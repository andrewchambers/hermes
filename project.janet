(post-deps
  (import shlex)
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
    "https://github.com/andrewchambers/janet-uri.git"
    "https://github.com/andrewchambers/janet-jdn.git"
    "https://github.com/andrewchambers/janet-flock.git"
    "https://github.com/andrewchambers/janet-process.git"
    "https://github.com/andrewchambers/janet-sh.git"
    "https://github.com/andrewchambers/janet-base16.git"
    "https://github.com/andrewchambers/janet-shlex.git"
  ])

(post-deps

### User config

(def *static-build* (= (or (os/getenv "HERMES_STATIC_BUILD") "yes") "yes"))

### End of user config

(def *lib-archive-cflags*
  (shlex/split
    (sh/$$_ ~[pkg-config --cflags ,;(if *static-build* ['--static] []) libarchive])))

(def *lib-archive-lflags*
  (shlex/split
    (sh/$$_ ~[pkg-config --libs ,;(if *static-build* ['--static] []) libarchive])))

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

(def all-headers
  (filter |(string/has-suffix? ".h" $) all-src))


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
      (sh/$ ["make" (string "PREFIX=" install-root) ;extra-make]))
    (sh/$ ~[touch ,stamp-built]))

  (rule stamp-installed [stamp-built]
    (eprint "installing " name)
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
  :src-sha256sum "a9c1c3c2647359a550a4a6d0fb7b13cbe00870c1b7e57a6b069992354b57ecaf"
  :extra-make (when *static-build* ["EXTRA_LDFLAGS=--static"]))

(defn declare-simple-c-prog
  [&keys {
    :name name
    :src src
    :extra-cflags extra-cflags
    :extra-lflags extra-lflags
  }]
  (default extra-cflags [])
  (default extra-lflags [])
  (def out (string "build/" name))
  (rule out src
    (sh/$ [
      (or (os/getenv "CC") "gcc")
      ;extra-cflags
      ;(if *static-build* ["--static"] [])
      ;src
      ;extra-lflags
      "-o" out
    ]))

  (each h all-headers
    (add-dep out h)))

(declare-simple-c-prog
  :name "hermes-tempdir"
  :src ["src/fts.c" "src/hermes-tempdir-main.c"])

(declare-simple-c-prog
  :name "hermes-namespace-container"
  :src ["src/hermes-namespace-container-main.c"])

(declare-simple-c-prog
  :name "hermes-minitar"
  :src ["src/hermes-minitar-main.c"]
  :extra-cflags *lib-archive-cflags*
  :extra-lflags *lib-archive-lflags*)

(rule "build/hermes-signify" ["third-party/signify/stamp_installed"]
  (sh/$ ~[cp "third-party/install-root/bin/signify" "build/hermes-signify"]))

(declare-native
  :name "_hermes"
  :headers ["src/hermes.h"
            "src/sha1.h"
            "src/sha256.h"
            "src/fts.h"]
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
           "src/unpack.c"
           "src/fts.c"]
  :cflags [;*lib-archive-cflags*]
  :lflags [;*lib-archive-lflags*])


(declare-executable
  :name "hermes"
  :entry "src/hermes-main.janet"
  :lflags [;*lib-archive-lflags*
           ;(if *static-build* ["-static"] [])]
  :deps all-src)

(declare-executable
  :name "hermes-pkgstore"
  :entry "src/hermes-pkgstore-main.janet"
  :cflags [;*lib-archive-cflags*]
  :lflags [;*lib-archive-lflags*
           ;(if *static-build* ["-static"] [])]
  :deps all-src)

(declare-executable
  :name "hermes-builder"
  :entry "src/hermes-builder-main.janet"
  :lflags [;*lib-archive-lflags*
           ;(if *static-build* ["-static"] [])]
  :deps all-src)

(each bin ["hermes" "hermes-pkgstore" "hermes-builder"]
  (def bin (string "build/" bin))
  (add-dep bin "build/_hermes.so")
  (add-dep bin "build/_hermes.a")
  (add-dep bin "build/_hermes.meta.janet"))

(def output-bins
  ["hermes"
   "hermes-pkgstore"
   "hermes-builder"
   "hermes-tempdir"
   "hermes-signify"
   "hermes-minitar"
   "hermes-namespace-container"])

(rule "build/hermes.tar.gz" (map |(string "build/" $) output-bins)
  (sh/$ ~[
     tar -C ./build
     -czf build/hermes.tar.gz
     --files-from=-
    ]
    :redirects [[stdin (string/join output-bins "\n")]]))

(add-dep "build" "build/hermes.tar.gz")
)
