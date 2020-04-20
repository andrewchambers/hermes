(import argparse)
(import sh)
(import uri)
(import path)
(import process)
(import ./download)
(import ./tempdir)
(import ./fetch)
(import ./hash)
(import ./builtins)
(import ../build/_hermes)

(var *store-path* "")

(defn- clear-table 
  [t]
  (each k (keys t) # don't mutate while iterating.
    (put t k 0))
  t)

(defn- clear-array
  [a]
  (array/remove a 0 (length a))
  a)

(defn- save-process-env
  []
  {:cwd (os/cwd)
   :environ (os/environ)})

(defn- restore-process-env
  [{:cwd cwd
    :environ environ}]
  (eachk k environ
     (os/setenv k (environ k)))
  (os/cd cwd))

(defn- load-hpkg-url
  [url args]
  (with [f (file/temp)]
    (match (download/download url |(file/write f $))
      :ok
        (file/seek f :set 0)
      [:fail err-msg]
        (error err-msg))
    (dofile f ;args)))

(defn- relative-import-path?
  [path]
  (or (string/has-prefix? "./" path)
      (string/has-prefix? "../" path)))

(defn- check-hpkg-url
  [path]
  (if-let [parsed-url (uri/parse path)
           url-scheme (parsed-url :scheme)
           url-host (parsed-url :host)
           url-path (parsed-url :path)]
    (string url-scheme "://" url-host url-path ".hpkg")
    (if-let [is-relpath (relative-import-path? path)
             current-url (dyn :source)
             source-is-string (string? current-url) # Possible :source is a file.
             parsed-url (uri/parse current-url)
             url-scheme (parsed-url :scheme)
             url-host (parsed-url :host)
             url-path (parsed-url :path)]
      (do
        (def url-path-dir (string/slice url-path 0 (- -2 (length (path/basename url-path)))))
        (def abs-path (path/posix/join url-path-dir path))
        (string url-scheme "://" url-host "/" abs-path  ".hpkg")))))

(defn- load-hpkg-path
  [path args]
  (dofile path ;args))

(defn- check-hpkg-path
  [path]
  (def path (string path ".hpkg"))
  (def path
    (if-let [is-relpath (relative-import-path? path)
             current-file (dyn :current-file)]
      (do
        (def path-dir (string/slice current-file 0 (- -2 (length (path/basename current-file)))))
        (def path (path/abspath (path/join path-dir path))))
      (when (string/has-prefix? "/" path)
        (path/normalize path))))
  path)

