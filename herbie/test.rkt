#lang racket

(require "common.rkt")
(require "alternative.rkt")
(require "programs.rkt")
(require "points.rkt")
(require racket/runtime-path)

(provide (struct-out test) test-program test-samplers
         load-tests load-file)

(define (unfold-let expr)
  (match expr
    [`(let* ,vars ,body)
     (let loop ([vars vars] [body body])
       (if (null? vars)
           body
           (let ([var (caar vars)] [val (cadar vars)])
             (loop (map (replace-var var val) (cdr vars))
                   ((replace-var var val) body)))))]
    [`(,head ,args ...)
     (cons head (map unfold-let args))]
    [x
     x]))

(define (expand-associativity expr)
  (match expr
    [(list (? (curryr member '(+ - * /)) op) a ..2 b)
     (list op
           (expand-associativity (cons op a))
           (expand-associativity b))]
    [(list op a ...)
     (cons op (map expand-associativity a))]
    [_
     expr]))

(define ((replace-var var val) expr)
  (cond
   [(eq? expr var) val]
   [(list? expr)
    (cons (car expr) (map (replace-var var val) (cdr expr)))]
   [#t
    expr]))

(define (compile-program prog)
  (expand-associativity (unfold-let prog)))

(define (test-program test)
  `(λ ,(test-vars test) ,(test-input test)))

(struct test (name vars sampling-expr input output) #:prefab)

(define (get-op op)
  (match op ['> >] ['< <] ['>= >=] ['<= <=]))

(define (get-sampler expr)
  (match expr
    [(? procedure? f) f] ; This can only come up from internal recusive calls
    ['float sample-float]
    ['double sample-double]
    ['default sample-default]
    [`(positive ,e) (compose (curry map abs) (get-sampler e))]
    [`(uniform ,a ,b) (sample-uniform a b)]
    ['integer sample-integer]
    ['expbucket sample-expbucket]
    [`(,(and op (or '< '> '<= '>=)) ,a ,(? number? b))
     (let ([sa (get-sampler a)] [test (curryr (get-op op) b)])
       (λ (n) (for/list ([va (sa n)]) (if (test va) va +nan.0))))]
    [`(,(and op (or '< '> '<= '>=)) ,(? number? a) ,b)
     (let ([sb (get-sampler b)] [test (curry (get-op op) a)])
       (λ (n) (for/list ([vb (sb n)]) (if (test vb) vb +nan.0))))]
    [`(,(and op (or '< '> '<= '>=)) ,a ,b ...)
     ; The justification for this is that (< (< 0 float) 1) is interpreted as
     ; samples from (< 0 float) that are (< ? 1), which is just what we want
     (get-sampler `(,op ,a ,(get-sampler `(,op ,@b))))]))

(define (test-samplers test)
  (for/list ([var (test-vars test)] [samp (test-sampling-expr test)])
    (cons var (get-sampler samp))))

(define (parse-test expr)
  (define (var&dist expr)
    (match expr
      [(list var samp) (cons var samp)]
      [var (cons var 'default)]))

  (match expr
    [(list 'herbie-test (list vars ...) name input output)
     (let* ([parse-args (map var&dist vars)])
       (let ([vars (map car parse-args)] [samp (map cdr parse-args)])
         (test name vars samp (compile-program input) (compile-program output))))]
    [(list 'herbie-test (list vars ...) name input)
     (let* ([parse-args (map var&dist vars)])
       (let ([vars (map car parse-args)] [samp (map cdr parse-args)])
         (test name vars samp (compile-program input) #f)))]))

(define-runtime-path benchmark-path "../bench/")

(define (load-file p)
  (let ([fp (open-input-file p)])
    (let loop ()
      (let ([test (read fp)])
        (if (eof-object? test)
            '()
            (cons (parse-test test) (loop)))))))

(define (is-racket-file? f)
  (and (equal? (filename-extension f) #"rkt") (file-exists? f)))

(define (walk-tree p callback)
  (cond
   [(file-exists? p)
    (callback p)]
   [(directory-exists? p)
    (for ([obj (directory-list p #:build? #t)])
      (walk-tree obj callback))]))

(define (load-tests [path benchmark-path])
  (define (handle-file sow p)
    (when (is-racket-file? p)
      (sow (load-file p))))

  (apply append
         (reap [sow]
               (walk-tree path (curry handle-file sow)))))
