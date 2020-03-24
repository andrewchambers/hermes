
(def bootstrap
  (pkg
    :out-hash
      "sha256:f11c73f3b0c4a5939f2d67f4a2b401a7938ddc7d8c7c3515b4c53efdf03cc0ce"
    :builder
      (fn []
        (unpack
          (fetch
            "https://github.com/andrewchambers/hpkgs-seeds/raw/v0.0.1/linux-x86_64-seed.tar.gz")
            :dest (dyn :pkg-out))
        # XXX We should include these in the tarball once self hosting.
        (os/cd (string (dyn :pkg-out) "/bin"))
        (os/link "./x86_64-linux-musl-ar" "ar")
        (os/link "./x86_64-linux-musl-cc" "cc")
        (os/link "./x86_64-linux-musl-c++" "c++"))))

(defn make-src-pkg
  [&keys {:url url :hash hash :fname fname}]
  (default fname (last (string/split "/" url))) # XXX rfind would be nice in stdlib.
  (pkg
    :out-hash
      hash
    :builder
      (fn []
        (fetch url (string (dyn :pkg-out) "/" fname)))
    ))

(defn make-core-pkg
  [&keys {:src src}]
  (pkg
    :builder
    (fn []
      (os/setenv "PATH" (string (bootstrap :path) "/bin"))
      # XXX we shouldn't need to do this at build time.
      (def src-archive (->> (src :path)
                            (os/dir)
                            (filter |(not (string/has-prefix? "." $)))
                            (first)))
      (unpack (string (src :path) "/"  src-archive) :strip 1)
      (os/setenv "CC" "x86_64-linux-musl-cc")
      (os/setenv "LDFLAGS" "-O2 -static")
      (sh/$ ["sh" "./configure" "--prefix" (dyn :pkg-out)])
      (sh/$ ["make"])
      (sh/$ ["make" "install"]))))

(defmacro defsrc
  [name &keys {:url url :hash hash}]
  (def src-pkg (gensym))
 ~(def ,name (,make-src-pkg :url ,url :hash ,hash)))

