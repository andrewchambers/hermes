(import base16)
(import sh)
(import _hermes)

(def store-path "/tmp/hpkgs")

(defn- assert-path-hash
  [path hash]
  (match (string/split ":" hash)
    ["sha256" hash]
      (do
        (def path (string path))
        (def sha256sum-bin (comptime (string (sh/$$_ ["which" "sha256sum"]))))
        (def actual-hash
           (as-> (sh/$$_ [sha256sum-bin path]) _
              (string _)
              (string/split " " _)
              (first _)))
        (unless (= hash actual-hash)
          (error (string/format "expected %v to have hash sha256:%s got sha256:%s" path hash actual-hash))))
    _ 
      (error (string "unsupported hash format - " hash)))
    nil)

(defn- fetch
  [&keys {
    :url url
    :hash hash
    :dest dest
  }]
  (default hash "sha256:unknown")
  (def url
    (if (or (string/has-prefix? "." url)
            (string/has-prefix? "/" url))
      (do
        (def tar-bin (comptime (string (sh/$$_ ["which" "readlink"]))))
        (string "file://" (sh/$ ["readlink" "-f" url])))
      url))
  (def curl-bin (comptime (string (sh/$$_ ["which" "curl"]))))
  (sh/$ [curl-bin "-L" "-o" dest url])
  (assert-path-hash dest hash))

(defn- unpack
  [&keys {
    :path path
    :dest dest
  }]
  (def tar-bin (comptime (string (sh/$$_ ["which" "tar"]))))
  (sh/$ ["tar" "-vxzf" path "-C" dest]))

(def builder-env (make-env root-env))
(put builder-env 'pkg
  @{:value (fn [&] (error "pkg cannot be invoked inside a builder"))})
(put builder-env 'fetch  @{:value fetch})
(put builder-env 'unpack @{:value unpack})
(put builder-env 'sh/$   @{:value sh/$})
(put builder-env 'sh/$$  @{:value sh/$$})
(put builder-env 'sh/$$_ @{:value sh/$$_})
(put builder-env 'sh/$?  @{:value sh/$?})
(def builder-load-registry (env-lookup builder-env))
(def builder-registry (invert builder-load-registry))

(defn pkg
  [&keys {
    :name name
    :builder builder
  }]
  (default name "")

  (unless (string? name)
    (error (string/format ":name must be a string, got %v" name)))

  (unless (function? builder)
    (error (string/format ":builder must be a function, got %v" builder)))

  (def hash
    (_hermes/pkg-hash store-path builder-registry builder name))

  (def pkg-path
    (string store-path "/pkgs/" (base16/encode hash)))

  (def marshalled-builder (string (marshal builder builder-registry)))

  (_hermes/pkg hash builder marshalled-builder name pkg-path))

(def user-env (make-env root-env))
(put user-env 'pkg    @{:value pkg})
(put user-env 'fetch  @{:value fetch})
(put user-env 'unpack @{:value unpack})
(put user-env 'sh/$   @{:value sh/$})
(put user-env 'sh/$$  @{:value sh/$$})
(put user-env 'sh/$$_ @{:value sh/$$_})
(put user-env 'sh/$?  @{:value sh/$?})

(defn build-order
  [pkg]
  (defn build-order2
    [pkg visited out]
    (if (visited pkg)
      nil
      (let [deps (_hermes/pkg-dependencies pkg)]
        (put visited pkg true)
        (eachk dep deps
          (build-order2 dep visited out))
        (array/push out pkg))))
  (def out @[])
  (build-order2 pkg @{} out)
  out)

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
  (def pkg-out (pkg :path))
  (def pkg-info-path (string pkg-out "/.xpkg.jdn"))
  (when (not (os/stat pkg-info-path))

    (when (os/stat pkg-out)
      (sh/$ ["chmod" "-v" "-R" "u+w" pkg-out])
      (sh/$ ["rm" "-vrf" pkg-out]))
    (sh/$ ["mkdir" "-v" pkg-out])
    (def env (save-env))
    (def tmpdir (string (sh/$$_ ["mktemp" "-d"])))
    (defer (do
             (restore-env env)
             (sh/$ ["chmod" "-R" "u+w" tmpdir])
             (sh/$ ["rm" "-rf" tmpdir]))
      # Wipe env so package builds
      # don't accidentally rely on any state.
      (eachk k (env :environ)
        (os/setenv k nil))
      (os/cd tmpdir)
      (with-dyns [:pkg-out pkg-out]
        (def builder (unmarshal (pkg :frozen-builder) builder-load-registry))
        (builder)))
    
    # TODO Scan for package dependencies references
    
    (let [tmp-info (string pkg-info-path ".tmp")]
      (spit tmp-info "Some bogus info...")
      (os/rename tmp-info pkg-info-path))

    # Set package permissions.
    (sh/$ ["chmod" "-v" "-R" "a-w,a+r,a+X" pkg-out]))

  # TODO Mark package complete.

  pkg-out)

(defn build
  [pkg]
  # TODO flocking
  (def all-dependencies (build-order pkg))
  (each pkg all-dependencies
    (build-one pkg)))