(import argparse)
(import path)
(import ./pkgstore)
(import ./builtins)
(import ../build/_hermes)

(defn die [& args]
  (eprint (string ;args))
  (os/exit 1))

(defn drop-setuid+setgid-privs
  []
  (def uid (_hermes/getuid))
  (def gid (_hermes/getgid))
  (_hermes/setegid gid)
  (_hermes/setgid gid)
  (_hermes/setuid uid)
  (_hermes/seteuid uid))

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
   "parallelism" 
      {:kind :option
       :short "j"
       :default "1"
       :help "Pass a parallelism hint to package builders."}
   "ttl" 
      {:kind :option
       :help "Only allow garbage collection of the package after ttl seconds."}
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

  (def pkg (unmarshal (slurp (parsed-args "package")) builtins/load-registry))

  (unless (= (type pkg) :hermes/pkg)
    (error (string/format "pkg did did not return a valid package, got %v" pkg)))

  (def parallelism (or (scan-number (parsed-args "parallelism"))
                       (error "expected a number for --parallelism")))

  (def ttl
    (when (parsed-args "ttl")
      (or (scan-number (parsed-args "ttl"))
          (error "expected a number of seconds for --ttl"))))

  (def fetch-socket-path (parsed-args "fetch-socket-path"))
  ((fn configure-fetch-socket
    [&opt nleft]
    (default nleft 5)
    (when (> 0 nleft)
      (error (string "fetch-socket " fetch-socket-path "never appeared")))
    (if (os/stat fetch-socket-path)
      (do
        # We must make the fetch socket
        # readable by any user so that build users
        # can connect.
        # protected by being in a private directory.
        # We should investigate other ways to do
        # this if possible.
        (os/chmod fetch-socket-path 8r777)
        nil)
      (do
        # If the socket is coming via ssh, its not easy to
        # tell when it will be ready. We can wait for it to simplify.
        (def wait-for 0.2)
        (os/sleep wait-for)
        (configure-fetch-socket (- nleft wait-for))))))

  (pkgstore/build
    :pkg pkg
    :fetch-socket-path fetch-socket-path
    :gc-root (unless (parsed-args "no-out-link") (parsed-args "output"))
    :parallelism parallelism
    :ttl ttl)
  
  (print (pkg :path)))

(def- gc-params
  ["Run the package garbage collector."
   "ignore-ttl" 
     {:kind :flag
      :help "Ignore package ttl roots."}
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

  (pkgstore/gc :ignore-ttl (parsed-args "ignore-ttl")))

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
      :help "Path to where package output link will be created."}
    "allow-untrusted" 
     {:kind :flag
      :help "Allow the receive end store owner to ignore failed trust challenges"}])

(defn- recv
  []
  (def parsed-args (argparse/argparse ;recv-params))

  (unless parsed-args
    (os/exit 1))

  (def store (parsed-args "store"))

  (unless (= store "")
    (drop-setuid+setgid-privs))

  (pkgstore/open-pkg-store store)
  (pkgstore/recv-pkg-closure
    stdout stdin (parsed-args "output") :allow-untrusted (parsed-args "allow-untrusted")))

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