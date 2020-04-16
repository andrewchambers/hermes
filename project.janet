(post-deps
  (import sh)
  (import path))

(declare-project
  :name "hermes"
  :author "Andrew Chambers"
  :license "MIT"
  :url "https://github.com/andrewchambers/hermes"
  :repo "git+https://github.com/andrewchambers/hermes.git"
  :dependencies [
    "https://github.com/janet-lang/sqlite3.git"
    "https://github.com/janet-lang/argparse.git"
    "https://github.com/janet-lang/path.git"
    "https://github.com/andrewchambers/janet-jdn.git"
    "https://github.com/andrewchambers/janet-flock.git"
    "https://github.com/andrewchambers/janet-process.git"
    "https://github.com/andrewchambers/janet-sh.git"
    "https://github.com/andrewchambers/janet-base16.git"
  ])

(post-deps

(defn src-file?
  [path]
  (def ext (path/ext path))
  (case ext
    ".janet" true
    ".c" true
    ".h" true
    false))

(def all-src
  (->>  (os/dir "./src")
        (map |(string "src/" $))
        (filter src-file?)))

(defn declare-third-party
  [&keys {:name name
          :src-url src-url
          :src-sha256sum src-sha256sum
          :extract-nstrip extract-nstrip
          :extra-configure extra-configure
          :extra-make extra-make
          :do-patch do-patch}]
  
  (default extract-nstrip 1)
  (default extra-configure [])
  (default extra-make [])
  (def dir (string "third-party/"  name))
  (def install-root (path/abspath "third-party/install-root"))
  (def src (string dir "/src"))
  (def archive (string dir "/" (last (string/split "/" src-url))))
  (def stamp-downloaded (string dir "/stamp_downloaded"))
  (def stamp-extracted (string dir "/stamp_extracted"))
  (def stamp-patched (string dir "/stamp_patched"))
  (def stamp-built (string dir "/stamp_built"))
  (def stamp-installed (string dir "/stamp_installed"))
  
  (rule stamp-downloaded []
    (eprint "downloading " src-url " to " archive)
    (sh/$ ~[mkdir -p ,dir])
    (sh/$ ~[curl -f -L -o ,archive ,src-url])
    (def hash (first (string/split " " (sh/$$_ ~[sha256sum ,archive]))))
    (unless (= hash src-sha256sum)
      (error (string "checksum of " archive " failed, expected " src-sha256sum " got " hash)))
    (sh/$ ~[touch ,stamp-downloaded]))

  (rule stamp-extracted [stamp-downloaded]
    (eprint "extracting " archive " to " src)
    (sh/$ ~[rm -rf ,src])
    (sh/$ ~[mkdir ,src])
    (sh/$ ~[tar -C ,src -vxaf ,(path/abspath archive) ,(string "--strip-components=" extract-nstrip)])
    (sh/$ ~[touch ,stamp-extracted]))

  (rule stamp-patched [stamp-extracted]
    (when do-patch
      (eprint "patching " name)
      (def wd (os/cwd))
      (defer (os/cd wd)
        (os/cd src)
        (do-patch)))
    (sh/$ ~[touch ,stamp-patched]))
  
  (rule stamp-built [stamp-patched]
    (eprint "building " name)
    (def wd (os/cwd))
    (defer (os/cd wd)
      (os/cd src)
      (when (os/stat "./configure")
        (sh/$ ~[./configure ,(string "--prefix=" install-root) ,;extra-configure]))
      (sh/$ ~[make ,(string "PREFIX=" install-root) ;extra-make]))
    (sh/$ ~[touch ,stamp-built]))

  (rule stamp-installed [stamp-built]
    (sh/$ ~[mkdir -p ,install-root])
    (def wd (os/cwd))
    (defer (os/cd wd)
      (os/cd src)
      (sh/$ ~[make ,(string "PREFIX=" install-root) ,;extra-make install]))
    (sh/$ ~[touch ,stamp-installed]))

  (add-dep "build" stamp-installed))

(declare-third-party
  :name "signify"
  :src-url "https://github.com/aperezdc/signify/releases/download/v29/signify-29.tar.xz"
  :src-sha256sum "a9c1c3c2647359a550a4a6d0fb7b13cbe00870c1b7e57a6b069992354b57ecaf")

(declare-third-party
  :name "util-linux"
  :src-url "https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.35/util-linux-2.35.tar.xz"
  :src-sha256sum "b3081b560268c1ec3367e035234e91616fa7923a0afc2b1c80a2a6d8b9dfe2c9"
  :extra-configure ~[
    --disable-all-programs
    --enable-unshare
    --disable-libblkid
    --disable-libmount
    --disable-libuuid
    --disable-libsmartcols
    --disable-libfdisk
    --disable-makeinstall-chown
    --disable-makeinstall-setuid
  ])

(declare-third-party
  :name "dumb-init"
  :src-url "https://github.com/Yelp/dumb-init/archive/v1.2.2.tar.gz"
  :src-sha256sum "d4e2e10e39ad49c225e1579a4d770b83637399a0be48e29986f720fae44dafdf"
  :do-patch
  (fn []
    (as-> (slurp "Makefile") _
          (string/replace " -static " " " _)
          (string _ ".PHONY: install\ninstall: \n\tcp dumb-init $(PREFIX)/bin/dumb-init")
          (spit "Makefile" _))))

(rule "build/hermes-tempdir" ["src/hermes-tempdir-main.c"]
  (sh/$ ~[,(os/getenv "CC" "gcc") src/hermes-tempdir-main.c -o build/hermes-tempdir]))

(rule "build/hermes-minitar" ["src/hermes-minitar-main.c"]
  (sh/$ ~[,(os/getenv "CC" "gcc") src/hermes-minitar-main.c -larchive -o build/hermes-minitar]))

(rule "build/hermes-signify" ["third-party/signify/stamp_installed"]
  (sh/$ ~[cp "third-party/install-root/bin/signify" "build/hermes-signify"]))

(rule "build/hermes-unshare" ["third-party/util-linux/stamp_installed"]
  (sh/$ ~[cp "third-party/install-root/bin/unshare" "build/hermes-unshare"]))

(rule "build/hermes-dumb-init" ["third-party/dumb-init/stamp_installed"]
  (sh/$ ~[cp "third-party/install-root/bin/dumb-init" "build/hermes-dumb-init"]))


(declare-native
  :name "_hermes"
  :headers ["src/hermes.h"
            "src/sha1.h"
            "src/sha256.h"]
  :source ["src/hermes.c"
           "src/scratchvec.c"
           "src/sha1.c"
           "src/sha256.c"
           "src/hash.c"
           "src/pkgfreeze.c"
           "src/deps.c"
           "src/hashscan.c"
           "src/base16.c"
           "src/storify.c"
           "src/os.c"
           "src/unpack.c"]
  :lflags ["-larchive"])

(declare-executable
  :name "hermes"
  :entry "src/hermes-main.janet"
  :deps all-src)

(declare-executable
  :name "hermes-pkgstore"
  :entry "src/hermes-pkgstore-main.janet"
  :deps all-src)

(declare-executable
  :name "hermes-builder"
  :entry "src/hermes-builder-main.janet"
  :deps all-src)

(def output-bins
  ["hermes"
   "hermes-pkgstore"
   "hermes-builder"
   "hermes-tempdir"
   "hermes-signify"
   "hermes-unshare"
   "hermes-dumb-init"])

(rule "build/hermes.tar.gz" (map |(string "build/" $) output-bins)
  (sh/$
   ~[tar -C ./build -czf build/hermes.tar.gz --files-from=-]
    :redirects [[stdin (string/join output-bins "\n")]]))

(add-dep "build" "build/hermes.tar.gz")


)
