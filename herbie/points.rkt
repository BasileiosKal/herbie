#lang racket

(require math/flonum)
(require math/bigfloat)
(require math/distributions)
(require "common.rkt")
(require "programs.rkt")
(require "config.rkt")

(provide *pcontext* in-pcontext mk-pcontext pcontext?
	 sample-expbucket sample-double sample-float sample-default
	 sample-uniform sample-integer sample-list
         prepare-points prepare-points-period make-exacts
         errors errors-score sorted-context-list sort-context-on-expr)

(provide (all-defined-out))

(define *pcontext* (make-parameter #f))

(struct pcontext (points exacts))

(define (in-pcontext context)
  (in-parallel (in-vector (pcontext-points context)) (in-vector (pcontext-exacts context))))

(define (mk-pcontext points exacts)
  (pcontext (if (list? points)
		(begin (assert (not (null? points)))
		       (list->vector points))
		(begin (assert (not (= 0 (vector-length points))))
		       points))
	    (if (list? exacts)
		(begin (assert (not (null? exacts)))
		       (list->vector exacts))
		(begin (assert (not (= 0 (vector-length exacts))))
		       exacts))))

(define (sorted-context-list context vidx)
  (let ([p&e (sort (for/list ([(pt ex) (in-pcontext context)]) (cons pt ex))
		   < #:key (compose (curryr list-ref vidx) car))])
    (list (map car p&e) (map cdr p&e))))

(define (sort-context-on-expr context expr variables)
  (let ([p&e (sort (for/list ([(pt ex) (in-pcontext context)]) (cons pt ex))
		   < #:key (λ (p&e)
			     (let* ([expr-prog `(λ ,variables ,expr)]
				    [float-val ((eval-prog expr-prog mode:fl) (car p&e))])
			       (if (ordinary-float? float-val) float-val
				   ((eval-prog expr-prog mode:bf) (car p&e))))))])
    (list (map car p&e) (map cdr p&e))))

(define (sample-expbucket num)
  (let ([bucket-width (/ (- 256 2) num)]
        [bucket-bias (- (/ 256 2) 1)])
    (for/list ([i (range num)])
      (expt 2 (- (* bucket-width (+ i (random))) bucket-bias)))))

(define (random-single-flonum)
  (floating-point-bytes->real (integer->integer-bytes (random-exp 32) 4 #f)))

(define (random-double-flonum)
  (floating-point-bytes->real (integer->integer-bytes (random-exp 64) 8 #f)))

(define (sample-float num)
  (for/list ([i (range num)])
    (real->double-flonum (random-single-flonum))))

(define (sample-double num)
  (for/list ([i (range num)])
    (real->double-flonum (random-double-flonum))))

(define (sample-default n) (((flag 'sample 'double) sample-double sample-float) n))

(define ((sample-uniform a b) num)
  (build-list num (λ (_) (+ (* (random) (- b a)) a))))

(define (mag-sqrt x)
  (if (negative? x)
      (- (sqrt (- x)))
      (sqrt x)))

;; This sampler returns num lists, with each list having a length
;; produced by length-sampler, an average produced mean-sampler, and a
;; ratio between the mean and the standard deviation produced by
;; deviation-ratio-sampler.
(define ((sample-list length-sampler mean-sampler deviation-ratio-sampler) num)
  ;; For each list we want to produce, use our samplers to produce
  ;; length, mean, and deviation ratios, and iterate through them.
  (for/list ([lst-length (length-sampler num)] [mean (mean-sampler num)]
	     [deviation-ratio (deviation-ratio-sampler num)])
    (let* ([deviation (* deviation-ratio mean)])
      (sample (normal-dist mean deviation) lst-length))))

;; For testing the previous function
(define (standard-deviation lst)
  (let* ([mean (/ (apply + lst) (length lst))]
	 [deviations (map (compose sqr (curry - mean)) lst)])
    (sqrt (/ (apply + deviations) (length lst)))))

(define (sample-integer num)
  (build-list num (λ (_) (- (random-exp 32) (expt 2 31)))))

(define (make-period-points num periods)
  (let ([points-per-dim (floor (exp (/ (log num) (length periods))))])
    (apply list-product
	   (map (λ (prd)
		  (let ([bucket-width (/ prd points-per-dim)])
		    (for/list ([i (range points-per-dim)])
		      (+ (* i bucket-width) (* bucket-width (random))))))
		periods))))

(define (select-every skip l)
  (let loop ([l l] [count skip])
    (cond
     [(null? l) '()]
     [(= count 0)
      (cons (car l) (loop (cdr l) skip))]
     [else
      (loop (cdr l) (- count 1))])))

(define (make-exacts* prog pts)
  (let ([f (eval-prog prog mode:bf)] [n (length pts)])
    (let loop ([prec (- (bf-precision) (*precision-step*))]
               [prev #f])
      (bf-precision prec)
      (let ([curr (map f pts)])
        (if (and prev (andmap =-or-nan? prev curr))
            curr
            (loop (+ prec (*precision-step*)) curr))))))

(define (make-exacts prog pts)
  (define n (length pts))
  (let loop ([n* 16]) ; 16 is arbitrary; *num-points* should be n* times a power of 2
    (cond
     [(>= n* n)
      (make-exacts* prog pts)]
     [else
      (make-exacts* prog (select-every (round (/ n n*)) pts))
      (loop (* n* 2))])))

(define (filter-points pts exacts)
  "Take only the points for which the exact value is normal, and the point is normal"
  (reap (sow)
    (for ([pt pts] [exact exacts])
      (when (and (ordinary-float? exact) (andmap ordinary-arg? pt))
        (sow pt)))))

(define (filter-exacts pts exacts)
  "Take only the exacts for which the exact value is normal, and the point is normal"
  (reap (sow)
    (for ([pt pts] [exact exacts])
      (when (and (ordinary-float? exact) (andmap ordinary-arg? pt))
	(sow exact)))))

(define (ordinary-arg? x)
  (cond [(list? x) (andmap ordinary-arg? x)]
	[#t (ordinary-float? x)]))

; These definitions in place, we finally generate the points.

(define (prepare-points prog samplers)
  "Given a program, return two lists:
   a list of input points (each a list of flonums or lists of flonums)
   and a list of exact values for those points (each a flonum)"

  ; First, we generate points;
  (let loop ([pts '()] [exs '()])
    (if (>= (length pts) (*num-points*))
        (mk-pcontext (take pts (*num-points*)) (take exs (*num-points*)))
        (let* ([num (- (*num-points*) (length pts))]
               [pts1 (filter ordinary-arg? (flip-lists (for/list ([rec samplers]) ((cdr rec) num))))]
               [exs1 (make-exacts prog pts1)]
               ; Then, we remove the points for which the answers
               ; are not representable
               [pts* (filter-points pts1 exs1)]
               [exs* (filter-exacts pts1 exs1)])
          (loop (append pts* pts) (append exs* exs))))))

(define (prepare-points-period prog periods)
  (let* ([pts (make-period-points (*num-points*) periods)]
	 [exacts (make-exacts prog pts)]
	 [pts* (filter-points pts exacts)]
	 [exacts* (filter-exacts pts exacts)])
    (mk-pcontext pts* exacts*)))

(define (errors prog pcontext)
  (let ([fn (eval-prog prog mode:fl)]
	[max-ulps (expt 2 (*bit-width*))])
    (for/list ([(point exact) (in-pcontext pcontext)])
      (let ([out (fn point)])
	(add1
	 (if (real? out)
	     (abs (ulp-difference out exact))
	     max-ulps))))))

(define (errors-score e)
  (let-values ([(reals unreals) (partition ordinary-float? e)])
    (if ((flag 'reduce 'avg-error) #f #t)
        (apply max (map ulps->bits reals))
        (/ (+ (apply + (map ulps->bits reals))
              (* (*bit-width*) (length unreals)))
           (length e)))))
