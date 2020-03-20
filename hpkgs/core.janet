
(def bootstrap
  (pkg
    :out-hash
    "sha256:b4c6762f7c715e3884f89315961ae7812f5fa1c4151dd390dbbf2e77ff6f7568"
    :builder
    (fn []
      (unpack
        (fetch "https://github.com/andrewchambers/hpkgs-seeds/raw/v0.0.1/linux-x86_64-seed.tar.gz")
        (dyn :pkg-out)))))

(defn core-src
  [&keys {:url url :hash hash}]
  (def fname (last (string/split "/" url))) # XXX rfind would be nice in stdlib.
  (pkg
    :builder
      (fn []
        (fetch url (string (dyn :pkg-out) "/" fname)))
    :out-hash
      hash))

(defn core-pkg
  [&keys {:src-url src-url :src-hash src-hash}]
  (def src (core-src :url src-url :hash src-hash))
  (pkg
    :builder
    (fn []
      (os/setenv "PATH" (string (bootstrap :path) "/bin"))
      (sh/$ ["sh" "-c" (string "tar -avxf " (src :path) "/*")])
      (os/setenv "CC" "x86_64-linux-musl-cc")
      (os/setenv "LDFLAGS" "-O2 -static")
      (sh/$ ["sh" "./configure" (dyn :pkg-out)])
      (sh/$ ["make"])
      (sh/$ ["make" "install"]))))

(def coreutils
  (core-pkg
    :src-url
    "https://ftp.gnu.org/gnu/coreutils/coreutils-8.31.tar.xz"
    :src-hash
    "sha256:b812a9a95a7de00367309940f39cf822c5b5e749b18e78fa045694872828a146"))
