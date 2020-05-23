(import sh)

(def td (sh/$<_ mktemp -d))
(defer (do
         (sh/$ chmod -R +w ,td)
         (sh/$ rm -rf ,td))

  (os/cd td)

  # We can build a simple package.
  (defn simple-build []
    (sh/$<_ hermes build -e `
      (pkg
        :builder 
        (fn []
          (spit (string (dyn :pkg-out) "/result.txt")
                "pass")))`))

  (def out (simple-build))
  (assert (= (string (slurp "./result/result.txt")) "pass"))
  (assert (= (os/readlink "./result") out))

  # Sanity test of cp command.
  (sh/$ hermes cp ./result ./result2)
  (assert (= (string (slurp "./result2/result.txt")) "pass"))

  # Sanity test of gc.
  (sh/$ hermes gc)
  (sh/$ rm ./result ./result2)
  (sh/$ hermes gc)

  # Test single user init.
  (def s1 (string td "/store1"))
  (def s2 (string td "/store2"))
  (os/setenv "HERMES_STORE" s1)
  (sh/$ hermes init)
  (sh/$ hermes init)
  (os/setenv "HERMES_STORE" s2)
  (sh/$ hermes init)

  (sh/$ cp (os/realpath (string s1 "/etc/hermes/signing-key.pub")) (string s2 "/etc/hermes/trusted-pub-keys"))

  # Copy across store
  (os/setenv "HERMES_STORE" (string td "/store1"))
  (simple-build)
  (sh/$ hermes cp -t (string td "/store2") ./result ./result2)

  (assert (= (string (slurp "./result2/result.txt")) "pass")))
