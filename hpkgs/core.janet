
(def bootstrap
  (pkg
    :out-hash
      "sha256:f6c56e84b78b7d1d57aa9c127b23b9fd5c729410b4ecad9012b0de5ab55649bd"
    :builder
      (fn []
        (unpack
          (fetch
            # TODO FIXME make this a tag.
            "https://github.com/andrewchambers/hermes-seeds/raw/master/bootstrap.tar.gz")
            :dest (dyn :pkg-out)))))

(defn- make-src-pkg
  [&keys {:name name :url url :hash hash :fname fname}]
  (default fname (last (string/split "/" url))) # XXX rfind would be nice in stdlib.
  (pkg
    :name
      name
    :out-hash
      hash
    :builder
      (fn []
        (fetch url (string (dyn :pkg-out) "/" fname)))
    ))

(defn- core-pkg
  [&keys {:name name :src src}]
  (pkg
    :name name
    :builder
    (fn []
      (os/setenv "PATH" (string (bootstrap :path) "/bin"))
      # XXX we shouldn't need to do this at build time.
      (def src-archive (->> (src :path)
                            (os/dir)
                            (filter |(not (string/has-prefix? "." $)))
                            (first)))
      (unpack (string (src :path) "/"  src-archive) :strip 1)
      (os/setenv "CC" "x86_64-linux-musl-cc --static")
      (os/setenv "CFLAGS" "-O2")
      (os/setenv "LDFLAGS" "--static")
      (sh/$ ["sh" "./configure" "--enable-shared=no" "--prefix" (dyn :pkg-out)])
      (sh/$ ["make"])
      (sh/$ ["make" "install"]))))

(defmacro defsrc
  [name &keys {:url url :hash hash}]
  (def src-pkg (gensym))
 ~(def ,name (,make-src-pkg :name ,(string name) :url ,url :hash ,hash)))

