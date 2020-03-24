(import sh)
(import sqlite3)
(import flock)
(import jdn)
(import _hermes)

(def store-path "/tmp/hpkgs")

(defn assert-dir-hash
  [path expected]
  
  (def sha256sum-bin (comptime (string (sh/$$_ ["which" "sha256sum"]))))
  
  (defn dir-hash
    [hasher path]
    (def wd (os/cwd))
    (defer (os/cd wd)
      (os/cd path)
      (sh/$$
        (sh/pipeline [
          ["find" "." "-print0"]
          ["sort" "-z"]
          ["tar"
            "-c"
            "-f" "-"
            "--numeric-owner"
            "--owner=0"
            "--group=0"
            "--mode=go-rwx,u-rw"
            "--mtime=1970-01-01"
            "--no-recursion"
            "--null"
            "--files-from" "-"]
          hasher
        ]))))

    (def actual
      (match (string/split ":" expected)
        ["sha256" _]
          (do
            (def actual
              (as-> [sha256sum-bin "-b" "-"] _
                    (dir-hash _ path)
                    (string/split " " _)
                    (first _)))
            (string "sha256:" actual))
        _ 
          (error (string "unsupported hash format - " expected))))

    (unless (= expected actual)
        (error (string/format "expected %v to have hash %s but got %s" path expected actual))))

(defn- fetch
  [url &opt dest]
  (def url
    (if (or (string/has-prefix? "." url)
            (string/has-prefix? "/" url))
      (do
        (def tar-bin (comptime (string (sh/$$_ ["which" "readlink"]))))
        (string "file://" (sh/$ ["readlink" "-f" url])))
      url))
  (default dest (last (string/split "/" url)))
  (def curl-bin (comptime (string (sh/$$_ ["which" "curl"]))))
  (sh/$ [curl-bin "-L" "-o" dest url])
  dest)

(defn- unpack
  [path &opt &keys {
    :dest dest
    :strip nstrip
  }]
  (default dest "./")
  (default nstrip 0)
  (unless (os/stat dest)
    (os/mkdir dest))
  (def tar-bin (comptime (string (sh/$$_ ["which" "tar"]))))
  (sh/$ [tar-bin (string "--strip-components=" nstrip) "-avxf" path "-C" dest]))

(def builder-env (make-env root-env))
(put builder-env 'pkg
  @{:value (fn [&] (error "pkg cannot be invoked inside a builder"))})
