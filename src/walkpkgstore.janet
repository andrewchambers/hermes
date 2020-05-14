(import jdn)
(import path)

(defn walk-store-closure
  [roots &opt f]

  (def ref-work-q @[])
  (def visited @{})

  (defn- enqueue
    [ref]
    (unless (in visited ref)
      (put visited ref true)
      (array/push ref-work-q ref)))

  (var hpkg-path nil)

  (each root roots 
    (def abs-path (os/realpath root))
    (def pkg-ref (path/basename abs-path))
    (def root-hpkg-path (string/slice abs-path 0 (- -2 (length pkg-ref))))
    (if-not hpkg-path
      (set hpkg-path root-hpkg-path)
      (unless (= root-hpkg-path hpkg-path)
        (error "unable to walk closure roots from different package stores")))
    (enqueue (path/basename abs-path)))
  
  (if (nil? hpkg-path)
    (assert (empty? ref-work-q))
    (unless (string/has-suffix? "/hpkg" hpkg-path)
      (error "unable to walk closure outside of $STORE/hpkg")))

  (defn walk-store-closure []
    (unless (empty? ref-work-q)
      (def ref (array/pop ref-work-q))
      (def pkg-path (string hpkg-path "/" ref))
      (def pkg-info (jdn/decode (slurp (string pkg-path "/.hpkg.jdn"))))
      (def new-refs
        (if-let [forced-refs (pkg-info :force-refs)]
          forced-refs
          (let [unfiltered-refs (array/concat @[]
                                  (pkg-info :scanned-refs)
                                  (get pkg-info :extra-refs []))]
            (if-let [weak-refs (pkg-info :weak-refs)]
              (do
                (def weak-refs-lut (reduce |(put $0 $1 true) @{} weak-refs))
                (filter weak-refs-lut unfiltered-refs))
              unfiltered-refs))))
        (when f
          (f pkg-path pkg-info new-refs))
      (each ref new-refs
        (enqueue ref))
      (walk-store-closure)))
  (walk-store-closure)
  visited)

(defn walk-pkgs
  [pkgs &opt f]
  (walk-store-closure (map |(in $ :path))) f)