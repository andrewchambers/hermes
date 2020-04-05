(import sh)
(import sqlite3)
(import path)
(import flock)
(import jdn)
(import ./builder)
(import ../build/_hermes :as _hermes)

(var- *store-path* nil)
(var- *store-config* nil)

(defn open-pkg-store
  [store-path]

  (set *store-path* (if (= store-path "")
                      ""
                      (let [abs (path/abspath store-path)]
                        (if (= abs "/") "" abs))))
  
  (def uid (_hermes/getuid))
  (def euid (_hermes/geteuid))
  
  # setuid mode should only be used for a multi-user store
  # at the root path. We cannot allow non root users to
  # access other stores as this creates opportunities for bugs...
  # https://en.wikipedia.org/wiki/Time-of-check_to_time-of-use
  (when (and (zero? euid) (not (zero? uid)))
    (unless (empty? *store-path*)
      (error "non root user using setuid pkgstore to access non multi-user store")))

  (def cfg-path (string *store-path* "/etc/hermes/cfg.jdn"))
  (def cfg-stat (os/lstat cfg-path))
  
  (unless cfg-stat
    (error "unable to open package store"))
 
  (set *store-config* (jdn/decode (slurp cfg-path)))

  (case (*store-config* :mode)
    :single-user
      (do
        (when (empty? *store-path*)
          (error "single-user stores cannot be rooted at /"))
        (unless (= (cfg-stat :uid) uid)
          (error "package store is not owned by current user")))
    :multi-user
      (do
        (unless (empty? *store-path*)
          (error "multi-user stores can only be rooted at /"))
        (unless (cfg-stat :uid)
          (error "multi-user store must be root owned"))
        (unless (= euid 0)
          (error "euid must be root when opening a multi-user store")))
    (error "store has bad :mode value in package store config.")))

(defn init-store
  [mode path]

  (defn ensure-dir-exists
    [d]
    (unless (os/stat d)
      (os/mkdir d)))

  (with [old-umask (os/umask 8r077) os/umask]

    (when (= mode :single-user)
      (ensure-dir-exists path))
    (ensure-dir-exists (string path "/etc"))
    (ensure-dir-exists (string path "/etc/hermes"))
    (ensure-dir-exists (string path "/var"))
    (ensure-dir-exists (string path "/var/hermes"))
    (ensure-dir-exists (string path "/var/hermes/lock"))
    (ensure-dir-exists (string path "/hpkg"))
    (os/chmod (string path "/hpkg") 8r755)

    (spit (string path "/var/hermes/lock/gc.lock") "")

    (case mode
      :single-user
        (do
          # Only the user can look in his respository
          (os/chmod path 8r700)
          # If we mount /hpkg in a user container, then
          # we must ensure that sandbox user has access.
          (os/chmod (string path "/hpkg") 8r755)
          (def cfg
            (string
              "{\n"
              "  :mode :single-user\n"
              "}\n"))
          (spit (string path "/etc/hermes/cfg.jdn") cfg))
      :multi-user
        (do
          (os/chmod (string path "/hpkg") 8r755)

          (def euid (_hermes/geteuid))
          (unless (zero? euid)
            (error "multi-user store initialization must be done as root"))

          (defn fmt-string-list [l]
            (string/join (map |(string/format "%j" $) l) "\n    "))

          (def cfg
            (string
              "{\n"
              "  :mode :multi-user"
              "  :sandbox-build-users [\n"
              "    " (map |(string "hermes_build_user" $) (range 9)) "\n"
              "  ]\n"
              "  :authorized-groups [\n"
              "    \"hermes_users\"\n"
              "  ]\n"
              "}\n"))

          (spit (string path "/etc/hermes/cfg.jdn") cfg))
      (error (string/format "unsupported store mode %j" mode)))

    (with [db (sqlite3/open (string path "/var/hermes/hermes.db"))]
      (sqlite3/eval db "begin transaction;")
      (when (empty? (sqlite3/eval db "select name from sqlite_master where type='table' and name='Meta'"))
        (sqlite3/eval db "create table Roots(LinkPath text primary key);")
        (sqlite3/eval db "create table Pkgs(Hash text primary key, Name text);")
        (sqlite3/eval db "create table Meta(Key text primary key, Value text);")
        (sqlite3/eval db "insert into Meta(Key, Value) Values('StoreVersion', 1);")
        (sqlite3/eval db "commit;"))))

  nil)

