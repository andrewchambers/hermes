(declare-project
  :name "x"
  :author "Andrew Chambers"
  :license "MIT"
  :url "https://github.com/andrewchambers/x"
  :repo "git+https://github.com/andrewchambers/x.git")

(declare-source
    :name "x"
    :source ["x.janet"])

(declare-native
    :name "_x"
    :cflags ["-g"]
    :source ["x.c" "sha1.c"])
