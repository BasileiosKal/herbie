#lang racket
(require herbie/test)

; Multiphoton states related via linear optics
; P. Migdal, J. Rodrigues-Laguna, M. Oszmaniec, M. Lewenstein
; Phys. Rev. A 89, 062329 (2014), http://journals.aps.org/pra/abstract/10.1103/PhysRevA.89.062329

(casio-test (k n)
  "Migdal et al, Equation (51)"
  (* (/ (sqrt k)) (expt (* 2 pi n) (/ (- 1 k) 2))))

(casio-test (a1 a2 th)
  "Migdal et al, Equation (64)"
  (+ (* (/ (cos th) (sqrt 2)) (sqr a1))
     (* (/ (cos th) (sqrt 2)) (sqr a2))))