(defn- in-hpkg-context
  [f]
  (def saved-process-env (save-process-env))
  (def saved-root-env (merge-into @{} root-env))
  (def saved-mod-loaders (merge-into @{} module/loaders))
  (def saved-mod-paths  (array ;module/paths))
  (def saved-mod-cache  (merge-into @{} module/cache))
  

  (defer (do
           (clear-table module/cache)
           (merge-into module/cache saved-mod-cache)

           (clear-array module/paths)
           (array/concat module/paths saved-mod-paths)

           (clear-table root-env)
           (merge-into root-env saved-root-env)

           (clear-table module/loaders)
           (merge-into module/loaders saved-mod-loaders)
           
           (restore-process-env saved-process-env))
    
    (clear-table root-env)
    (merge-into root-env builtins/hermes-env)

    # Clear module cache.
    (clear-table module/cache)
    
    (clear-array module/paths)

    (put module/loaders :hpkg-url load-hpkg-url)
    (put module/loaders :hpkg-path load-hpkg-path)
    (array/push module/paths [check-hpkg-url  :hpkg-url])
    (array/push module/paths [check-hpkg-path :hpkg-path])
    (clear-table builtins/*content-map*)

    (f)))

(defn- eval-expression-in-env
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

(defn load-pkgs
  [expr &opt module-path]
  (in-hpkg-context
    (fn []
      (def env
        (if module-path
          (do
            (def module-path
              (if (string/has-suffix? ".hpkg" module-path)
                (string/slice module-path 0 -6)
                module-path))
            # Convert to absolute so we don't have to worry
            # about where our current path is relative to.
            (def module-path
              (if-let [parsed-url (uri/parse module-path)
                       url-scheme (parsed-url :scheme)]
                module-path
                (path/abspath module-path)))
            (merge-into @{} builtins/hermes-env (require module-path)))
          (merge-into @{} builtins/hermes-env)))
      (eval-expression-in-env expr env))))

(defn- unknown-command
  []
  (eprintf "unknown command: %v" (get (dyn :args) 0))
  (os/exit 1))


(def- init-params
  ["Init the hermes package store."])

(defn- init
  []
  (def parsed-args (argparse/argparse ;init-params))
  (unless parsed-args
    (os/exit 1))
  (def pkgstore-cmd @[
    "hermes-pkgstore"
    "init" "-s" *store-path*
  ])
  (os/exit (process/run pkgstore-cmd)))

(def- build-params
  ["Build a hermes package."
   "module"
     {:kind :option
      :short "m"
      :help "Path to the module in which to run 'expression'."}
   "build-host"
     {:kind :option
      :help "Transparently build on a remote host."}
   "expression"
     {:kind :option
      :short "e"
      :help "Expression to build."}
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
      :help "Do not create an output link."}])

(defn- build
  []
  (def parsed-args (argparse/argparse ;build-params))
  (unless parsed-args
    (os/exit 1))
  
  (def pkg (load-pkgs (get parsed-args "expression" "default-pkg")  (parsed-args "module")))

  (unless (= (type pkg) :hermes/pkg)
    (eprintf "expression did not return a valid package, got %v" pkg)
    (os/exit 1))

  (def tmpdir (tempdir/tempdir))
  (os/chmod (tmpdir :path) 8r700)

  (def fetch-socket-path (string (tmpdir :path) "/fetch.sock"))
  (def fetch-socket (_hermes/unix-listen fetch-socket-path))
  (os/chmod fetch-socket-path 8r777)
  (def fetch-server (fetch/spawn-server fetch-socket builtins/*content-map*))

  (def parallelism (parsed-args "parallelism"))

  (def pkg-path (string (tmpdir :path) "/hermes-build.pkg"))

  (spit pkg-path (marshal pkg builtins/registry))

  (def exit-status
    (if-let [build-host (parsed-args "build-host")]
      (do
        (def rtmpdir (tempdir/tempdir build-host))
        (def rfetch-socket-path (string (rtmpdir :path) "/fetch.sock"))
        (def rpkg-path (string (rtmpdir :path) "/hermes-build.pkg"))
        (def rroot (string (rtmpdir :path) "/build.root"))
        (def fetch-proxy-cmd
          @["ssh"
            "-oStreamLocalBindMask=0111"
            "-oBatchMode=yes"
            "-oExitOnForwardFailure=yes"
            "-N"
            "-R" (string rfetch-socket-path ":" fetch-socket-path)
            build-host])
        (eprintf "%j" fetch-proxy-cmd)
        (def fetch-proxy
          (process/spawn fetch-proxy-cmd))

        (def scp-cmd @["scp"
                       "-oBatchMode=yes"
                       "-q"
                       pkg-path
                       (string build-host ":" rpkg-path)])
        (eprintf "%j" scp-cmd)
        (sh/$ scp-cmd)
        
        (def pkgstore-build-cmd
          @["ssh"
            "-oBatchMode=yes"
            build-host
            "--"
            "hermes-pkgstore" "build"
            "-j" parallelism
            "-f" rfetch-socket-path
            ;(if (= *store-path* "") [] ["-s" *store-path*])
            "-p" rpkg-path
            "-o" rroot
            ])

        (eprintf "%j" pkgstore-build-cmd)
        
        (def result-path-buf @"")
        (def build-exit-code
          (process/run pkgstore-build-cmd :redirects [[stdout result-path-buf]]))

        (unless (zero? build-exit-code)
          (os/exit build-exit-code))

        (def cp-target-args
          (if (parsed-args "no-out-link")
            []
            (if-let [output (parsed-args "output")]
              [output]
              ["./result"])))

        (:close fetch-proxy)
        # XXX add ttl to cp
        (def cp-cmd
          @["hermes" "cp" (string "ssh://" build-host rroot) ;cp-target-args])
        (eprintf "%j" cp-cmd)
        (def cp-exit-status
          (process/run cp-cmd))
        (:close rtmpdir)
        (when (zero? cp-exit-status)
          (print (string result-path-buf)))
        cp-exit-status)
      (do

        (def pkgstore-build-cmd
          @["hermes-pkgstore" "build"
            "-j" parallelism
            "-f" fetch-socket-path
            "-s" *store-path*
            "-p" pkg-path
            ;(if (parsed-args "no-out-link") ["-n"] [])
            ;(if-let [ttl (parsed-args "ttl")] ["--ttl" ttl] [])
            ;(if-let [output (parsed-args "output")] ["--output" output] [])])

        (def build-exit-code
          (process/run pkgstore-build-cmd))
        
        build-exit-code)))

  (:close tmpdir)
  (os/exit exit-status))

(def- gc-params
  ["Run the package garbage collector."
    "ignore-ttl" 
      {:kind :flag
       :help "Ignore package ttl roots."}])

(defn- gc
  []
  (def parsed-args (argparse/argparse ;gc-params))
  (unless parsed-args
    (os/exit 1))
  
  (def pkgstore-cmd
    @["hermes-pkgstore" "gc" "-s" *store-path* ;(if (parsed-args "ignore-ttl") ["--ignore-ttl"] [])])
  (os/exit (process/run pkgstore-cmd)))

(def- cp-params
  ["Copy a package closure between package stores."
   "allow-untrusted" 
     {:kind :flag
      :help "Allow the destination to ignore failed trust challenges if run by the store owner."}
   "to-store"
    {:kind :option
     :short "t"
     :help "The store copy into."}
   :default {:kind :accumulate}])

(defn- cp
  []
  (def parsed-args (argparse/argparse ;cp-params))
  (unless parsed-args
    (os/exit 1))
  
  (def nargs (length (parsed-args :default)))
  (unless (or (= 1 nargs)
              (= 2 nargs))
    (error "expected a 'from' and 'to' argument"))

  (def [from to] (parsed-args :default))

  (def ssh-peg (peg/compile ~{
    :main (* "ssh://" (capture (some (* (not "/") 1)))  (choice (capture (some 1)) (constant nil)))
  }))

  (def from-cmd
    (if-let [[host from] (peg/match ssh-peg from)]
      @["ssh"
        "-oBatchMode=yes"
        host
        "--" "hermes-pkgstore" "send" "-p" from]
      @["hermes-pkgstore" "send" "-p" from]))

  (def to-cmd
    (do
      (def store-path
        (if-let [to-store (parsed-args "to-store")]
          to-store
          *store-path*))
      (def store-args
        (if (= store-path"")
          []
          ["-s" store-path]))
      (if-let [_ to
               [host to] (peg/match ssh-peg to)]
        @["ssh"
          "-oBatchMode=yes"
          host
          "--"
          "hermes-pkgstore" "recv"
          ;store-args
          ;(if to ["-o"  to] [])]
        @["hermes-pkgstore" "recv"
            ;store-args
            ;(if to ["-o"  to] [])
            ;(if (parsed-args "allow-untrusted") ["--allow-untrusted"] [])])))

  (def [pipe1< pipe1>] (process/pipe))
  (def [pipe2< pipe2>] (process/pipe))

  (with [send-proc (process/spawn from-cmd :redirects [[stdout pipe1>] [stdin pipe2<]])]
  (with [recv-proc (process/spawn to-cmd :redirects [[stdout pipe2>] [stdin pipe1<]])]
    
    (map file/close [pipe1< pipe1> pipe2< pipe2>])

    (let [send-exit (process/wait send-proc)
          recv-exit (process/wait recv-proc)]
      (unless (and (zero? send-exit)
                   (zero? recv-exit))
        (error "copy failed"))))))

(defn main
  [&]
  (def args (dyn :args))
  (set *store-path* (os/getenv "HERMES_STORE" ""))
  (with-dyns [:args (array/slice args 1)]
    (match args
      [_ "init"] (init)
      [_ "build"] (build)
      [_ "gc"] (gc)
      [_ "cp"] (cp)
      _ (unknown-command)))
  nil)