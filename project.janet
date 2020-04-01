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
  :headers ["hermes.h" "sha1.h" "sha256.h"]
  :source ["hermes.c" "scratchvec.c" "sha1.c" "sha256.c"
           "pathhash.c" "pkghash.c" "deps.c" "hashscan.c"
           "base16.c"])

(declare-executable
  :name "hermes"
  :entry "hermes-main.janet")

(declare-executable
  :name "hermes-pkgstore"
  :entry "hermes-pkgstore-main.janet")

(declare-executable
  :name "hermes-builder"
  :entry "hermes-builder-main.janet")