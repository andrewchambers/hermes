(import argparse)
(import path)
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
    (string/format "unknown command: %v" ((dyn :args) 0))))

(def- init-params
  ["Init the hermes package store."
   "store" 
     {:kind :option
      :short "s"
      :default ""
      :help "Package store to initialize."}])

(defn- init
  []
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
   "fetch-socket-path" 
     {:kind :option
      :short "f"
      :required true
      :help "Path to fetch socket to use during build."}
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
  
  (unless (= store "")
    (drop-setuid+setgid-privs))

  (pkgstore/open-pkg-store store)

  (def pkg (unmarshal (slurp (parsed-args "package")) builder/builder-load-registry))

  (unless (= (type pkg) :hermes/pkg)
    (error (string/format "pkg did did not return a valid package, got %v" pkg)))

  (def out-link (unless (parsed-args "no-out-link") (parsed-args "output")))

  (pkgstore/build pkg (parsed-args "fetch-socket-path") out-link)
  
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

  (unless (= store "")
    (drop-setuid+setgid-privs))

  (pkgstore/open-pkg-store store)

  (pkgstore/gc))

(def- send-params
  ["Send a package closure over stdin/stdout with the send/recv protocol."
   "package" 
     {:kind :option
      :short "p"
      :help "Path to package that is being sent."}])

(defn- send
  []
  (def parsed-args (argparse/argparse ;send-params))

  (unless parsed-args
    (os/exit 1))

  (def package (os/realpath (parsed-args "package")))
  (def hpkg-dir (let [pkg-name (path/basename package)]
                  (string/slice package 0 (- -2 (length pkg-name)))))
  
  (unless (string/has-suffix? "/hpkg" hpkg-dir)
    (error (string/format "%v is not a hermes package path" package)))

  (def store (string/slice hpkg-dir 0 -6))

  (unless (= store "")
    (drop-setuid+setgid-privs))

  (pkgstore/open-pkg-store store)
  (pkgstore/send-pkg-closure stdout stdin package))


(def- recv-params
  ["Receive a package closure sent over stdin/stdout with the send/recv protocol."
   "store" 
     {:kind :option
      :short "s"
      :default ""
      :help "Package store to receive the closure."}
    "output" 
     {:kind :option
      :short "o"
      :help "Path to where package output link will be created."}])

(defn- recv
  []
  (def parsed-args (argparse/argparse ;recv-params))

  (unless parsed-args
    (os/exit 1))

  (def store (parsed-args "store"))

  (unless (= store "")
    (drop-setuid+setgid-privs))

  (pkgstore/open-pkg-store store)
  (pkgstore/recv-pkg-closure stdout stdin (parsed-args "output")))

(defn main
  [&]
  (def args (dyn :args))
  (with-dyns [:args (array/slice args 1)]
    (match args
      [_ "init"] (init)
      [_ "build"] (build)
      [_ "gc"] (gc)
      [_ "send"] (send)
      [_ "recv"] (recv)
      _ (unknown-command)))
  nil)