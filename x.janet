(import ./build/_x)
(import base16)
(import path)
(import sh)

(def *store-path* "/tmp/xstore")
(def *hash-cache* @{})


(defn save-env
  []
  {:cwd (os/cwd)
   :environ (os/environ)})

(defn restore-env
  [{:cwd cwd
    :environ environ}]
  (eachk k environ
     (os/setenv k (environ k)))
  (os/cd cwd))

(defn build
  [pkg]
  (assert (struct? pkg))
  (assert (function? (pkg :builder)))

  (def pkgout (do
                (def hash (base16/encode (_x/hash *hash-cache* (pkg :builder))))
                (path/join *store-path* hash)))

  (def pkg-info-path (path/join pkgout ".xpkg.jdn"))
  # TODO flocking.
  (when (os/stat pkgout)
    (sh/$ ["rm" "-vrf" pkgout]))
  (sh/$ ["mkdir" "-pv" pkgout])
  (def env (save-env))
  (defer (restore-env env)
    (when (not (os/stat pkg-info-path))
      (do
        (os/cd pkgout)
        (with-dyns [:pkgout pkgout]
          ((pkg :builder))))))
  
  # TODO Scan for package dependencies references
  # and write the gc roots.
  # TODO write other hermes attributes in jdn format.
  # Force roots, ignore roots etc.
  (let [tmp-info (string pkg-info-path ".tmp")]
    (spit tmp-info "Some bogus info...")
    (os/rename tmp-info pkg-info-path))
  pkgout)


(def my-pkg {
  :builder
  (fn pkg []
    (print "Building package!")
    (spit (path/join (dyn :pkgout) "hello.txt") "hello world!"))
})


@{:}

(pp (build my-pkg))