(defn path-to-pkg-parts
  [path]
  (def tail-peg (comptime (peg/compile ~{
    :hash (capture (repeat 40 (choice (range "09") (range "af"))))
    :name (choice (sequence "-" (capture (some (sequence (not "/") 1))))
                  (constant nil))
    :main (sequence "/hpkg/" :hash :name)
  })))
  (when (string/has-prefix? *store-path* path)
    (def tail (string/slice path (length *store-path*)))
    (peg/match tail-peg tail)))

(defn- pkg-dir-name-from-parts [hash name]
  (if name
    (string hash "-" name)
    (string hash)))

(defn- build-lock-cleanup
  []
  (def all-locks (os/dir (string *store-path* "/var/hermes/lock")))
  (def pkg-locks (filter |(not= $ "gc.lock") all-locks))
  (each l pkg-locks
    (os/rm (string *store-path* "/var/hermes/lock/" l))))

(defn- optimistic-build-lock-cleanup
  []
  (when-let [gc-lock (flock/acquire (string *store-path* "/var/hermes/lock/gc.lock") :noblock :exclusive)]
    (build-lock-cleanup)
    (:close gc-lock)))

(defn has-pkg-with-hash
  [db hash]
  (not (empty? (sqlite3/eval db "select 1 from Pkgs where Hash=:hash" {:hash hash}))))

(defn gc
  []
  (with [flock (flock/acquire (string *store-path* "/var/hermes/lock/gc.lock") :block :exclusive)]
  (with [db (sqlite3/open (string *store-path* "/var/hermes/hermes.db"))]

    (def work-q @[])
    (def visited @{})

    (defn process-roots
      []
      (def dead-roots @[])
      (def roots (map |($ :LinkPath) (sqlite3/eval db "select * from Roots;")))
      (each root roots
        (if-let [rstat (os/lstat root)
                 is-link (= :link (rstat :mode))
                 [hash name] (path-to-pkg-parts (os/readlink root))
                 have-pkg (has-pkg-with-hash db hash)]
          (array/push work-q (string *store-path* "/hpkg/" (pkg-dir-name-from-parts hash name)))
          (array/push dead-roots root)))
      (sqlite3/eval db "begin transaction;")
      (each root dead-roots
        (sqlite3/eval db "delete from Roots where LinkPath = :root;" {:root root}))
      (sqlite3/eval db "commit;"))

    (defn gc-walk []
      (unless (empty? work-q)
        (def pkg-dir (array/pop work-q))
        (if (visited pkg-dir)
          (gc-walk)
          (do
            (put visited pkg-dir true)
            (def pkg-info (jdn/decode (slurp (string pkg-dir "/.hpkg.jdn"))))
            (def ref-to-full-path |(string *store-path* "/hpkg/" $))
            (array/concat work-q
              (map ref-to-full-path
                (if (pkg-info :force-refs)
                  (pkg-info :force-refs)
                  (let [refs (array/concat @[]
                               (get pkg-info :scanned-refs [])
                               (get pkg-info :extra-refs []))]
                    (if-let [weak-refs (pkg-info :weak-refs)]
                      (filter |(get weak-refs $) refs)
                      refs)))))
            (gc-walk)))))
    
    (process-roots)
    (gc-walk)

    (each dirname (os/dir (string *store-path* "/hpkg/"))
      (def pkg-dir (string *store-path* "/hpkg/" dirname))
      (unless (visited pkg-dir)
        (when-let [[hash name] (path-to-pkg-parts pkg-dir)]
          (sqlite3/eval db "delete from Pkgs where Hash = :hash;" {:hash hash}))
        (eprintf "deleting %s" pkg-dir)
        (sh/$ ["chmod" "-R" "u+w" pkg-dir])
        (sh/$ ["rm" "-rf" pkg-dir])))

    (build-lock-cleanup)

    nil)))

