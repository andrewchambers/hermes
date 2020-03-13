(import ./build/_x)
(import sh)
(import path)

(defn- save-env
  []
  {:cwd (os/cwd)
   :environ (os/environ)})

(defn- restore-env
  [{:cwd cwd
    :environ environ}]
  (eachk k environ
     (os/setenv k (environ k)))
  (os/cd cwd))

(defn- build-one
  [pkg]
  (def pkgout (pkg :path))
  (def pkg-info-path (path/join pkgout ".xpkg.jdn"))
  (when (not (os/stat pkg-info-path))

  (when (os/stat pkgout)
    (sh/$ ["rm" "-vrf" pkgout]))
  (sh/$ ["mkdir" "-pv" pkgout])
  (def env (save-env))
  (defer (restore-env env)
    # Wipe env so package builds
    # don't accidentally rely on any state.
    (eachk k (env :environ)
      (os/setenv k nil))
    (os/cd pkgout)
    (with-dyns [:pkgout pkgout]
      # TODO Work out how to privsep builder.
      # Marshal builder to different process?
      ((pkg :builder))))
  
  # TODO Freeze package on disk nix style
  # TODO Scan for package dependencies references
  # and write the gc roots.
  # TODO write other hermes attributes in jdn format.
  # Force roots, ignore roots etc.
  (let [tmp-info (string pkg-info-path ".tmp")]
    (spit tmp-info "Some bogus info...")
    (os/rename tmp-info pkg-info-path)))

  pkgout)

(defn build-order
  [pkg]
  (defn build-order2
    [pkg visited out]
    (if (visited pkg)
      nil
      (let [deps (_x/direct-dependencies pkg)]
        (put visited pkg true)
        (eachk dep deps
          (build-order2 dep visited out))
        (array/push out pkg))))
  (def out @[])
  (build-order2 pkg @{} out)
  out)

(defn build
  [pkg]
  # TODO flocking
  (def all-dependencies (build-order pkg))
  (each pkg all-dependencies
    (build-one pkg)))

(defn pkg
  [&keys {
    :builder builder
  }]
  (_x/pkg builder))

(def my-pkg1
  (pkg
    :builder
    (fn []
      (spit (string (dyn :pkgout) "/hello1.txt") "hello world 1!"))))

(def my-pkg2
  (pkg
    :builder
    (fn []
      (spit (string (dyn :pkgout) "/hello2.txt") (my-pkg1 :path)))))


(build my-pkg2)