(defmacro defpkg
  [name &keys {:src-url src-url :src-hash src-hash}]
  (def src-pkg (gensym))
 ~(def [,name ,(symbol name '-src)]
    (do
      (def ,src-pkg (,make-src-pkg :url ,src-url :hash ,src-hash))
      [(,make-core-pkg :src ,src-pkg) ,src-pkg])))

(defpkg coreutils
  :src-url
    "https://ftp.gnu.org/gnu/coreutils/coreutils-8.31.tar.xz"
  :src-hash
    "sha256:b812a9a95a7de00367309940f39cf822c5b5e749b18e78fa045694872828a146")

(defpkg awk
  :src-url
    "https://ftp.gnu.org/gnu/gawk/gawk-5.0.1.tar.xz"
  :src-hash
    "sha256:614c7af2bc8bf801bc0e7db1f15866b0b445bb10e38b920d234d7e858d0f220b")

(defpkg diffutils
  :src-url
    "https://ftp.gnu.org/gnu/diffutils/diffutils-3.7.tar.xz"
  :src-hash
    "sha256:8ff1882ea86b38be2f28dc335152bb5678af4f3187ae4cc436ea88a5b2807fb3")

(defpkg findutils
  :src-url
    "https://ftp.gnu.org/pub/gnu/findutils/findutils-4.6.0.tar.gz"
  :src-hash
    "sha256:82c42eac63c20ab10c3dd4b6040fc562c9070460214b0151b114780a96c75398")

(defpkg make
  :src-url
    "https://ftp.gnu.org/gnu/make/make-4.2.tar.gz"
  :src-hash
    "sha256:929b96ab4083fb3efee19ad2e9e6faaa53828a28e8f2282306228c527b6bbd7a")

(defpkg patch
  :src-url
    "https://ftp.gnu.org/gnu/patch/patch-2.7.tar.gz"
  :src-hash
    "sha256:f88b9f95bd536910329bf8b9dce3f066ec4ca9fe61217e1caf882c4673cc8d8e")

(defpkg pkgconf
  :src-url
    "https://distfiles.dereferenced.org/pkgconf/pkgconf-1.6.3.tar.xz"
  :src-hash
    "sha256:ae9fd87179b6e1adbd90cf4f484eb62922e7798f460260da51bbd7e0a4735cb5")

(defpkg sed
  :src-url
    "https://ftp.gnu.org/gnu/sed/sed-4.7.tar.xz"
  :src-hash
    "sha256:04a30573b1375d4b80412fd686abf46e78d92eb29667589e0f6e72091fc08ea2")

(defpkg grep
  :src-url
    "https://ftp.gnu.org/gnu/grep/grep-3.3.tar.xz"
  :src-hash
    "sha256:bc8e712d9a11f110c675c2f3959cd3781808ee10b13c13c9f10bebaa3e9de389")

(defpkg which
  :src-url
    "https://ftp.gnu.org/gnu/which/which-2.21.tar.gz"
  :src-hash
    "sha256:81707303a5b68562ef242036d6e697f3a5539679cc6cda1191ac1c3014d09ec4")

(defpkg tar
  :src-url
    "https://ftp.gnu.org/gnu/tar/tar-1.32.tar.gz"
  :src-hash
    "sha256:ff3e8ef8b959813f3c3c10b993c2b8f4c18974ed85b2e418dc67c386f91e0be0")

(defpkg gzip
  :src-url
    "https://ftp.gnu.org/gnu/gzip/gzip-1.10.tar.gz"
  :src-hash
    "sha256:088d9a30007446dd85f7efe27403d82177b384713448fb575aa47cb70ff3ba6a")

(defpkg lzip
  :src-url
    "http://download.savannah.gnu.org/releases/lzip/lzip-1.21.tar.gz"
  :src-hash
    "sha256:0d2d0f197a444d6d3a9edac84e2c4536e29d44111233c0c268185c2aee42971b")

(defpkg xz
  :src-url
    "https://ftp.gnu.org/gnu/which/which-2.21.tar.gz"
  :src-hash
    "sha256:81707303a5b68562ef242036d6e697f3a5539679cc6cda1191ac1c3014d09ec4")

(defn make-combined-env
  [&keys {:name name
          :bin-pkgs bin-pkgs }]
  (default bin-pkgs [])
  (pkg
    :name name
    :builder
    (fn []
      (os/mkdir (string (dyn :pkg-out) "/bin"))
      (each pkg bin-pkgs
        (def pkg-bin-dir (string (pkg :path) "/bin"))
        (each bin (os/dir pkg-bin-dir)
          (def from
            (string (sh/$$_ ["readlink" "-f" (string pkg-bin-dir "/" bin)])))
          (def to (string (dyn :pkg-out) "/bin/" bin))
          (unless (os/stat to)
            (os/link from to true)))))))

(def core-env
  (make-combined-env
    :name
      "core-env"
    :bin-pkgs
      [
        coreutils
        awk
        diffutils
        findutils
        make
        patch
        sed
        grep
        which
        tar
        gzip
        lzip
        xz
      ]))

(defsrc gcc-src
  :url "https://ftp.gnu.org/gnu/gcc/gcc-8.3.0/gcc-8.3.0.tar.xz"
  :hash "sha256:809be66cb398562d2f71c4d770cbf8df0b32d715f80113d630e8bd108fb62c9e")

(defsrc musl-cross-make-src
  :url "https://github.com/richfelker/musl-cross-make/archive/v0.9.8.tar.gz"
  :hash "sha256:84e9d1a141eee17b96e916a213eec7e5efede2933af35cb54b33aaf0f27d40d9")

(defsrc linux-hdrs-src
  :url "https://mirrors.edge.kernel.org/pub/linux/kernel/v4.x/linux-4.4.10.tar.xz"
  :hash "sha256:73e62a8ac190a8d76a6a48b19ca12179df927813a767bbc3a313bb544884abf1")

(defsrc binutils-src
  :url "https://ftp.gnu.org/gnu/binutils/binutils-2.32.tar.xz"
  :hash "sha256:a54bde22c5c478ac97a5ade4fd16f5c7fd25e9e96192b9f01e249294541f7fd2")

(defsrc gmp-src
  :url "https://gmplib.org/download/gmp/gmp-6.1.2.tar.xz"
  :hash "sha256:8bf2479e015f0a353b9a90ffd323ace20083919957ac0e154adc49f9d37b70e9")

(defsrc mpc-src
  :url "https://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz"
  :hash "sha256:8dcdaea72d8e107c75dda72c215664f07e1da6c648da2f0c9dc41903c9a745a5")

(defsrc mpfr-src
  :url "https://www.mpfr.org/mpfr-current/mpfr-4.0.2.tar.xz"
  :hash "sha256:26017838b1944df12aba805873901cc3f82cab43485d90282379520e8a58be86")

(defsrc musl-src
  :url "https://www.musl-libc.org/releases/musl-1.1.23.tar.gz"
  :hash "sha256:8afed31eeaefed62881267f97c7d021037e0e9aa79ff4c2bb9d0c8fc260f6209")
