(import hermes)
(import argparse)

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

(def- build-params
  ["Build a hermes package."
   "m" {:kind :option
        :short "m"
        :help "Module path to run expression in."}
   "e" {:kind :option
        :short "e"
        :help "Expression to build."}])

(defn- build
  []
  (def parsed-args (argparse/argparse ;build-params))
  (unless parsed-args
    (os/exit 1))
  
  (def env 
    (if (parsed-args "m")
      (hermes/load-pkgs (parsed-args "m"))
      root-env))

  (def pkg (eval-string-in-env (parsed-args "e") env ))
  (unless (= (type pkg) :hermes/pkg)
    (error (string/format "-e did not return a valid package, got %v" pkg)))
  (print (hermes/build pkg)))

(defn main
  [&]
  (def args (dyn :args))
  (with-dyns [:args (array/slice args 1)]
    (match args
      [_ "build"] (build)
      _ (unknown-command)))
  nil)