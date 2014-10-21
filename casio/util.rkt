#lang racket

(require casio/points)
(require casio/alternative)
(require casio/common)
(require casio/matcher)
(require casio/programs)
(require casio/main)
(require casio/simplify/egraph)
(require casio/rules)

(provide (all-defined-out))

(define (saturate-iters expr)
  (let ([eg (mk-egraph expr)])
    (let loop ([iters-done 1])
      (let ([start-cnt (egraph-cnt eg)])
	(one-iter eg *simplify-rules*)
	(printf "Did iter #~a, have ~a nodes.~n" iters-done (egraph-cnt eg))
	(if (> (egraph-cnt eg) start-cnt)
	    (loop (add1 iters-done))
	    (sub1 iters-done))))))

(define (print-improve prog max-iters)
  (match-let ([`(,end-prog ,context) (improve prog max-iters #:get-context #t)])
    (parameterize ([*pcontext* context])
      (let ([start (make-alt prog)]
	    [end (make-alt end-prog)])
        (println "Started at: " start)
        (println "Ended at: " end)
        (println "Improvement by an average of "
                 (- (errors-score (alt-errors start)) (errors-score (alt-errors end)))
                 " bits of precision")
        (void)))))

(define (setup prog)
  (define pcontext (prepare-points prog (for/list ([var (program-variables prog)])
					  (cons var sample-float))))
  (*pcontext* pcontext)
  (void))

(define (repl-print x)
  (begin (println x) (void)))

(define (prog-improvement prog1 prog2)
  (let-values ([(points exacts) (prepare-points prog1)])
    (- (errors-score (errors prog1 points exacts)) (errors-score (errors prog2 points exacts)))))

(define (annotated-alts-compare alt1 alt2)
  (match-let ([(list pts exs) (sorted-context-list (*pcontext*) 0)])
    (parameterize ([*pcontext* (mk-pcontext pts exs)])
      (annotated-errors-compare (alt-errors alt1) (alt-errors alt2)))))

(define (annotated-errors-compare errs1 errs2)
  (repl-print
   (reverse
    (first-value
     (for/fold ([acc '()] [region #f])
	 ([err-diff (for/list ([e1 errs1] [e2 errs2])
		      (cond [(> e1 e2) '>]
			    [(< e1 e2) '<]
			    [#t '=]))]
	  [(pt _) (in-pcontext (*pcontext*))])
       (if (eq? region err-diff)
	   (values (cons err-diff acc)
		   region)
	   (values (cons (cons pt err-diff) acc)
		   err-diff)))))))

(define (compare-alts . altns)
  (repl-print
   (reverse
    (first-value
     (for/fold ([acc '()] [region-idx -1])
	 ([(pt ex) (in-pcontext (*pcontext*))]
	  [errs (flip-lists (map alt-errors altns))])
       (let ([best-idx
	      (argmin (curry list-ref errs) (range (length altns)))])
	 (if (= best-idx region-idx)
	     (values (cons best-idx acc) region-idx)
	     (values (cons (list best-idx (list-ref altns best-idx) pt)
			   acc)
		     best-idx))))))))

(define (print-alt-info altn)
  (if (not (alt-prev altn))
      (println "Started with: " (alt-program altn))
      (begin (print-alt-info (alt-prev altn))
             (let ([chng (alt-change altn)])
               (println "Applied rule " (change-rule chng)
                        " at " (change-location chng)
                        " [ " (location-get (change-location chng)
                                            (alt-program (alt-prev altn)))
                        " ], and got:" (alt-program altn))
               (void)))))

(define (incremental-changes-apply changes expr)
  (let loop ([rest-chngs changes] [cur-expr expr])
    (if (null? rest-chngs)
	cur-expr
	(begin (println cur-expr)
	       (println (car rest-chngs))
	       (loop (cdr rest-chngs) (change-apply (car rest-chngs) cur-expr))))))
