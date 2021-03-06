#lang racket

(require (only-in xml write-xexpr xexpr?))
(require "../points.rkt" "../float.rkt" "../alternative.rkt" "../interface.rkt"
         "../syntax/rules.rkt" "../core/regimes.rkt" "../common.rkt" "tex.rkt")
(provide render-history)

(define (split-pcontext pcontext splitpoints alts repr)
  (define preds (splitpoints->point-preds splitpoints alts repr))

  (for/list ([pred preds])
    (define-values (pts* exs*)
      (for/lists (pts exs)
          ([(pt ex) (in-pcontext pcontext)] #:when (pred pt))
        (values pt ex)))

    ;; TODO: The (if) here just corrects for the possibility that we
    ;; might have sampled new points that include no points in a given
    ;; regime. Instead it would be best to continue sampling until we
    ;; actually have many points in each regime. That would require
    ;; breaking some abstraction boundaries right now so we haven't
    ;; done it yet.
    (if (null? pts*) pcontext (mk-pcontext pts* exs*))))

(struct interval (alt-idx start-point end-point expr))

(define (interval->string ival repr)
  (define start (interval-start-point ival))
  (define end (interval-end-point ival))
  (string-join
   (list
    (if start
        (format "~a < " (repr->fl start repr))
        "")
    (~a (interval-expr ival))
    (if (equal? end +nan.0)
        ""
        (format " < ~a" (repr->fl end repr))))))

(define/contract (render-history altn pcontext pcontext2 repr)
  (-> alt? pcontext? pcontext? representation? (listof xexpr?))
  (define err
    (format-bits (errors-score (errors (alt-program altn) pcontext repr))))
  (define err2
    (format "Internally ~a" (format-bits (errors-score (errors (alt-program altn) pcontext2 repr)))))

  (match altn
    [(alt prog 'start (list))
     (list
      `(li (p "Initial program " (span ([class "error"] [title ,err2]) ,err))
           (div ([class "math"]) "\\[" ,(texify-prog prog repr) "\\]")))]
    [(alt prog `(start ,strategy) `(,prev))
     `(,@(render-history prev pcontext pcontext2 repr)
       (li ([class "event"]) "Using strategy " (code ,(~a strategy))))]

    [(alt _ `(regimes ,splitpoints) prevs)
     (define intervals
       (for/list ([start-sp (cons (sp -1 -1 #f) splitpoints)] [end-sp splitpoints])
         (interval (sp-cidx end-sp) (sp-point start-sp) (sp-point end-sp) (sp-bexpr end-sp))))

     `((li ([class "event"]) "Split input into " ,(~a (length prevs)) " regimes")
       (li
        ,@(apply
           append
           (for/list ([entry prevs] [idx (in-naturals)]
                      [new-pcontext (split-pcontext pcontext splitpoints prevs repr)]
                      [new-pcontext2 (split-pcontext pcontext splitpoints prevs repr)])
             (define entry-ivals (filter (λ (intrvl) (= (interval-alt-idx intrvl) idx)) intervals))
             (define condition (string-join (map (curryr interval->string repr) entry-ivals) " or "))
             `((h2 (code "if " (span ([class "condition"]) ,condition)))
               (ol ,@(render-history entry new-pcontext new-pcontext2 repr))))))
       (li ([class "event"]) "Recombined " ,(~a (length prevs)) " regimes into one program."))]

    [(alt prog `(taylor ,pt ,loc) `(,prev))
     `(,@(render-history prev pcontext pcontext2 repr)
       (li (p "Taylor expanded around " ,(~a pt) " " (span ([class "error"] [title ,err2]) ,err))
           (div ([class "math"]) "\\[\\leadsto " ,(texify-prog prog repr #:loc loc
                                                               #:color "blue") "\\]")))]

    [(alt prog `(simplify ,loc) `(,prev))
     `(,@(render-history prev pcontext pcontext2 repr)
       (li (p "Simplified" (span ([class "error"] [title ,err2]) ,err))
           (div ([class "math"]) "\\[\\leadsto " ,(texify-prog prog repr #:loc loc
                                                               #:color "blue") "\\]")))]

    [(alt prog `initial-simplify `(,prev))
     `(,@(render-history prev pcontext pcontext2 repr)
       (li (p "Initial simplification" (span ([class "error"] [title ,err2]) ,err))
           (div ([class "math"]) "\\[\\leadsto " ,(texify-prog prog repr) "\\]")))]

    [(alt prog `final-simplify `(,prev))
     `(,@(render-history prev pcontext pcontext2 repr)
       (li (p "Final simplification" (span ([class "error"] [title ,err2]) ,err))
           (div ([class "math"]) "\\[\\leadsto " ,(texify-prog prog repr) "\\]")))]

    [(alt prog (list 'change cng) `(,prev))
     `(,@(render-history prev pcontext pcontext2 repr)
       (li (p "Applied " (span ([class "rule"]) ,(~a (rule-name (change-rule cng))))
              (span ([class "error"] [title ,err2]) ,err))
           (div ([class "math"]) "\\[\\leadsto " ,(texify-prog prog repr #:loc (change-location cng) #:color "blue") "\\]")))]
    ))
