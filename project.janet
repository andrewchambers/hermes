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

(def *static-build* (= (or (os/getenv "HERMES_STATIC_BUILD") "no") "yes"))

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

(def hermes-src
  (->>  (os/dir "./src")
        (map |(string "src/" $))
        (filter src-file?)))

(def hermes-headers
  (filter |(string/has-suffix? ".h" $) hermes-src))

(def signify-src
  (->>  (os/dir "./third-party/signify")
        (map |(string "./third-party/signify/" $))
        (filter src-file?)))

(rule "build/hermes-signify" signify-src
  (eprint "building signify")
  (def wd (os/cwd))
  (defer (os/cd wd)
    (os/cd "./third-party/signify")
    (sh/$ ["make" ;(if *static-build* ["EXTRA_LDFLAGS=--static"] [])])
    (sh/$ ["cp" "-v" "signify" "../../build/hermes-signify"])))

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

  (each h hermes-headers
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
  :deps hermes-src)

(declare-executable
  :name "hermes-pkgstore"
  :entry "src/hermes-pkgstore-main.janet"
  :cflags [;*lib-archive-cflags*]
  :lflags [;(if *static-build* ["-static"] [])
           ;*lib-archive-lflags*]
  :deps hermes-src)

(declare-executable
  :name "hermes-builder"
  :entry "src/hermes-builder-main.janet"
  :lflags [;(if *static-build* ["-static"] [])
           ;*lib-archive-lflags*]
  :deps hermes-src)

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

(phony "clean-third-party" []
  (def wd (os/cwd))
  (defer (os/cd wd)
    (os/cd "./third-party/signify")
    (sh/$ ["make" "clean"] :redirects [[stdout :null]])))


(add-dep "clean" "clean-third-party")

)
