(import argparse)
(import sh)
(import path)
(import process)
(import ./fetch)
(import ./hash)
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

(defn pkg
  [&keys {
    :builder builder
    :name name
    :content content
    :force-refs force-refs
    :extra-refs extra-refs
    :weak-refs weak-refs
  }]
  (_hermes/pkg builder name content force-refs extra-refs weak-refs))

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

(def *content-map* @{})

(defn- fetch*
  [hash dest]
  (error "fetch* is not supported while loading package definitions"))

(defn- unpack
  [path &opt &keys {
    :dest dest
    :unwrap unwrap
  }]
  (error "unpack is not supported while loading package definitions"))

(defn add-mirror
  [hash url]
  (if-let [mirrors (get *content-map* hash)]
    (array/push mirrors url)
    (put *content-map* hash @[url])))

(defn fetch
  [&keys {
    :url url
    :hash hash
    :file-name file-name
  }]

  (default file-name (last (string/split "/" url))) # XXX rfind would be nice in stdlib.

  (var url
    (cond
      (string? url)
        url
      (symbol? url)
        (string url)
      (error (string/format "fetch url must be a string or symbol, got %v" url))))

  (add-mirror hash url)

  (pkg
    :name
      file-name
    :content
      {file-name {:content hash}}
    :builder
      (fn []
        (fetch* hash (string (dyn :pkg-out) "/" file-name)))))

(defn local-file*
  [path &opt hash]
  (default hash (hash/hash "sha256" path))
  (fetch :url (string "file://" path) :hash hash))

(defmacro local-file
  [path &opt hash]
  (def source (path/abspath (or (dyn :source) (path/join (os/cwd) "--expression"))))
  (def basename (path/basename source))
  (def dir (string/slice source 0 (- -2 (length basename))))   # XXX upstream path/dir.
  (defn local-path
    [path]
    (def path
      (cond
        (string? path)
          path
        (symbol? path)
          (string path)
        (error "path must be a string or symbol")))
    (when (path/abspath? path)
      (error "path must be a relative path"))
    (path/join dir path))
  ~(,local-file* (,local-path ,path) ,hash))

# TODO XXX This environment should be a sandbox, loading
# packages should be effectively a pure operation. When the 
# actual build takes place, we swap the sandbox stubs for the real implementaion.
# TODO XXX load from .hpkg extension.

(def pkg-loading-env (merge-into @{} root-env))
(put pkg-loading-env 'pkg    @{:value pkg})
(put pkg-loading-env 'fetch  @{:value fetch})
(put pkg-loading-env 'fetch* @{:value fetch*})
(put pkg-loading-env 'local-file  @{:value local-file :macro true})
(put pkg-loading-env 'local-file* @{:value local-file*})
(put pkg-loading-env 'fetch* @{:value fetch*})
(put pkg-loading-env 'add-mirror @{:value add-mirror})
(put pkg-loading-env 'unpack @{:value unpack})
(put pkg-loading-env 'sh/$   @{:value sh/$})
(put pkg-loading-env 'sh/$$  @{:value sh/$$})
(put pkg-loading-env 'sh/$$_ @{:value sh/$$_})
(put pkg-loading-env 'sh/$?  @{:value sh/$?})
(put pkg-loading-env 'sh/glob  @{:value sh/glob})
(def marshal-client-pkg-registry (invert (env-lookup pkg-loading-env)))

(defn load-pkgs
  [fpath]

  (def saved-process-env (save-process-env)) # XXX shouldn't be needed with proper sandboxed env.
  (def saved-root-env (merge-into @{} root-env))
  (def saved-mod-paths (array ;module/paths))
  (def saved-mod-cache (merge-into @{} module/cache))

  (defer (do
           (clear-table module/cache)
           (merge-into module/cache saved-mod-cache)

           (clear-array module/paths)
           (array/concat module/paths saved-mod-paths)

           (clear-table root-env)
           (merge-into root-env saved-root-env)
           
           (restore-process-env saved-process-env))
    
    (clear-table root-env)
    (merge-into root-env pkg-loading-env)

    # Clear module cache.
    (clear-table module/cache)
    
    # Remove all paths, to ensure hermetic package env.
    (defn- check-. [x] (if (string/has-prefix? "." x) x))
    (clear-array module/paths)
    (array/concat module/paths @[[":cur:/:all:.janet" :source check-.]])

    (clear-table *content-map*)

    # XXX it would be nice to not exit on error, but raise an error.
    # this is easier for now though.
    (merge-into @{} pkg-loading-env (dofile fpath :exit true))))

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
  
  (def env 
    (if (parsed-args "module")
      (load-pkgs (parsed-args "module"))
      pkg-loading-env))

  (def pkg (eval-string-in-env (get parsed-args "expression" "default-pkg") env ))

  (unless (= (type pkg) :hermes/pkg)
    (eprintf "expression did not return a valid package, got %v" pkg)
    (os/exit 1))

  (def tmpdir (string (sh/$$_ ["mktemp" "-d"])))
  (os/chmod tmpdir 8r700)

  (def fetch-socket-path (string tmpdir "/fetch.sock"))
  (def fetch-socket (_hermes/unix-listen fetch-socket-path))
  (os/chmod fetch-socket-path 8r777)
  (def fetch-server (fetch/spawn-server fetch-socket *content-map*))

  (def parallelism (parsed-args "parallelism"))

  (os/exit 
    (defer (sh/$ ["rm" "-rf" tmpdir])
      
      (def pkg-path (string tmpdir "/hermes-build.pkg"))
      
      (spit pkg-path (marshal pkg marshal-client-pkg-registry))
      
      (def pkgstore-cmd @["hermes-pkgstore" "build" "-j" parallelism "-f" fetch-socket-path "-s" *store-path* "-p" pkg-path])
      
      (when (parsed-args "no-out-link")
        (array/concat pkgstore-cmd ["-n"]))

      (when (parsed-args "ttl")
        (array/concat pkgstore-cmd ["--ttl" (parsed-args "ttl")]))

      (when (parsed-args "output")
        (array/concat pkgstore-cmd ["-o" (parsed-args "output")]))
      
      (process/run pkgstore-cmd))))

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
  
  (unless (= 2 (length (parsed-args :default)))
    (error "expected a 'from' and 'to' argument"))

  (def [from to] (parsed-args :default))

  # TODO pass in config.
  (def ssh-peg (peg/compile ~{
    :main (* "ssh://" (capture (some (* (not "/") 1)))  (capture (any 1)))
  }))

  (def from-cmd
    (if-let [[host from] (peg/match ssh-peg from)]
      @["ssh" "-C" host "hermes-pkgstore" "send" "-p" from]
      @["hermes-pkgstore" "send" "-p" from]))

  (def to-cmd
    (do
      (def store-args
        (if-let [to-store (parsed-args "to-store")]
          @["-s" to-store] 
          @[]))
      (if-let [[host to] (peg/match ssh-peg to)]
        @["ssh" "-C" host "--" "hermes-pkgstore" "recv" ;store-args ;(if to ["-o"  to] [])]
        @["hermes-pkgstore" "recv" ;store-args "-o" to])))

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