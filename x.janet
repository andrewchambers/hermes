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
  (def pkg-out (pkg :path))
  (def pkg-info-path (path/join pkg-out ".xpkg.jdn"))
  (when (not (os/stat pkg-info-path))

    (when (os/stat pkg-out)
      (sh/$ ["chmod" "-v" "-R" "u+w" pkg-out])
      (sh/$ ["rm" "-vrf" pkg-out]))
    (sh/$ ["mkdir" "-pv" pkg-out])
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
        # TODO Work out how to privsep builder.
        # Marshal builder to different process?
        ((pkg :builder))))
    
    # TODO Scan for package dependencies references
    
    (let [tmp-info (string pkg-info-path ".tmp")]
      (spit tmp-info "Some bogus info...")
      (os/rename tmp-info pkg-info-path))

    # Set package permissions.
    (sh/$ ["chmod" "-v" "-R" "a-w,a+r,a+X" pkg-out]))

  # TODO Mark package complete.

  pkg-out)

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
    :name name
    :builder builder
    :out-hash out-hash
  }]
  (_x/pkg builder name out-hash))

(defn dtar
  "Tar a directory into a 'deterministic tar'. The
  resulting tarball has lexically sorted filenames,
  fixed users, and only the executable bit is preserved.
  
  Out can be a file or buffer.

  returns outs."

  [path &opt out]
  (default out @"")
  (def wd (os/cwd))
  (defer (os/cd wd)
    (os/cd path)
    (sh/$
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
      ]) :redirects [[stdout out]]))
  out)

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

(defn fetch
  [&keys {
    :url url
    :hash hash
    :dest dest
  }]
  (default hash "sha256:unknown")
  (def url
    (if (or (string/has-prefix? "." url)
            (string/has-prefix? "/" url))
      (string "file://" (path/abspath url))
      url))
  # XXX fetch should work from within a sandbox.
  # in this can be done via a fetch protocol
  # over a unix socket. For out proof of concept
  # we just fake it.
  #
  # XXX In the final version, the hash of the download should be verified
  # via the sandbox server.
  (def curl-bin (comptime (string (sh/$$_ ["which" "curl"]))))
  (sh/$ [curl-bin "-L" "-o" dest url])
  (assert-path-hash dest hash))

(defn unpack
  [&keys {
    :path path
    :dest dest
  }]
  (def tar-bin (comptime (string (sh/$$_ ["which" "tar"]))))
  (sh/$ ["tar" "-vxzf" path "-C" dest]))

(def bootstrap
  (pkg
    :builder
    (fn []
      (fetch 
        :url "https://github.com/andrewchambers/hpkgs-seeds/raw/v0.0.1/linux-x86_64-seed.tar.gz"
        :hash "sha256:b224a5368310894d2e64a0ba4032b187098473865b02c0bbf55add35576070a8"
        :dest "./seed.tar.gz")
      (unpack
        :path "./seed.tar.gz"
        :dest (dyn :pkg-out)))))

(def amazing-package
  (pkg
    :builder
    (fn []
      (os/setenv "PATH" (string (bootstrap :path) "/bin"))
      (spit "./hello-world.c" ` 
        #include <stdio.h>
        int main () {
          printf("hello world!");
        }
      `)
      (def bindir (string (dyn :pkg-out) "/bin"))
      (sh/$ ["mkdir" bindir])
      (sh/$ ["x86_64-linux-musl-cc" "--static" "./hello-world.c" "-o" (string bindir "/hello")]))))

(build amazing-package)
(pp (amazing-package :path))