(defmacro defcore
  [name &keys {:src-url src-url :src-hash src-hash}]
  (def src-pkg (gensym))
  (def src-name (symbol name '-src))
 ~(def [,name ,src-name]
    (do
      (def ,src-pkg (,make-src-pkg :name ,(string src-name) :url ,src-url :hash ,src-hash))
      [(,core-pkg :name ,(string name) :src ,src-pkg) ,src-pkg])))

(defcore dash
  :src-url
    "http://gondor.apana.org.au/~herbert/dash/files/dash-0.5.10.tar.gz"
  :src-hash
    "sha256:4273c06551b2c1f281c9ca92e69e8bb01783fdbf8eef85a630640c63043732bf")

(defcore coreutils
  :src-url
    "https://ftp.gnu.org/gnu/coreutils/coreutils-8.31.tar.xz"
  :src-hash
    "sha256:b812a9a95a7de00367309940f39cf822c5b5e749b18e78fa045694872828a146")

(defcore awk
  :src-url
    "https://ftp.gnu.org/gnu/gawk/gawk-5.0.1.tar.xz"
  :src-hash
    "sha256:614c7af2bc8bf801bc0e7db1f15866b0b445bb10e38b920d234d7e858d0f220b")

(defcore diffutils
  :src-url
    "https://ftp.gnu.org/gnu/diffutils/diffutils-3.7.tar.xz"
  :src-hash
    "sha256:8ff1882ea86b38be2f28dc335152bb5678af4f3187ae4cc436ea88a5b2807fb3")

(defcore findutils
  :src-url
    "https://ftp.gnu.org/pub/gnu/findutils/findutils-4.7.0.tar.xz"
  :src-hash
    "sha256:5e22d995f9f378bad17538fccde3cc67df618aac937f3ef1b51fb2ff37137e60")

(defcore make
  :src-url
    "https://ftp.gnu.org/gnu/make/make-4.2.tar.gz"
  :src-hash
    "sha256:929b96ab4083fb3efee19ad2e9e6faaa53828a28e8f2282306228c527b6bbd7a")

(defcore patch
  :src-url
    "https://ftp.gnu.org/gnu/patch/patch-2.7.tar.gz"
  :src-hash
    "sha256:f88b9f95bd536910329bf8b9dce3f066ec4ca9fe61217e1caf882c4673cc8d8e")

(defcore pkgconf
  :src-url
    "https://distfiles.dereferenced.org/pkgconf/pkgconf-1.6.3.tar.xz"
  :src-hash
    "sha256:ae9fd87179b6e1adbd90cf4f484eb62922e7798f460260da51bbd7e0a4735cb5")

(defcore sed
  :src-url
    "https://ftp.gnu.org/gnu/sed/sed-4.7.tar.xz"
  :src-hash
    "sha256:04a30573b1375d4b80412fd686abf46e78d92eb29667589e0f6e72091fc08ea2")

(defcore grep
  :src-url
    "https://ftp.gnu.org/gnu/grep/grep-3.3.tar.xz"
  :src-hash
    "sha256:bc8e712d9a11f110c675c2f3959cd3781808ee10b13c13c9f10bebaa3e9de389")

(defcore which
  :src-url
    "https://ftp.gnu.org/gnu/which/which-2.21.tar.gz"
  :src-hash
    "sha256:81707303a5b68562ef242036d6e697f3a5539679cc6cda1191ac1c3014d09ec4")

(defcore tar
  :src-url
    "https://ftp.gnu.org/gnu/tar/tar-1.32.tar.gz"
  :src-hash
    "sha256:ff3e8ef8b959813f3c3c10b993c2b8f4c18974ed85b2e418dc67c386f91e0be0")

(defcore gzip
  :src-url
    "https://ftp.gnu.org/gnu/gzip/gzip-1.10.tar.gz"
  :src-hash
    "sha256:088d9a30007446dd85f7efe27403d82177b384713448fb575aa47cb70ff3ba6a")

(defsrc bzip2-src
  :url
    "https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz"
  :hash
    "sha256:e1b3c10021d1e662e1125ead2fdb29fd21d5c7da9579b9d59a254bafd3281a44")

(def bzip2
  (pkg
    :name "bzip2"
    :builder
    (fn []
      (os/setenv "PATH" (string (bootstrap :path) "/bin"))
      # XXX we shouldn't need to do this at build time.
      (def src-archive (->> (bzip2-src :path)
                            (os/dir)
                            (filter |(not (string/has-prefix? "." $)))
                            (first)))
      (unpack (string (bzip2-src :path) "/"  src-archive) :strip 1)
      (sh/$ ["make" "install"
               "CC=x86_64-linux-musl-cc --static"
               "CFLAGS=-O2"
               "LDFLAGS=--static"
               (string "PREFIX=" (dyn :pkg-out))]))))

(defcore lzip
  :src-url
    "http://download.savannah.gnu.org/releases/lzip/lzip-1.21.tar.gz"
  :src-hash
    "sha256:0d2d0f197a444d6d3a9edac84e2c4536e29d44111233c0c268185c2aee42971b")

(defcore xz
  :src-url
    "https://tukaani.org/xz/xz-5.2.4.tar.gz"
  :src-hash
    "sha256:e0639989aa21a9487908d106a44065372a8e371e35d1d5fb51b1ec9d5008438b")

(defn make-combined-env
  [&keys {:name name
          :bin-pkgs bin-pkgs
          :post-build post-build}]
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
            (os/symlink from to))))
      (when post-build
        (post-build)))))

(def core-env
  (make-combined-env
    :name
      "core-env"
    :bin-pkgs
      [
        dash
        coreutils
        awk
        diffutils
        findutils
        patch
        sed
        grep
        which
        tar
        gzip
        lzip
        xz
      ]
    :post-build
    (fn []
      (os/cd (string (dyn :pkg-out) "/bin"))
      (os/symlink "./dash" "sh"))))

(defsrc musl-cross-make-src
  :url "https://github.com/richfelker/musl-cross-make/archive/v0.9.9.tar.gz"
  :hash "sha256:0e2dc83f870cd48f545470bdf5acddabf296aca155705312f292fc2b22e41b88")

(defsrc gcc-src
  :url "https://ftp.gnu.org/pub/gnu/gcc/gcc-9.2.0/gcc-9.2.0.tar.xz"
  :hash "sha256:e25f41bb630915c9a2de18e959c7f920cda202022e7c815090c519f3ce36db81")

(defsrc binutils-src
  :url "https://ftp.gnu.org/pub/gnu/binutils/binutils-2.33.1.tar.xz"
  :hash "sha256:f6245cf858b2a50a515e5d13d1be3e2acbf7cb5f4873baa6319d83ff3d700a7e")

(defsrc gmp-src
  :url "https://ftp.gnu.org/pub/gnu/gmp/gmp-6.1.2.tar.bz2"
  :hash "sha256:1dc7d51347da25aa183cdae34c064938c1540b4328a352c6ddef59d917499e16")

(defsrc mpc-src
  :url "https://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz"
  :hash "sha256:8dcdaea72d8e107c75dda72c215664f07e1da6c648da2f0c9dc41903c9a745a5")

