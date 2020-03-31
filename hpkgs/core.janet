
(def bootstrap
  (pkg
    :content
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
    :content
      {fname {:content hash}}
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
      (os/symlink (string (bootstrap :path) "/bin/dash") "/bin/sh")
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
    "sha256:ad70e0cc3116b424931c392912b3ebdb8053b21f3fd968c782f0b19fd8ae31ab")

(defcore coreutils
  :src-url
    "https://ftp.gnu.org/gnu/coreutils/coreutils-8.31.tar.xz"
  :src-hash
    "sha256:ff7a9c918edce6b4f4b2725e3f9b37b0c4d193531cac49a48b56c4d0d3a9e9fd")

(defcore awk
  :src-url
    "https://ftp.gnu.org/gnu/gawk/gawk-5.0.1.tar.xz"
  :src-hash
    "sha256:8e4e86f04ed789648b66f757329743a0d6dfb5294c3b91b756a474f1ce05a794")

(defcore diffutils
  :src-url
    "https://ftp.gnu.org/gnu/diffutils/diffutils-3.7.tar.xz"
  :src-hash
    "sha256:b3a7a6221c3dc916085f0d205abf6b8e1ba443d4dd965118da364a1dc1cb3a26")

(defcore findutils
  :src-url
    "https://ftp.gnu.org/pub/gnu/findutils/findutils-4.7.0.tar.xz"
  :src-hash
    "sha256:c5fefbdf9858f7e4feb86f036e1247a54c79fc2d8e4b7064d5aaa1f47dfa789a")

(defcore make
  :src-url
    "https://ftp.gnu.org/gnu/make/make-4.2.tar.gz"
  :src-hash
    "sha256:e968ce3c57ad39a593a92339e23eb148af6296b9f40aa453a9a9202c99d34436")

(defcore patch
  :src-url
    "https://ftp.gnu.org/gnu/patch/patch-2.7.tar.gz"
  :src-hash
    "sha256:59c29f56faa0a924827e6a60c6accd6e2900eae5c6aaa922268c717f06a62048")

(defcore pkgconf
  :src-url
    "https://distfiles.dereferenced.org/pkgconf/pkgconf-1.6.3.tar.xz"
  :src-hash
    "sha256:61f0b31b0d5ea0e862b454a80c170f57bad47879c0c42bd8de89200ff62ea210")

(defcore sed
  :src-url
    "https://ftp.gnu.org/gnu/sed/sed-4.7.tar.xz"
  :src-hash
    "sha256:2885768cd0a29ff8d58a6280a270ff161f6a3deb5690b2be6c49f46d4c67bd6a")

(defcore grep
  :src-url
    "https://ftp.gnu.org/gnu/grep/grep-3.3.tar.xz"
  :src-hash
    "sha256:b960541c499619efd6afe1fa795402e4733c8e11ebf9fafccc0bb4bccdc5b514")

(defcore which
  :src-url
    "https://ftp.gnu.org/gnu/which/which-2.21.tar.gz"
  :src-hash
    "sha256:f4a245b94124b377d8b49646bf421f9155d36aa7614b6ebf83705d3ffc76eaad")

(defcore tar
  :src-url
    "https://ftp.gnu.org/gnu/tar/tar-1.32.tar.gz"
  :src-hash
    "sha256:b59549594d91d84ee00c99cf2541a3330fed3a42c440503326dab767f2fbb96c")

(defcore gzip
  :src-url
    "https://ftp.gnu.org/gnu/gzip/gzip-1.10.tar.gz"
  :src-hash
    "sha256:c91f74430bf7bc20402e1f657d0b252cb80aa66ba333a25704512af346633c68")

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
    "sha256:e48b5039d3164d670791f9c5dbaa832bf2df080cb1fbb4f33aa7b3300b670d8b")

(defcore xz
  :src-url
    "https://tukaani.org/xz/xz-5.2.4.tar.gz"
  :src-hash
    "sha256:b512f3b726d3b37b6dc4c8570e137b9311e7552e8ccbab4d39d47ce5f4177145")

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
      (def activate-script (string (dyn :pkg-out) "/activate"))
      (spit activate-script 
        (string
          "export PATH=" (string (dyn :pkg-out) "/bin") "\n"))
      (os/chmod activate-script 8r555)
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
  :hash "sha256:ff3e2188626e4e55eddcefef4ee0aa5a8ffb490e3124850589bcaf4dd60f5f04")

(defsrc gcc-src
  :url "https://ftp.gnu.org/pub/gnu/gcc/gcc-9.2.0/gcc-9.2.0.tar.xz"
  :hash "sha256:ea6ef08f121239da5695f76c9b33637a118dcf63e24164422231917fa61fb206")

(defsrc binutils-src
  :url "https://ftp.gnu.org/pub/gnu/binutils/binutils-2.33.1.tar.xz"
  :hash "sha256:ab66fc2d1c3ec0359b8e08843c9f33b63e8707efdff5e4cc5c200eae24722cbf")

(defsrc gmp-src
  :url "https://ftp.gnu.org/pub/gnu/gmp/gmp-6.1.2.tar.bz2"
  :hash "sha256:5275bb04f4863a13516b2f39392ac5e272f5e1bb8057b18aec1c9b79d73d8fb2")

(defsrc mpc-src
  :url "https://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz"
  :hash "sha256:6985c538143c1208dcb1ac42cedad6ff52e267b47e5f970183a3e75125b43c2e")

(defsrc mpfr-src
  :url "https://ftp.gnu.org/pub/gnu/mpfr/mpfr-4.0.2.tar.bz2"
  :hash "sha256:c05e3f02d09e0e9019384cdd58e0f19c64e6db1fd6f5ecf77b4b1c61ca253acc")

(defsrc musl-src
  :url "https://www.musl-libc.org/releases/musl-1.2.0.tar.gz"
  :hash "sha256:c6de7b191139142d3f9a7b5b702c9cae1b5ee6e7f57e582da9328629408fd4e8")

(defsrc linux-hdrs-src
  :url "http://ftp.barfooze.de/pub/sabotage/tarballs//linux-headers-4.19.88.tar.xz"
  :hash "sha256:d3f3acf6d16bdb005d3f2589ade1df8eff2e1c537f92e6cd9222218ead882feb")

# XXX Why does musl cross make download this?
(def- config.sub
  (pkg
    :content
      {"config.sub" {:content "sha256:75d5d255a2a273b6e651f82eecfabf6cbcd8eaeae70e86b417384c8f4a58d8d3"}}
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
      (os/symlink (string (dash :path) "/bin/dash") "/bin/sh")
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

