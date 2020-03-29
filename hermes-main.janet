(import argparse)
(import sh)
(import process)
(import ./hermes)

(var *store-path* "/hermes")

(defn- unknown-command
  []
  (eprintf "unknown command: %v" (get (dyn :args) 0))
  (os/exit 1))

(defn eval-string-in-env
  [str env]
  (var state (string str))
  (defn chunks [buf _]
    (def ret state)
    (set state nil)
    (when ret
      (buffer/push-string buf str)
      (buffer/push-string buf "\n")))
  (var returnval nil)
  (run-context {:chunks chunks
                :on-compile-error (fn [x y z]
                                    (bad-compile x y z)
                                    (os/exit 1))
                :on-parse-error (fn [x y]
                                  (bad-parse x y)
                                  (os/exit 1))
                :fiber-flags :i
                :on-status (fn [f val]
                             (if-not (= (fiber/status f) :dead)
                               (error val))
                             (set returnval val))
                :source "--expression"
                :env env})
  returnval)

(def- init-params
  ["Init the hermes package store."])

(defn- init
  []
  (def parsed-args (argparse/argparse ;init-params))
  (unless parsed-args
    (os/exit 1))

  (def pkgstore-cmd @["hermes-pkgstore" "init" "-s" *store-path*])
  (os/exit (process/run pkgstore-cmd)))

(def- build-params
  ["Build a hermes package."
   "module"
     {:kind :option
      :short "m"
      :help "Path to the module in which to run 'expression'."}
   "expression"
     {:kind :option
      :short "e"
      :help "Expression to build."}
   "output" 
     {:kind :option
      :short "o"
      :default "./result"
      :help "Path to where package output link will be created."}
   "no-out-link" 
     {:kind :flag
      :short "n"
      :help "Do not create an output link."}])

(defn- build
  []
  (def parsed-args (argparse/argparse ;build-params))
  (unless parsed-args
    (os/exit 1))
  
  (def env 
    (if (parsed-args "module")
      (hermes/load-pkgs (parsed-args "module"))
      root-env))

  (def pkg (eval-string-in-env (get parsed-args "expression" "default-pkg") env ))

  (unless (= (type pkg) :hermes/pkg)
    (eprintf "expression did not return a valid package, got %v" pkg)
    (os/exit 1))

  (def tmpdir (string (sh/$$_ ["mktemp" "-d"])))
  (os/exit 
    (defer (sh/$ ["rm" "-rf" tmpdir])
      
      (def thunk (string tmpdir "/pkg.thunk"))
      
      (spit thunk (marshal pkg hermes/marshal-client-pkg-registry))
      
      (def pkgstore-cmd @["hermes-pkgstore" "build" "-s" *store-path* "-t" thunk])
      
      (when (parsed-args "no-out-link")
        (array/concat pkgstore-cmd ["-n"]))

      (when (parsed-args "output")
        (array/concat pkgstore-cmd ["-o" (parsed-args "output")]))
      
      (process/run pkgstore-cmd))))

(def- gc-params
  ["Run the package garbage collector."])

(defn- gc
  []
  (def parsed-args (argparse/argparse ;gc-params))
  (unless parsed-args
    (os/exit 1))
  
  (def pkgstore-cmd @["hermes-pkgstore" "gc" "-s" *store-path*])
  (os/exit (process/run pkgstore-cmd)))

(defn main
  [&]
  (def args (dyn :args))
  (set *store-path* (os/getenv "HERMES_STORE" *store-path*))
  (with-dyns [:args (array/slice args 1)]
    (match args
      [_ "init"] (init)
      [_ "build"] (build)
      [_ "gc"] (gc)
      _ (unknown-command)))
  nil)