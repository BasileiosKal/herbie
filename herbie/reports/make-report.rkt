#lang racket

(require racket/date)
(require unstable/sequence)
(require "../compile/texify.rkt")
(require "../common.rkt")
(require "datafile.rkt")
(provide (all-defined-out))

(provide make-report-page)

(define (format-time ms)
  (cond
   [(< ms 1000) (format "~a ms" (round ms))]
   [(< ms 60000) (format "~a s" (/ (round (/ ms 100.0)) 10))]
   [(< ms 3600000) (format "~a m" (/ (round (/ ms 6000.0)) 10))]
   [else (format "~a hr" (/ (round (/ ms 360000.0)) 10))]))

(define (display-bits r #:sign [sign #f])
  (cond
   [(not r) ""]
   [(and (r . > . 0) sign) (format "+~a" (/ (round (* r 10)) 10))]
   [else (format "~a" (/ (round (* r 10)) 10))]))

(define (make-report-page file info)
  (match info
    [(report-info date commit branch seed flags points iterations bit-width note tests)

     (define table-labels
       '("Test" "Start" "Result" "Target" "∞ ↔ ℝ" "Time"))

     (define-values (dir _name _must-be-dir?) (split-path file))

     (copy-file "herbie/reports/report.js" (build-path dir "report.js") #t)
     (copy-file "herbie/reports/report.css" (build-path dir "report.css") #t)
     (copy-file "herbie/reports/graph.css" (build-path dir "graph.css") #t)
     (copy-file "herbie/reports/graph.js" (build-path dir "graph.js") #t)

     (define total-time (apply + (map table-row-time tests)))
     (define total-passed
       (for/sum ([row tests])
         (if (member (table-row-status row) '("gt-target" "eq-target" "imp-start")) 1 0)))
     (define total-available
       (for/sum ([row tests])
         (if (not (equal? (table-row-status row) "ex-start")) 1 0)))
     (define total-crashes
       (for/sum ([row tests])
         (if (equal? (table-row-status row) "crash") 1 0)))

     (define total-gained
       (for/sum ([row tests])
         (or (table-row-result row) 0)))
     (define total-start
       (for/sum ([row tests])
         (or (table-row-start row) 0)))

     (define (round* x)
       (inexact->exact (round x)))

     (write-file file
       ; HTML cruft
       (printf "<!doctype html>\n")
       (printf "<head>\n")
       (printf "<title>Herbie test results</title>\n")
       (printf "<meta charset='utf-8' />")
       (printf "<link rel='stylesheet' type='text/css' href='report.css' />")

       ; Scripts: the report script, MathJax, D3, and graph-drawing code
       (printf "<script src='report.js'></script>\n")
       (printf "<script src='~a'></script>" ; MathJax URL for prettifying programs
               "https://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML")
       (printf "<script src='http://d3js.org/d3.v3.min.js' charset='utf-8'></script>\n")
       (printf "<script type='text/javascript' src='graph.js'></script>\n")
       (printf "</head>\n")
       (printf "<body>\n")

       ; Big bold numbers
       (printf "<div id='large'>\n")
       (printf "<div>Time: <span class='number'>~a</span></div>\n"
               (format-time total-time))
       (printf "<div>Passed: <span class='number'>~a/~a</span></div>\n"
               total-passed total-available)
       (when (not (= total-crashes 0))
         (printf "<div>Crashes: <span class='number'>~a</span></div>\n"
                 total-crashes))
       (printf "<div>Tests: <span class='number'>~a</span></div>\n"
               (length tests))
       (printf "<div>Bits: <span class='number'>~a/~a</span></div>\n"
               (round* (- total-start total-gained)) (round* total-start))
       (printf "</div>\n")

       ; The graph
       (printf "<figure><svg id='graph' width='400'></svg>\n")
       (printf "<script>window.addEventListener('load', function(){draw_results(d3.select('#graph'))})</script>\n")
       (printf "</figure>\n")

       ; Test badges
       (printf "<ul id='test-badges'>\n")
       (define sorted-tests
         (sort (map cons tests (range (length tests))) >
               #:key (λ (x) (or (table-row-start (car x)) 0))))
       (for ([(result id) (in-pairs sorted-tests)])
         (printf "<li class='badge ~a' title='~a (~a to ~a)' data-id='~a'>~a</li>\n"
                 (table-row-status result)
                 (table-row-name result)
                 (display-bits (table-row-start result))
                 (display-bits (table-row-result result))
                 id
                 (match (table-row-status result)
                   ["crash" "ERR"]
                   ["timeout" "TIME"]
                   [_ (display-bits (- (table-row-start result) (table-row-result result)) #:sign #t)])))
       (printf "</ul>\n")
       (printf "<hr style='clear:both;visibility:hidden'>\n")

       ; Run stats
       (printf "<table id='about'>\n")
       (printf "<tr><th>Date:</th><td>~a</td></tr>\n" (date->string (current-date)))
       (printf "<tr><th>Commit:</th><td>~a on ~a</td></tr>\n" commit branch)
       (printf "<tr><th>Points:</th><td>~a</td></tr>\n" (*num-points*))
       (printf "<tr><th>Fuel:</th><td>~a</td></tr>\n" (*num-iterations*))
       (printf "<tr><th>Seed:</th><td>~a</td></tr>\n" seed)
       (printf "<tr><th>Flags:</th><td id='flag-list'>")
       (for ([rec (hash->list (*flags*))])
         (for ([fl (cdr rec)])
           (printf "<kbd>~a:~a</kbd>" (car rec) fl)))
       (printf "</td></tr>")
       (printf "</table>\n")

       ; Results table
       (printf "<table id='results'>\n")
       (printf "<thead><tr>")
       (for ([label table-labels])
         (printf "<th>~a</th>" label))
       (printf "</tr></thead>\n")
       (printf "</div>\n")

       (printf "<tbody>")
       (for ([result tests])
         (printf "<tr class='~a'>" (table-row-status result))

         (printf "<td>~a</td>" (or (table-row-name result) ""))
         (printf "<td>~a</td>" (display-bits (table-row-start result)))

         (if (and (table-row-result result) (table-row-result-est result)
                  (> (abs (- (table-row-result result) (table-row-result-est result))) 1))
             (printf "<td class='bad-est'>[~a ≉] ~a </td>"
                     (display-bits (table-row-result-est result))
                     (display-bits (table-row-result result)))
             (printf "<td>~a</td>" (display-bits (table-row-result result))))

         (printf "<td>~a</td>" (display-bits (table-row-target result)))
         (printf "<td>~a~a</td>"
                 (let ([inf- (table-row-inf- result)])
                   (if (and inf- (> inf- 0)) (format "+~a" inf-) ""))
                 (let ([inf+ (table-row-inf+ result)])
                   (if (and inf+ (> inf+ 0)) (format "-~a" inf+) "")))
         (printf "<td>~a</td>" (format-time (table-row-time result)))
         (if (table-row-link result)
           (printf "<td><a href='~a/graph.html'>more</a></td>" (table-row-link result))
           (printf "<td></td>"))
         (printf "<td>\\(~a\\)</td>" (or (texify-expression (table-row-input result)) ""))
         (printf "</tr>\n"))
       (printf "</tbody>\n")
       (printf "</table>\n")
       (printf "</body>\n")
       (printf "</html>\n"))

     ; Delete old files
     (let* ([expected-dirs (map string->path (filter identity (map table-row-link tests)))]
            [actual-dirs (filter (λ (name) (directory-exists? (build-path dir name))) (directory-list dir))]
            [extra-dirs (filter (λ (name) (not (member name expected-dirs))) actual-dirs)])
       (for ([subdir extra-dirs])
         (delete-directory/files (build-path dir subdir))))]))

(define (render-json file)
  (define info (read-datafile file))

  (when (not (directory-exists? report-output-path))
    (make-directory report-output-path))

  (make-report-page (build-path report-output-path "report.html") info))
