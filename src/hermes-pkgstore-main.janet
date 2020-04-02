(import argparse)
(import ./pkgstore)
(import ./builder)

(defn- unknown-command
  []
  (eprintf "unknown command: %v" (get (dyn :args) 0 "<no command specified>"))
  (os/exit 1))

(def- init-params
  ["Init the hermes package store."
   "store" 
     {:kind :option
      :short "s"
      :required true
      :help "Package store to initialize."}])

(defn- init
  []
  (def parsed-args (argparse/argparse ;init-params))
  (unless parsed-args
    (os/exit 1))
  (pkgstore/set-store-path (parsed-args "store"))
  (pkgstore/init-store))

(def- build-params
  ["Build a marshalled package."
   "store" 
     {:kind :option
      :short "s"
      :required true
      :help "Package store to use for build."}
   "package" 
     {:kind :option
      :short "p"
      :required true
      :help "Path to marshalled package."}
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
  
  (pkgstore/set-store-path (parsed-args "store"))

  (def pkg (unmarshal (slurp (parsed-args "package")) builder/builder-load-registry))

  (unless (= (type pkg) :hermes/pkg)
    (error (string/format "pkg did did not return a valid package, got %v" pkg)))

  (def out-link (unless (parsed-args "no-out-link") (parsed-args "output")))

  (pkgstore/build pkg out-link)
  
  (print (pkg :path)))

(def- gc-params
  ["Run the package garbage collector."
   "store" 
     {:kind :option
      :short "s"
      :required true
      :help "Package store to run the garbage collector on."}])

(defn- gc
  []
  (def parsed-args (argparse/argparse ;gc-params))
  (unless parsed-args
    (os/exit 1))
  (pkgstore/set-store-path (parsed-args "store"))
  (pkgstore/gc))

(defn main
  [&]
  (def args (dyn :args))
  (with-dyns [:args (array/slice args 1)]
    (match args
      [_ "init"] (init)
      [_ "build"] (build)
      [_ "gc"] (gc)
      _ (unknown-command)))
  nil)