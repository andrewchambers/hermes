(declare-project
  :name "hermes"
  :author "Andrew Chambers"
  :license "MIT"
  :url "https://github.com/andrewchambers/hermes"
  :repo "git+https://github.com/andrewchambers/hermes.git")

(declare-source
  :name "hermes"
  :source ["hermes.janet"])

(declare-native
  :name "_hermes"
  :cflags ["-g"]
  :headers ["hermes.h" "sha1.h"]
  :source ["hermes.c" "util.c" "sha1.c" "pkghash.c" "deps.c" "hashscan.c"])

#(declare-executable
# :name "hermes"
# :entry "main.janet")