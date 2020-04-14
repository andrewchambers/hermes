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
  ])

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

(rule "build/hermes-tempdir" ["src/hermes-tempdir-main.c"]
  (shell "gcc" "src/hermes-tempdir-main.c" "-o" "build/hermes-tempdir"))

(declare-executable
  :name "hermes"
  :entry "src/hermes-main.janet"
  :deps ["build/hermes-tempdir"])

(declare-executable
  :name "hermes-pkgstore"
  :entry "src/hermes-pkgstore-main.janet"
  :deps ["build/hermes-tempdir"])

(declare-executable
  :name "hermes-builder"
  :entry "src/hermes-builder-main.janet")