(put builder-env 'fetch  @{:value fetch})
(put builder-env 'unpack @{:value unpack})
(put builder-env 'sh/$   @{:value sh/$})
(put builder-env 'sh/$$  @{:value sh/$$})
(put builder-env 'sh/$$_ @{:value sh/$$_})
(put builder-env 'sh/$?  @{:value sh/$?})
(def builder-load-registry (env-lookup builder-env))
(def builder-registry (invert builder-load-registry))

(defn pkg-hash
  [pkg]
  (_hermes/pkg-hash store-path builder-registry pkg))

(defn pkg
  [&keys {
    :builder builder
    :name name
    :out-hash out-hash
  }]
  (_hermes/pkg builder name out-hash))

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

(defn load-pkgs
  [fpath]

  (defn clear-table 
    [t]
    (each k (keys t) # don't mutate while iterating.
      (put t k 0))
    t)
  
  (defn clear-array
    [a]
    (array/remove a 0 (length a))
    a)

  (def saved-process-env (save-process-env))
  (def saved-root-env (merge-into @{}))
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
      
    # Configure the pkg loading env.
    # We update the root env in place so
    # that every file has the extra builtins.
    (put root-env 'pkg    @{:value pkg})
    (put root-env 'fetch  @{:value fetch})
    (put root-env 'unpack @{:value unpack})
    (put root-env 'sh/$   @{:value sh/$})
    (put root-env 'sh/$$  @{:value sh/$$})
    (put root-env 'sh/$$_ @{:value sh/$$_})
    (put root-env 'sh/$?  @{:value sh/$?})

    # Clear module cache.
    (clear-table module/cache)
    
    # Remove all paths, to ensure hermetic package env.
    (defn- check-. [x] (if (string/has-prefix? "." x) x))
    (clear-array module/paths)
    (array/concat module/paths @[[":cur:/:all:.janet" :source check-.]])

    # XXX it would be nice to not exit on error, but raise an error.
    # this is easier for now though.
    (dofile fpath :exit true)))

(defn init-store
  [&opt path]
  (default path store-path)
  (os/mkdir path)
  (os/mkdir (string path "/lock"))
  (spit (string path "/lock/gc.lock") "")

  (os/mkdir (string path "/pkg"))
  (with [db (sqlite3/open (string path "/hermes.db"))]
    (sqlite3/eval db "begin transaction;")
    (when (empty? (sqlite3/eval db "select name from sqlite_master where type='table' and name='Meta'"))
      (sqlite3/eval db "create table Roots(LinkPath text primary key);")
      (sqlite3/eval db "create table Pkgs(Hash text primary key, Path text);")
      (sqlite3/eval db "create unique index PkgsPathIndex on Pkgs(Path);")
      (sqlite3/eval db "create table Meta(Key text primary key, Value text);")
      (sqlite3/eval db "insert into Meta(Key, Value) Values('StoreVersion', 1);")
      (sqlite3/eval db "commit;")))
  nil)

(defn compute-dep-info
  [pkg]
  (def deps @{})
  (def order @[])
  (defn compute-dep-info2
    [pkg]
    (if (deps pkg)
      nil
      (let [direct-deps (_hermes/pkg-dependencies pkg)]
        (put deps pkg (keys direct-deps))
        (eachk dep direct-deps
          (compute-dep-info2 dep))
        (array/push order pkg))))
  (compute-dep-info2 pkg)
  {:deps deps
   :order order})

(defn ref-scan
  [pkg]
  (def ref-set (_hermes/ref-scan store-path pkg @{}))
  (sorted (keys ref-set)))


(defn- build-lock-cleanup
  []
  (def all-locks (os/dir (string store-path "/lock")))
  (def pkg-locks (filter |(not= $ "gc.lock") all-locks))
  (each l pkg-locks
    (os/rm (string store-path "/lock/" l))))

(defn- optimistic-build-lock-cleanup
  []
  (when-let [gc-lock (flock/acquire (string store-path "/lock/gc.lock") :noblock :exclusive)]
    (build-lock-cleanup)
    (:close gc-lock)))

(defn build
  [pkg &opt root]

  # Copy registry so we can update it as we build packages.
  (def registry (merge-into @{} builder-registry))
  (def load-registry (invert registry))
  (put load-registry '*pkg-already-built* (fn [&] nil))

  (with [flock (flock/acquire (string store-path "/lock/gc.lock") :block :shared)]
  (with [db (sqlite3/open (string store-path "/hermes.db"))]
    (def dep-info (compute-dep-info pkg))
    (each p (dep-info :order)
      # Hash the packages in order as children must be hashed first.
      (pkg-hash p))

    (defn has-pkg
      [pkg]
      (not (empty? (sqlite3/eval db "select 1 from Pkgs where Hash=:hash" {:hash (pkg :hash)}))))

    (defn build2
      [pkg &opt root]
      (each dep (get-in dep-info [:deps pkg])
        (unless (has-pkg dep)
          (build2 dep))
        (put registry (dep :builder) '*pkg-already-built*))

      (with [flock (flock/acquire (string store-path "/lock/" (pkg :hash) ".lock") :block :exclusive)]
        # After aquiring the package lock, check again that it doesn't exist.
        # This is in case multiple builders were waiting.
        (when (not (has-pkg pkg))
          (when (os/stat (pkg :path))
            (sh/$ ["chmod" "-v" "-R" "u+w" (pkg :path)])
            (sh/$ ["rm" "-vrf" (pkg :path)]))
          (sh/$ ["mkdir" "-v" (pkg :path)])
          (def env (save-process-env))
          (def tmpdir (string (sh/$$_ ["mktemp" "-d"])))
          (defer (do
                   (restore-process-env env)
                   (sh/$ ["chmod" "-R" "u+w" tmpdir])
                   (sh/$ ["rm" "-rf" tmpdir]))
            # Wipe env so package builds
            # don't accidentally rely on any state.
            (eachk k (env :environ)
              (os/setenv k nil))
            (os/cd tmpdir)
            (with-dyns [:pkg-out (pkg :path)]
              (def frozen-builder (marshal (pkg :builder) registry))
              (def builder (unmarshal frozen-builder load-registry))
              (builder)))
          
          (when-let [out-hash (pkg :out-hash)]
            (assert-dir-hash (pkg :path) out-hash))

          (def scanned-refs (ref-scan pkg))
          
          (spit (string (pkg :path) "/.hpkg.jdn") (string/format "%j" {
            :name (pkg :name)
            :hash (pkg :hash)
            # We support sending packages built at different store paths.
            :store-path store-path
            :scanned-refs scanned-refs
          }))

          # Set package permissions.
          (sh/$ ["chmod" "-v" "-R" "a-w,a+r,a+X" (pkg :path)])
          (sqlite3/eval db "insert into Pkgs(Hash, Path) Values(:hash, :path)" {:hash (pkg :hash) :path (pkg :path)}))

        (when root
          (sqlite3/eval db "insert or ignore into Roots(LinkPath) Values(:root);" {:root root})
          (def tmplink (string root ".hermes-root"))
          (when (os/stat tmplink)
            (os/rm tmplink))
          (os/link (pkg :path) tmplink true)
          (os/rename tmplink root)))

        nil)

    (build2 pkg root)))
    (optimistic-build-lock-cleanup)
    nil)

(defn path-to-pkg-hash
  [path]
  (def tail-peg (comptime (peg/compile ~{
    :hash (capture (repeat 40 (choice (range "09") (range "af"))))
    :main (sequence "/pkg/"  :hash)
  })))
  (when (string/has-prefix? store-path path)
    (def tail (string/slice path (length store-path)))
    (first (peg/match tail-peg tail))))

(defn gc
  []
  (with [flock (flock/acquire (string store-path "/lock/gc.lock") :block :exclusive)]
  (with [db (sqlite3/open (string store-path "/hermes.db"))]

    (def work-q @[])
    (def visited @{})

    (defn process-roots
      []
      (def dead-roots @[])
      (def roots (map |($ "LinkPath") (sqlite3/eval db "select * from roots")))
      (each root roots
        (if-let [rstat (os/lstat root)
                 is-link (= :link (rstat :mode))]
          (array/push work-q (path-to-pkg-hash (os/readlink root)))
          (array/push dead-roots root)))
      (sqlite3/eval db "begin transaction;")
      (each root dead-roots
        (sqlite3/eval db "delete from Roots where LinkPath = :root;" {:root root}))
      (sqlite3/eval db "commit;"))

    (defn gc-walk []
      (unless (empty? work-q)
        (def hash (array/pop work-q))
        (if (visited hash)
          (gc-walk)
          (do
            (put visited hash true)
            (when-let [row (first (sqlite3/eval db "select Path from Pkgs where Hash = :hash;" {:hash hash}))
                       pkg-dir (row "Path")]
              (def pkg-info (jdn/decode-one (slurp (string pkg-dir "/.hpkg.jdn"))))
              (array/concat work-q (pkg-info :scanned-refs))
              (gc-walk))))))
    
    (process-roots)
    (gc-walk)

    (each pkg-name (os/dir (string store-path "/pkg/"))
      (def pkg-dir (string store-path "/pkg/" pkg-name))
      (def pkg-hash (path-to-pkg-hash pkg-dir))
      (unless (visited hash)
        (eprintf "deleting %s" pkg-dir)
        (sqlite3/eval db "delete from Pkgs where Hash = :hash" {:hash pkg-hash})
        (sh/$ ["chmod" "-R" "u+w" pkg-dir])
        (sh/$ ["rm" "-rf" pkg-dir])))

    (build-lock-cleanup)

    nil)))