(defn check-pkg-content
  [base-path content]

  (defn- bad-content
    [msg]
    (return :check-content [:fail msg]))

  (defn- check-hash
    [path expected is-dir]
    (def actual
      (match (string/split ":" expected)
        ["sha256" _]
          (string
            "sha256:"
            (if is-dir
              (_hermes/sha256-dir-hash path)
              (_hermes/sha256-file-hash path)))
        _ 
          (bad-content (string "unsupported hash format - " expected))))
      (unless (= expected actual)
        (bad-content (string "expected " path " to have hash " expected " but got " actual))))

  (defn- unify-dir-content
    [dir-path content &opt st]
    (default st (os/lstat dir-path))
    (unless st
      (bad-content (string "expected content at " dir-path)))
    (unless (struct? content)
      (bad-content (string "expected a directory descriptor struct at " dir-path)))
    (unless (= (st :mode) :directory)
      (bad-content (string "expected a directory at " dir-path)))
    (def ents (os/dir dir-path))
    (unless (= (length ents) (length content))
      (bad-content (string (length ents) " directory entries, expected " (length content) " at " dir-path)))
    (each ent-name ents
      (def ent-path (string dir-path "/" ent-name))
      (def ent-st (os/stat ent-path))
      (def expected-mode (get (content ent-name) :mode :file))
      (def expected-perms (get (content ent-name) :permissions "r--r--r--"))
      (unless (= (ent-st :mode) expected-mode)
        (bad-content (string "expected " expected-mode " at " ent-path)))
      (unless (= (ent-st :permissions) expected-perms)
        (bad-content (string "expected perms " expected-perms " at " ent-path ", got " (ent-st :permissions))))
      (def subcontent (get (content ent-name) :content))
      (case (ent-st :mode)
        :directory
          (if (string? subcontent)
            (check-hash ent-path subcontent true)
            (unify-dir-content ent-path subcontent))
        :link
          (unless (= subcontent (os/readlink ent-path))
            (bad-content (string "link at " ent-path " expected to point to " subcontent)))
        :file
          (do
            (unless (string? subcontent)
              (bad-content (string "content at " ent-path " must be a hash, got: " subcontent)))
            (check-hash ent-path subcontent false))
        (bad-content (string "unexpected mode " (ent-st :mode) " at " ent-path)))))
  
  (prompt :check-content 
    (cond
      (string? content)
        (check-hash base-path content true)
      (struct? content)
        (unify-dir-content base-path content)
      (error (string/format "package content must be a hash or directory description struct")))
    :ok))

(defn compute-build-dep-info
  [pkg]
  (def deps @{})
  (def order @[])
  (defn compute-build-dep-info2
    [pkg]
    (if (deps pkg)
      nil
      (let [direct-deps (_hermes/pkg-dependencies pkg)]
        (put deps pkg (keys direct-deps))
        (eachk dep direct-deps
          (compute-build-dep-info2 dep))
        (array/push order pkg))))
  (compute-build-dep-info2 pkg)
  {:deps deps
   :order order})

(defn ref-scan
  [db pkg]
  # Because package names are not fixed length, the scanner can only scan for hashes. 
  # We must reconstruct the full package path by fetching from the database.
  (def hash-set (_hermes/hash-scan *store-path* pkg @{}))
  (def refs @[])
  (def hashes (keys hash-set))
  (sort hashes)
  (each h hashes
    (when-let [row (first (sqlite3/eval db "select Name from Pkgs where Hash = :hash;" {:hash h}))]
      (array/push refs (pkg-dir-name-from-parts h (row :Name)))))
  refs)

(var- aquire-build-user-counter 0)
(defn aquire-build-user
  []
  (defn select-and-lock-build-user
    [users idx]
    (if (= idx (length users))
      (do
        # XXX exp backoff?
        (os/sleep 0.5)
        (select-and-lock-build-user users 0))
      (let [u (users idx)]
        (if-let [user-lock (flock/acquire (string *store-path* "/var/hermes/lock/user-" u ".lock") :noblock :exclusive)]
          (merge-into (_hermes/getpwnam u)
                      @{:lock user-lock :close (fn [self] (:close (self :lock)))})
          (select-and-lock-build-user users (inc idx))))))
  
  (if (= (*store-config* :mode) :multi-user)
    (let [users (get *store-config* :sandbox-build-users [])
          start-idx (mod (++ aquire-build-user-counter) (length users))]
      (select-and-lock-build-user users start-idx))
    (merge-into (_hermes/getpwuid (_hermes/getuid))
                @{:close (fn [self] nil)})))

