(import argparse)
(import ./pkgstore)
(import ./builder)
(import ../build/_hermes)

(defn die [& args]
  (eprint (string ;args))
  (os/exit 1))

(defn drop-setuid+setgid-privs
  []
  (def uid (_hermes/getuid))
  (def gid (_hermes/getgid))
  (_hermes/seteuid uid)
  (_hermes/setegid gid))

(defn- unknown-command
  []
  (die
    (string/format "unknown command: %v" (get (dyn :args) 0 "<no command specified>"))))

(def- init-params
  ["Init the hermes package store."
   "store" 
     {:kind :option
      :short "s"
      :default ""
      :help "Package store to initialize."}])

(defn- init
  []
  # N.B.
  # Because we support installing the pkgstore as setuid root.
  # We must always perform init as the real user.
  (drop-setuid+setgid-privs)

  (def parsed-args (argparse/argparse ;init-params))
  (unless parsed-args
    (os/exit 1))


  (def store (parsed-args "store"))
  (def mode (if (= store "") :multi-user :single-user))
  (pkgstore/init-store mode store))

(def- build-params
  ["Build a marshalled package."
   "store" 
     {:kind :option
      :short "s"
      :default ""
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
      :help "Do not create an output link."}
     "no-out-link"])

(defn- build
  []

  (def parsed-args (argparse/argparse ;build-params))
  (unless parsed-args
    (os/exit 1))
  
  (def store (parsed-args "store"))
  
  # N.B. If it is a single user store, we must drop privileges
  # to avoid excess privileges when pkgstore is setuid root.
  (unless (= store "")
    (drop-setuid+setgid-privs))

  (pkgstore/open-pkg-store store)

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
      :default ""
      :help "Package store to run the garbage collector on."}])

(defn- gc
  []
  (def parsed-args (argparse/argparse ;gc-params))

  (unless parsed-args
    (os/exit 1))

  (def store (parsed-args "store"))

  # N.B. If it is a single user store, we must drop privileges
  # to avoid excess privileges when pkgstore is setuid root.
  (unless (= store "")
    (drop-setuid+setgid-privs))

  (pkgstore/open-pkg-store (parsed-args "store"))

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