(defsrc mpfr-src
  :url "https://ftp.gnu.org/pub/gnu/mpfr/mpfr-4.0.2.tar.bz2"
  :hash "sha256:1a962881aeac34c637ae68946b8795b81f059e80e986c9955db8bc33f6d9b901")

(defsrc musl-src
  :url "https://www.musl-libc.org/releases/musl-1.2.0.tar.gz"
  :hash "sha256:13c4b5a3b00f7e097ab4c8f06772785f5408b7f65fcb76cf1e12aa79fd84f33b")

(defsrc linux-hdrs-src
  :url "http://ftp.barfooze.de/pub/sabotage/tarballs//linux-headers-4.19.88.tar.xz"
  :hash "sha256:741546ea9581dce73534d3ca8445e5243aa21b7b01d22d82019b459a34fbc160")

# XXX Why does musl cross make download this?
(def- config.sub
  (pkg
    :out-hash "sha256:df2fda02b714aa5815f2107a9b6d0af508aa51df59e84bab29fcdd672bf9ede9"
    :builder
    (fn []
      (fetch
        "http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=3d5db9ebe860"
        (string (dyn :pkg-out) "/" "config.sub")))))


(defn- install-musl-cross-make-gcc
  [post-extract post-install]
  (defn archive-path
        [src-pkg]
        (->> (src-pkg :path)
          (os/dir)
          (filter |(not (string/has-prefix? "." $)))
          (first)
          (string (src-pkg :path) "/")))

  (os/setenv "PATH"
    (string
      (patch :path) "/bin:" # XXX busybox patch cannot apply these patches.
      (bootstrap :path) "/bin"))
  
  (unpack (archive-path musl-cross-make-src) :strip 1)

  (os/mkdir "sources")
  (each src [gcc-src binutils-src musl-src gmp-src mpc-src mpfr-src linux-hdrs-src]
    (sh/$ ["cp" (archive-path src) "./sources"]))
  (sh/$ ["cp" (string (config.sub :path) "/config.sub") "./sources"])
  
  (spit "config.mak"
    (string
      "TARGET=x86_64-linux-musl\n"
      "OUTPUT=" (dyn :pkg-out) "\n"
      "COMMON_CONFIG += CC=\"cc -static --static\" CXX=\"c++ -static --static\"\n"
      "COMMON_CONFIG += CFLAGS=\"-g0 -Os\" CXXFLAGS=\"-g0 -Os\" LDFLAGS=\"-s\"\n"
      "DL_CMD=false\n"
      "COWPATCH=" (os/cwd) "/cowpatch.sh\n"))

  (sh/$ ["make" "extract_all"])
  (when post-extract
    (post-extract))
  (sh/$ ["make" "install" "-j8"])
  (when post-install
    (post-install)))

# The runtime package is a gcc installation with only 
(def gcc-runtime
  (pkg
    :name "rt"
    :builder
    (fn []
      (defn do-fixups
        []
        # Remove things that aren't dynamic libs.
        (sh/$ ["find" (dyn :pkg-out) "-type" "f" "-not" "-name" "*.so*" "-delete"])
        
        # XXX Fix broken link, why is this broken?
        (def ld.so (string (dyn :pkg-out) "/x86_64-linux-musl/lib/ld-musl-x86_64.so.1"))
        (os/rm ld.so)
        (os/symlink "libc.so" ld.so)
        
        # Manually configure path with musl config.
        (os/mkdir (string (dyn :pkg-out) "/x86_64-linux-musl/etc"))
        (spit 
          (string (dyn :pkg-out) "/x86_64-linux-musl/etc/ld-musl-x86_64.path")
          (string (dyn :pkg-out) "/x86_64-linux-musl/lib\n"))
        #XXX TODO DELETE empty dirs
        )
      (install-musl-cross-make-gcc
        nil
        do-fixups))))

(def gcc
  (pkg
    :name "gcc"
    :builder
    (fn []
      (defn do-patch
        []
        (def cfg "gcc-9.2.0/gcc/config/i386/linux64.h")
        (spit cfg 
          (string/replace-all
            "/lib/ld-musl-x86_64.so.1"
            (string (gcc-runtime :path) "/x86_64-linux-musl/lib/ld-musl-x86_64.so.1")
            (slurp cfg))))
      (install-musl-cross-make-gcc
        do-patch
        nil))))


