(import hermes)

(def pkg1
  (hermes/pkg
    :builder (fn [] nil)))

(def pkg2
  (hermes/pkg
    :builder (fn [] (pp pkg1))))

(hermes/pkg-hash pkg1)
(hermes/pkg-hash pkg2)

(pp (pkg1 :hash))
(pp (pkg1 :path))


(pp (pkg2 :path))
(pp (hermes/build-order pkg2))