(defn build
  [pkg &opt gc-root]

  (def dep-info (compute-build-dep-info pkg))

  # Copy registry so we can update it as we build packages.
  (def registry (merge-into @{} builder/builder-registry))
  
  (each p (dep-info :order)
    (put registry (p :builder) '*pkg-noop-build*))

  (each p (dep-info :order)
    # Hash the packages in order as children must be hashed first.
    (_hermes/pkg-hash *store-path* builder/builder-registry p))

  (with [flock (flock/acquire (string *store-path* "/var/hermes/lock/gc.lock") :block :shared)]
  (with [db (sqlite3/open (string *store-path* "/var/hermes/hermes.db"))]
    
    (defn has-pkg
      [pkg]
      (has-pkg-with-hash db (pkg :hash)))

    (defn build2
      [pkg]
      (unless (has-pkg pkg)
        (each dep (get-in dep-info [:deps pkg])
          (unless (has-pkg dep)
            (build2 dep)))

        (with [build-user (aquire-build-user)]
        (with [flock (flock/acquire (string *store-path* "/var/hermes/lock/build-" (pkg :hash) ".lock") :block :exclusive)]
          # After aquiring the package lock, check again that it doesn't exist.
          # This is in case multiple builders were waiting.
          (when (not (has-pkg pkg))
            
            (when (os/stat (pkg :path))
              (sh/$ ["chmod" "-R" "u+w" (pkg :path)])
              (sh/$ ["rm" "-rf" (pkg :path)]))
            
            (sh/$ ["mkdir" (pkg :path)])

            (when (= (*store-config* :mode) :single-user)
              # XXX FIXME. We set the permissions to 777
              # during a single user build to ensure the 
              # sandbox user can actually write to it. 
              # When initializing the store we mark it's
              # root directory as 700 so this should
              # be secure, however it also seems like 
              # a kludge that could be fixed.
              (os/chmod (pkg :path) 8r777))

            (def tmpdir (sh/$$_ ["mktemp" "-d"]))
            (defer (do
                     (sh/$ ["chmod" "-R" "u+w" tmpdir])
                     (sh/$ ["rm" "-r" tmpdir]))
              
              (def bin (string tmpdir "/bin"))
              (def usr-bin (string tmpdir "/usr/bin"))
              (def tmp (string tmpdir "/tmp"))
              (def build (string tmpdir "/tmp/build"))
              (def hpkg-path (string *store-path* "/hpkg"))

              (sh/$ ["mkdir" "-p" build bin usr-bin])

              (defn do-build []
                (os/cd "/tmp/build")
                (with-dyns [:pkg-out (pkg :path)]
                  ((pkg :builder))))

              (def thunk-path (string tmpdir "/tmp/.pkg.thunk"))
              (put registry (pkg :builder) nil)
              (spit thunk-path (marshal do-build registry))
              (put registry (pkg :builder) '*pkg-noop-build*)

              (sh/$ [
                "nsjail"
                "-M" "o"
                "-q"
                "--chroot" "/" # XXX We should make a proper chroot?.
                "--rlimit_as" "max"
                "--rlimit_cpu" "max"
                "--rlimit_fsize" "max"
                "--rlimit_nofile" "max"
                "--rlimit_nproc" "max"
                "--rlimit_stack" "max"
                ;(if (pkg :content) ["--disable_clone_newnet"] [])
                "--bindmount" (string bin ":/bin")
                "--bindmount" (string tmp ":/tmp")
                "--bindmount" (string hpkg-path ":" hpkg-path)
                "--user" (string (build-user :uid))
                "--group" (string (build-user :gid))
                "--" (sh/$$_ ["which" "hermes-builder"]) "-t" "/tmp/.pkg.thunk"])) # XXX don't shell out.

            (def scanned-refs (ref-scan db pkg))
            
            # Set package permissions.
            (sh/$ ["chmod" "-R" "a-w,a+r,a+X" (pkg :path)])

            (when-let [content (pkg :content)]
              (match (check-pkg-content (pkg :path) content)
                [:fail msg]
                  (error msg)))

            (defn refset-to-dirnames
              [pkg set-key]
              (when-let [rs (pkg set-key)]
                (map |(pkg-dir-name-from-parts ($ :hash) ($ :name)) (pkg set-key))))

            (os/chmod (pkg :path) 8r755)

            (spit (string (pkg :path) "/.hpkg.jdn") (string/format "%j" {
              :name (pkg :name)
              :hash (pkg :hash)
              :force-refs (refset-to-dirnames pkg :force-refs)
              :weak-refs  (refset-to-dirnames pkg :weak-refs)
              :extra-refs (refset-to-dirnames pkg :extra-refs)
              :scanned-refs scanned-refs
              :content (pkg :content)
            }))

            (os/chmod (pkg :path) 8r555)

            (sqlite3/eval db "insert into Pkgs(Hash, Name) Values(:hash, :name);"
              {:hash (pkg :hash) :name (pkg :name)}))))

          nil))

    (build2 pkg)

    (when gc-root
      (with [old-euid (_hermes/geteuid) _hermes/seteuid]
        (sqlite3/eval db "insert or ignore into Roots(LinkPath) Values(:root);" {:root gc-root})
        (def tmplink (string gc-root ".hermes-root"))
        (when (os/stat tmplink)
          (os/rm tmplink))
        (os/link (pkg :path) tmplink true)
        (os/rename tmplink gc-root)))))
    
    (optimistic-build-lock-cleanup)
    
    nil)