(def core-build-env
  (make-combined-env
    :name
      "core-build-env"
    :bin-pkgs
      [
        core-env
        gcc
        pkgconf
        make
      ]
    :post-build
      (fn []
        (os/cd (string (dyn :pkg-out) "/bin"))
        # This could probably be a loop.
        (os/symlink "./x86_64-linux-musl-ar" "ar")
        (os/symlink "./x86_64-linux-musl-ar" "ranlib")
        (os/symlink "./x86_64-linux-musl-cc" "cc")
        (os/symlink "./x86_64-linux-musl-cc" "gcc")
        (os/symlink "./x86_64-linux-musl-c++" "c++")
        (os/symlink "./x86_64-linux-musl-c++" "g++")
        (os/symlink "./x86_64-linux-musl-ld" "ld"))))

(def bootstrap-out
  (pkg
    :name "bootstrap-out"
    :builder
    (fn []
      
      (os/setenv "PATH" (string (bootstrap :path) "/bin"))

      (defn copy-bin
        [pkg]
        (def out-bin-dir (string (dyn :pkg-out) "/bin"))
        (os/mkdir out-bin-dir)
        (sh/$ ["cp" "-rT" (string (pkg :path) "/bin") out-bin-dir]))

      (copy-bin dash)
      (copy-bin awk)
      (copy-bin coreutils)
      (copy-bin diffutils)
      (copy-bin findutils)
      (copy-bin patch)
      (copy-bin make)
      (copy-bin tar)
      (copy-bin gzip)
      (copy-bin bzip2)
      (copy-bin xz)
      (copy-bin grep)
      (copy-bin sed)

      (install-musl-cross-make-gcc
        nil
        nil)

      (def start-dir (os/cwd))
      (os/cd (string (dyn :pkg-out) "/bin"))
      (os/symlink "./dash" "sh")
      (os/symlink "./x86_64-linux-musl-ar" "ar")
      (os/symlink "./x86_64-linux-musl-cc" "cc")
      (os/symlink "./x86_64-linux-musl-c++" "c++")
      (os/cd start-dir)

      (sh/$ ["tar" "-C" (dyn :pkg-out) "-cz" "-f" "./bootstrap.tar.gz" "."])
      (sh/$ ["mv" "./bootstrap.tar.gz" (dyn :pkg-out)]))))

(defn std-pkg
  [&keys {
    :name name
    :src src
    :bin-inputs bin-inputs
    :unpack-phase unpack-phase    
    :configure-phase configure-phase
    :install-phase install-phase
  }]

  (default bin-inputs [])
  
  (default unpack-phase
    (fn std-unpack-phase []
      (def src (dyn :pkg-src))
      (def src-archive (->> (src :path)
                            (os/dir)
                            (filter |(not (string/has-prefix? "." $)))
                            (first)))
      (unpack (string (src :path) "/"  src-archive) :strip 1)))

  (default configure-phase
    (fn std-configure-phase []
      (when (os/stat "./configure")
        (sh/$ ["./configure" "--prefix" (dyn :pkg-out)]))))

  (default install-phase
    (fn std-install-phase []
      (sh/$ ["make"])
      (sh/$ ["make" "install" (string "PREFIX=" (dyn :pkg-out))])))

  (pkg
    :name name
    :builder
    (fn std-builder []
      (def all-bin-inputs (array/concat @[] bin-inputs [core-build-env]))
      (os/setenv "PATH"
        (string/join (map |(string ($ :path) "/bin") all-bin-inputs) ":"))
      (with-dyns [:pkg-src src]
        (unpack-phase))
      (configure-phase)
      (install-phase))))

(defmacro defpkg
  [name &keys {
    :src-url src-url
    :src-hash src-hash
    :bin-inputs bin-inputs
    :unpack-phase unpack-phase    
    :configure-phase configure-phase
    :install-phase install-phase
  }]
  (def src-pkg (gensym))
  (def src-name (symbol name '-src))
 ~(def [,name ,src-name]
    (do
      (def ,src-pkg (,make-src-pkg :name ,(string src-name) :url ,src-url :hash ,src-hash))
      [
        (,std-pkg
          :name ,(string name)
          :src ,src-pkg
          :bin-inputs ,bin-inputs
          :unpack-phase ,unpack-phase    
          :configure-phase ,configure-phase
          :install-phase ,install-phase)
      ,src-pkg])))



(defpkg janet
  :src-url "https://github.com/janet-lang/janet/archive/v1.7.0.tar.gz"
  :src-hash "sha256:f48f2b1fd90fe347e356bf50339d6917cc12c61eb8dfe76d41a1b58b4e992c1f")

