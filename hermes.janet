(import sh)
(import _hermes)

(def store-path "/tmp/hpkgs")

(defn assert-dir-hash
  [path expected]
  
  (def sha256sum-bin (comptime (string (sh/$$_ ["which" "sha256sum"]))))
  
  (defn dir-hash
    [hasher path]
    (def wd (os/cwd))
    (defer (os/cd wd)
      (os/cd path)
      (sh/$$
        (sh/pipeline [
          ["find" "." "-print0"]
          ["sort" "-z"]
          ["tar"
            "-c"
            "-f" "-"
            "--numeric-owner"
            "--owner=0"
            "--group=0"
            "--mode=go-rwx,u-rw"
            "--mtime=1970-01-01"
            "--no-recursion"
            "--null"
            "--files-from" "-"]
          hasher
        ]))))

    (def actual
      (match (string/split ":" expected)
        ["sha256" _]
          (do
            (def actual
              (as-> [sha256sum-bin "-b" "-"] _
                    (dir-hash _ path)
                    (string/split " " _)
                    (first _)))
            (string "sha256:" actual))
        _ 
          (error (string "unsupported hash format - " expected))))

    (unless (= expected actual)
        (error (string/format "expected %v to have hash %s but got %s" path expected actual))))

(defn- fetch
  [url &opt dest]
  (def url
    (if (or (string/has-prefix? "." url)
            (string/has-prefix? "/" url))
      (do
        (def tar-bin (comptime (string (sh/$$_ ["which" "readlink"]))))
        (string "file://" (sh/$ ["readlink" "-f" url])))
      url))
  (default dest (last (string/split "/" url)))
  (def curl-bin (comptime (string (sh/$$_ ["which" "curl"]))))
  (sh/$ [curl-bin "-L" "-o" dest url])
  dest)

(defn- unpack
  [path &opt dest &keys {
    :strip nstrip
  }]
  (default dest "./")
  (default nstrip 0)
  (unless (os/stat dest)
    (os/mkdir dest))
  (def tar-bin (comptime (string (sh/$$_ ["which" "tar"]))))
  (sh/$ [tar-bin (string "--strip-components=" nstrip) "-avxf" path "-C" dest]))

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

(defn pkg-hash
  [pkg]
  (_hermes/pkg-hash store-path builder-registry pkg))

(defn pkg
  [&keys {
    :builder builder
    :name name
    :out-hash out-hash
  }]
  (_hermes/pkg builder name out-hash))

(def user-env (make-env root-env))
(put user-env 'pkg    @{:value pkg})
(put user-env 'fetch  @{:value fetch})
(put user-env 'unpack @{:value unpack})
(put user-env 'sh/$   @{:value sh/$})
(put user-env 'sh/$$  @{:value sh/$$})
(put user-env 'sh/$$_ @{:value sh/$$_})
(put user-env 'sh/$?  @{:value sh/$?})

(defn load-pkgs
  [fpath]
  (dofile fpath :env user-env))

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


(defn build
  [pkg]

  (def registry (merge-into @{} builder-registry))
  (def load-registry (invert registry))
  (put load-registry '*pkg-already-built* (fn [&] nil))

  (defn- build-one
    [pkg]
    (def out-hash (pkg :out-hash))
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
          (def frozen-builder (marshal (pkg :builder) registry))
          (def builder (unmarshal frozen-builder load-registry))
          (builder)))
      
      # TODO Scan for package dependencies references

      (when out-hash
        (assert-dir-hash pkg-out out-hash))
      
      (let [tmp-info (string pkg-info-path ".tmp")]
        (spit tmp-info "Some bogus info...")
        (os/rename tmp-info pkg-info-path))

      # Set package permissions.
      (sh/$ ["chmod" "-v" "-R" "a-w,a+r,a+X" pkg-out]))

    # TODO Mark package complete.

    pkg-out)

  # TODO flocking
  (def all-dependencies (build-order pkg))
  (each pkg all-dependencies
    (print "building pkg: " pkg)
    (pkg-hash pkg)
    (build-one pkg)
    (put registry (pkg :builder) '*pkg-already-built*))
  (pkg :path))