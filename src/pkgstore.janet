(import posix-spawn)
(import sh)
(import sqlite3)
(import path)
(import flock)
(import jdn)
(import base16)
(import ./tempdir)
(import ./hash)
(import ./protocol)
(import ./builtins)
(import ../build/_hermes :as _hermes)

(var- *store-path* nil)
(var- *store-config* nil)
(var- *store-owner-uid* nil)
(var- *store-owner-gid* nil)

(defn open-pkg-store
  [store-path]

  (set *store-path* (if (= store-path "")
                      ""
                      (let [abs (path/abspath store-path)]
                        (if (= abs "/") "" abs))))
  
  (def uid (_hermes/getuid))
  (def gid (_hermes/getgid))
  (def euid (_hermes/geteuid))
  (def egid (_hermes/getegid))
  
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
    (error (string/format "unable to open package store, %j missing" cfg-path)))
 
  (set *store-config* (jdn/decode (slurp cfg-path)))
  (set *store-owner-uid* (cfg-stat :uid))
  (set *store-owner-gid* (cfg-stat :gid))

  (case (*store-config* :mode)
    :single-user
      (do
        (when (empty? *store-path*)
          (error "single-user stores cannot be rooted at /"))
        (unless (= *store-owner-uid* uid)
          (error "package store is not owned by current user"))
        (unless (= *store-owner-gid* gid)
          (error "package store group differs from current user")))
    :multi-user
      (do
        (unless (empty? *store-path*)
          (error "multi-user stores can only be rooted at /"))
        (unless (and (= *store-owner-uid* 0) (= *store-owner-gid* 0))
          (error "multi-user store must be root owned"))
        (unless (= euid 0)
          (error "euid must be root when opening a multi-user store"))
        (unless (= egid 0)
          (error "egid must be root when opening a multi-user store"))
        
        (let [user-name ((_hermes/getpwuid uid) :name)
              authorized-group-info (_hermes/getgrnam (get *store-config* :authorized-group "root"))]
          (unless (or (= "root" user-name)
                      (find  |(= $ user-name) (authorized-group-info :members)))
            (error 
              (string/format "current user %v not in the authorized group %v (see %v)"
                user-name
                (authorized-group-info :name)
                cfg-path)))))
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
    (ensure-dir-exists (string path "/etc/hermes/trusted-pub-keys"))
    (ensure-dir-exists (string path "/var"))
    (ensure-dir-exists (string path "/var/hermes"))
    (ensure-dir-exists (string path "/var/hermes/lock"))
    (ensure-dir-exists (string path "/hpkg"))
    (os/chmod (string path "/hpkg") 8r755)

    (unless (os/lstat (string path "/etc/hermes/signing-key.sec"))
      (def store-id (base16/encode (os/cryptorand 16)))
      (def secret-key-path (string path "/etc/hermes/signing-key-" store-id ".sec"))
      (def public-key-path (string path "/etc/hermes/signing-key-" store-id ".pub"))
      (sh/$ hermes-signify -G -n
               -c "Hermes package store key" 
               -s ,secret-key-path
               -p ,public-key-path)
      (os/symlink 
         (string "./signing-key-" store-id ".sec")
         (string path "/etc/hermes/signing-key.sec"))
      (os/symlink 
         (string "./signing-key-" store-id ".pub")
         (string path "/etc/hermes/signing-key.pub")))

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
              "  :mode :multi-user\n"
              "  :authorized-group \"wheel\"\n"
              "  :sandbox-build-users [\n"
              "    " (string/join (map |(string/format "%j" (string "hermes_build_user" $)) (range 9)) "\n    ") "\n"
              "  ]\n"
              "}\n"))

          (spit (string path "/etc/hermes/cfg.jdn") cfg))
      (error (string/format "unsupported store mode %j" mode)))

    (with [db (sqlite3/open (string path "/var/hermes/hermes.db"))]
      (sqlite3/eval db "begin transaction;")
      (when (empty? (sqlite3/eval db "select name from sqlite_master where type='table' and name='Meta'"))
        (sqlite3/eval db "create table Roots(LinkPath text primary key);")
        (sqlite3/eval db "create table Pkgs(Hash text primary key, Name text, TTLExpires integer);")
        (sqlite3/eval db "create table Meta(Key text primary key, Value text);")
        (sqlite3/eval db "insert into Meta(Key, Value) Values('StoreVersion', 1);")
        (sqlite3/eval db "commit;"))))

  nil)

(defn- path-to-pkg-parts
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

(defn- pkg-path-from-parts [hash name]
  (string *store-path* "/hpkg/" (pkg-dir-name-from-parts hash name)))

(defn- pkg-parts-from-dir-name
  [dir-name]
  (if-let [idx (string/find "-" dir-name)]
    [(string/slice dir-name 0 idx) (string/slice dir-name (inc idx))]
    [dir-name nil]))

(defn open-db
  []
  (sqlite3/open (string *store-path* "/var/hermes/hermes.db")))

(defn- acquire-gc-lock
  [block mode]
  (flock/acquire (string *store-path* "/var/hermes/lock/gc.lock") block mode))

(defn- acquire-build-lock
  [hash block mode]
  (flock/acquire (string *store-path* "/var/hermes/lock/build-" hash ".lock") block mode))

(defn- build-lock-cleanup
  []
  (def all-locks (os/dir (string *store-path* "/var/hermes/lock")))
  (def pkg-locks (filter |(not= $ "gc.lock") all-locks))
  (each l pkg-locks
    (os/rm (string *store-path* "/var/hermes/lock/" l))))

(defn- optimistic-build-lock-cleanup
  []
  (when-let [gc-lock (acquire-gc-lock :noblock :exclusive)]
    (build-lock-cleanup)
    (:close gc-lock)))

(defn- has-pkg-with-hash
  [db hash]
  (not (empty? (sqlite3/eval db "select 1 from Pkgs where Hash=:hash" {:hash hash}))))

(defn- has-pkg-with-dirname
  [db dir-name]
  (def hash (first (pkg-parts-from-dir-name dir-name)))
  (has-pkg-with-hash db hash))

(defn walk-store-closure
  [roots &opt f]

  (def ref-work-q @[])
  (def visited @{})

  (defn- enqueue
    [ref]
    (unless (in visited ref)
      (put visited ref true)
      (array/push ref-work-q ref)))

  (var hpkg-path nil)

  (each root roots 
    (def abs-path (os/realpath root))
    (def pkg-ref (path/basename abs-path))
    (def root-hpkg-path (string/slice abs-path 0 (- -2 (length pkg-ref))))
    (if-not hpkg-path
      (set hpkg-path root-hpkg-path)
      (unless (= root-hpkg-path hpkg-path)
        (error "unable to walk closure roots from different package stores")))
    (enqueue (path/basename abs-path)))
  
  (if (nil? hpkg-path)
    (assert (empty? ref-work-q))
    (unless (string/has-suffix? "/hpkg" hpkg-path)
      (error "unable to walk closure outside of $STORE/hpkg")))

  (defn -walk-store-closure []
    (unless (empty? ref-work-q)
      (def ref (array/pop ref-work-q))
      (def pkg-path (string hpkg-path "/" ref))
      (def pkg-info (jdn/decode (slurp (string pkg-path "/.hpkg.jdn"))))
      (def new-refs
        (if-let [forced-refs (pkg-info :force-refs)]
          forced-refs
          (let [unfiltered-refs (array/concat @[]
                                  (pkg-info :scanned-refs)
                                  (get pkg-info :extra-refs []))]
            (if-let [weak-refs (pkg-info :weak-refs)]
              (do
                (def weak-refs-lut (reduce |(put $0 $1 true) @{} weak-refs))
                (filter weak-refs-lut unfiltered-refs))
              unfiltered-refs))))
        (when f
          (f pkg-path pkg-info new-refs))
      (each ref new-refs
        (enqueue ref))
      (-walk-store-closure)))
  (-walk-store-closure)
  visited)

(defn gc
  [&keys {
    :ignore-ttl ignore-ttl
  }]
  (assert *store-config*)
  (with [gc-lock (acquire-gc-lock :block :exclusive)]
  (with [db (open-db)]

    (def root-pkg-paths @[])

    (defn process-ttl-roots
      []
      (each row (sqlite3/eval db
                   "select * from Pkgs where TTLExpires is not null and TTLExpires > :now;"
                   {:now (os/time)})
        (array/push root-pkg-paths (pkg-path-from-parts (row :Hash) (row :Name)))))

    (defn process-roots
      []
      (def dead-roots @[])
      (def roots (map |($ :LinkPath) (sqlite3/eval db "select * from Roots;")))
      (each root roots
        (if-let [rstat (os/lstat root)
                 is-link (= :link (rstat :mode))
                 pkg-path (os/readlink root)
                 [hash name] (path-to-pkg-parts pkg-path)
                 have-pkg (has-pkg-with-hash db hash)]
          (array/push root-pkg-paths pkg-path)
          (array/push dead-roots root)))
      (sqlite3/eval db "begin transaction;")
      (each root dead-roots
        (sqlite3/eval db "delete from Roots where LinkPath = :root;" {:root root}))
      (sqlite3/eval db "commit;"))
    
    (unless ignore-ttl
      (process-ttl-roots))
    (process-roots)
    (def visited (walk-store-closure root-pkg-paths))

    (each dirname (os/dir (string *store-path* "/hpkg/"))
      (def pkg-dir (string *store-path* "/hpkg/" dirname))
      (def dir-name (path/basename pkg-dir))
      (unless (visited dir-name)
        (when-let [[hash name] (path-to-pkg-parts pkg-dir)]
          (sqlite3/eval db "delete from Pkgs where Hash = :hash;" {:hash hash}))
        (eprintf "deleting %s" pkg-dir)
        (_hermes/nuke-path pkg-dir)))

    (build-lock-cleanup)

    nil)))

(defn- assert-pkg-content
  [base-path content]

  (defn- unify-dir-content
    [dir-path content &opt st]
    (default st (os/lstat dir-path))
    (unless st
      (error (string "expected content at " dir-path)))
    (unless (struct? content)
      (error (string "expected a directory descriptor struct at " dir-path)))
    (unless (= (st :mode) :directory)
      (error (string "expected a directory at " dir-path)))
    (def ents (os/dir dir-path))
    (unless (= (length ents) (length content))
      (error (string (length ents) " directory entries, expected " (length content) " at " dir-path)))
    (each ent-name ents
      (def ent-path (string dir-path "/" ent-name))
      (def ent-st (os/stat ent-path))
      (def expected-mode (get (content ent-name) :mode :file))
      (def expected-perms (get (content ent-name) :permissions "r--r--r--"))
      (unless (= (ent-st :mode) expected-mode)
        (error (string "expected " expected-mode " at " ent-path)))
      (unless (= (ent-st :permissions) expected-perms)
        (error (string "expected perms " expected-perms " at " ent-path ", got " (ent-st :permissions))))
      (def subcontent (get (content ent-name) :content))
      (case (ent-st :mode)
        :directory
          (if (string? subcontent)
            (hash/assert ent-path subcontent)
            (unify-dir-content ent-path subcontent))
        :link
          (unless (= subcontent (os/readlink ent-path))
            (error (string "link at " ent-path " expected to point to " subcontent)))
        :file
          (do
            (unless (string? subcontent)
              (error (string "content at " ent-path " must be a hash, got: " subcontent)))
            (hash/assert ent-path subcontent))
        (error (string "unexpected mode " (ent-st :mode) " at " ent-path)))))
  
    (cond
      (string? content)
        (hash/assert base-path content)
      (struct? content)
        (unify-dir-content base-path content)
      (error (string/format "package content must be a hash or directory description struct")))
    nil)

(defn compute-build-dep-info
  [pkg]
  (def deps @{})
  (def all-pkgs @{pkg true})
  (def order @[])
  (defn compute-build-dep-info2
    [pkg]
    (if (deps pkg)
      nil
      (let [pkg-seq-num (pkg :sequence-number)
            direct-deps (keys (_hermes/pkg-dependencies pkg))
            filtered-deps (filter |(< ($ :sequence-number) pkg-seq-num ) direct-deps)]
        (each d direct-deps
          (put all-pkgs d true))
        (put deps pkg filtered-deps)
        (each dep filtered-deps
          (compute-build-dep-info2 dep))
        (array/push order pkg))))
  (compute-build-dep-info2 pkg)
  {:deps deps
   :order order
   :all-pkgs (keys all-pkgs)})

(defn- ref-scan
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

(var- acquire-build-user-counter 0)
(defn- acquire-build-user
  []
  (defn select-and-lock-build-user
    [users idx]
    (if (= idx (length users))
      (do
        # XXX exp backoff?
        (eprintf "waiting for a free build user...")
        (os/sleep 0.5)
        (select-and-lock-build-user users 0))
      (let [u (users idx)]
        (if-let [user-lock (flock/acquire (string *store-path* "/var/hermes/lock/user-" u ".lock") :noblock :exclusive)]
          (merge-into (_hermes/getpwnam u)
                      @{:lock user-lock :close (fn [self] (:close (self :lock)))})
          (select-and-lock-build-user users (inc idx))))))
  
  (if (= (*store-config* :mode) :multi-user)
    (let [users (get *store-config* :sandbox-build-users [])
          start-idx (mod (++ acquire-build-user-counter) (length users))]
      (select-and-lock-build-user users start-idx))
    (merge-into (_hermes/getpwuid (_hermes/getuid))
                @{:close (fn [self] nil)})))

(defn add-root
  [db pkg-path root]
  (def root (path/abspath root))
  (with [old-euid (_hermes/geteuid) _hermes/seteuid]
    (sqlite3/eval db "insert or ignore into Roots(LinkPath) Values(:root);" {:root root})
    (def tmplink (string root ".hermes-root"))
    (when (os/stat tmplink)
      (os/rm tmplink))
    (os/link pkg-path tmplink true)
    (os/rename tmplink root)))

(defn build
  [&keys {
     :pkg pkg
     :fetch-socket-path fetch-socket-path
     :gc-root gc-root
     :parallelism parallelism
     :ttl ttl
   }]
  (assert *store-config*)

  (def store-mode (*store-config* :mode))

  (def dep-info (compute-build-dep-info pkg))

  # Copy registry so we can update it as we build packages.
  (def registry (merge-into @{} builtins/registry))
  
  (each p (dep-info :all-pkgs)
    # Initially all reachable packages are marked
    # so that marshalling efficiently ignores them
    # when we don't need them. 
    #
    # As we perform builds in topological build order,
    # We can remove the circular reference tag, and
    # during each build, we allow marshalling of the
    # one builder we are actually calling.
    (put registry p '*circular-reference*)
    (put registry (p :builder) '*pkg-noop-build*))

  (each p (dep-info :order)
    # Freeze the packages in order as children must be frozen first.
    (_hermes/pkg-freeze *store-path* builtins/registry p))

  (with [gc-flock (acquire-gc-lock :block :shared)]
  (with [build-user (acquire-build-user)]
  (with [db (open-db)]

    (var run-builder nil)

    (defn build-pkg
      [pkg]
      (def pkg-ready
        (if (has-pkg-with-hash db (pkg :hash))
            true
          (do
            (var deps-ready true)
            (each dep (get-in dep-info [:deps pkg])
              (set deps-ready (and (build-pkg dep) deps-ready)))
            
              (if-let [_ deps-ready
                       flock (acquire-build-lock (pkg :hash) :noblock :exclusive)]
                (defer (:close flock)
                  # After aquiring the package lock, check again that it doesn't exist.
                  # This is in case multiple builders were waiting, and another did the build.
                  (when (not (has-pkg-with-hash db (pkg :hash)))
                    (run-builder pkg))
                  true)
                false))))
      (when pkg-ready
        # The package should no longer marshal as a circular reference.
        # as we know all it/all of it's dependencies are on disk.
        (put registry pkg nil))
      pkg-ready)
    
    (set run-builder 
      (fn run-builder
        [pkg]
        (eprintf "building %s..." (pkg :path))
        (when (os/stat (pkg :path))
          (_hermes/nuke-path (pkg :path)))
        
        (os/mkdir (pkg :path))

        (with [tmpdir (tempdir/tempdir)]

          (def thunk-path (string (tmpdir :path) "/pkg.thunk"))
          (defn spit-do-build-thunk
            [do-build]
            (put registry (pkg :builder) nil)
            (spit thunk-path (marshal do-build registry))
            (put registry (pkg :builder) '*pkg-noop-build*))
          
          # network allowed if content specified, nothing downloaded
          # can alter the package outcome.
          (def allow-network (truthy? (pkg :content)))

          (if (= store-mode :single-user)
            (do
              (def build-dir (string (tmpdir :path) "/build"))
              (os/mkdir build-dir)
              (def fetch-socket-path
                (if allow-network
                  fetch-socket-path
                  (string (tmpdir :path) "/bad.sock")))
              # No sandbox at all for single user mode.
              # It's faster, easier to test, more lightweight.
              (def do-build 
                # wrapper to minimize closure over capturing.
                (do
                  (defn make-builder [pkg-path pkg-builder build-dir fetch-socket-path parallelism]
                    (fn do-build []
                      (os/cd build-dir)
                      (eachk k (os/environ)
                        (os/setenv k nil))
                      (with-dyns [:pkg-out pkg-path
                                  :parallelism parallelism
                                  :fetch-socket fetch-socket-path]
                        (pkg-builder))))
                  (make-builder (pkg :path) (pkg :builder) build-dir fetch-socket-path parallelism)))
              (spit-do-build-thunk do-build)
              (unless (sh/$? hermes-builder -t ,thunk-path)
                (error "builder failed")))
            (do
              # chrooted sandbox build for multi user store.
              (def hpkg (string *store-path* "/hpkg"))
              (def chroot (string (tmpdir :path) "/chroot"))
              (def chroot-hpkg (string chroot hpkg))
              (def chroot-tmp (string chroot "/tmp"))
              (def chroot-fetch-socket (string chroot "/tmp/fetch.sock"))
              (def chroot-usr (string chroot "/usr/"))
              (def chroot-usr-bin (string chroot "/usr/bin"))
              (def chroot-bin (string chroot "/bin"))
              (def chroot-etc (string chroot "/etc"))
              (def chroot-var (string chroot "/var"))
              (def chroot-proc (string chroot "/proc"))
              (def chroot-dev (string chroot "/dev"))
              (def chroot-build (string chroot "/build"))
              (def chroot-paths [
                chroot chroot-hpkg chroot-usr chroot-usr-bin chroot-bin
                chroot-etc chroot-var chroot-build chroot-tmp chroot-proc
                chroot-dev
              ])

              (each p chroot-paths
                (os/mkdir p))

              (spit chroot-fetch-socket "")
              (spit (string chroot "/etc/passwd")
                (string 
                   "root:x:0:0:root:/:/bin/sh\n"
                   "builder:x:" (build-user :uid) ":" (build-user :gid) ":builder:/build:/bin/sh\n"))
              (spit (string chroot "/etc/group")
                (string  "builder:x:" (build-user :gid) ":"))

              # Paths that need to be owned by the build user for various reasons.
              (each d [(pkg :path) chroot-bin chroot-usr-bin chroot-build chroot-tmp]
                (_hermes/chown d (build-user :uid) (build-user :gid)))

              (def do-build 
                # wrapper to minimize closure over capturing.
                (do
                  (defn make-builder [chroot hpkg pkg-path pkg-builder parallelism build-uid build-gid allow-network]
                    (fn do-build []
                      (_hermes/setuid 0)
                      (_hermes/setgid 0)
                      (_hermes/cleargroups)
                      (_hermes/mount "proc" (string chroot "/proc") "proc" 0)
                      (_hermes/mount "/dev" (string chroot "/dev") "" (bor _hermes/MS_BIND _hermes/MS_REC))
                      (_hermes/mount hpkg (string chroot hpkg) "" (bor _hermes/MS_BIND _hermes/MS_RDONLY))
                      (_hermes/mount pkg-path (string chroot pkg-path) "" _hermes/MS_BIND)
                      (_hermes/mount fetch-socket-path (string chroot "/tmp/fetch.sock") "" _hermes/MS_BIND)
                      (_hermes/chroot chroot)
                      (_hermes/setegid build-gid)
                      (_hermes/setgid build-gid)
                      (_hermes/setuid build-uid)
                      (_hermes/seteuid build-uid)
                      (os/cd "/build")
                      (with-dyns [:pkg-out pkg-path
                                  :parallelism parallelism
                                  :fetch-socket "/tmp/fetch.sock"]
                        (pkg-builder))))
                  (make-builder chroot hpkg (pkg :path) (pkg :builder) parallelism (build-user :uid) (build-user :gid) allow-network)))

              (spit-do-build-thunk do-build)
              (unless (sh/$?
                         hermes-namespace-container -u -m -u -p -i
                         ;(if allow-network
                           []
                           ["-n"])
                        -- 
                        hermes-builder -t ,thunk-path)
                (error "builder failed")))))

        # Ensure files have correct owner, clear any permissions except execute.
        (_hermes/storify (pkg :path) *store-owner-uid* *store-owner-gid*)

        (def scanned-refs (ref-scan db pkg))

        (when-let [content (pkg :content)]
          (assert-pkg-content (pkg :path) content))

        (defn pkg-refset-to-dirnames
          [pkg set-key]
          (when-let [rs (pkg set-key)]
            (map |(pkg-dir-name-from-parts ($ :hash) ($ :name)) (pkg set-key))))

        (os/chmod (pkg :path) 8r755)

        (def info-path (string (pkg :path) "/.hpkg.jdn"))
        (spit info-path  (string/format "%j" {
          :name (pkg :name)
          :hash (pkg :hash)
          :force-refs (pkg-refset-to-dirnames pkg :force-refs)
          :weak-refs  (pkg-refset-to-dirnames pkg :weak-refs)
          :extra-refs (pkg-refset-to-dirnames pkg :extra-refs)
          :scanned-refs scanned-refs
          :content (pkg :content)
        }))

        (_hermes/storify info-path *store-owner-uid* *store-owner-gid*)

        (os/chmod (pkg :path) 8r555)
        (_hermes/sync)
        (sqlite3/eval db "insert into Pkgs(Hash, Name) Values(:hash, :name);"
          {:hash (pkg :hash) :name (pkg :name)})
      nil))

    (while true
      (when (build-pkg pkg)
        (break))
      # TODO exp backoffs.
      (eprintf "waiting for more work...")
      (os/sleep 0.5))

    (when ttl
      (sqlite3/eval db "Update Pkgs set TTLExpires = :expires where Hash = :hash;"
        {:hash (pkg :hash) :expires (+ (os/time) ttl)}))

    (when gc-root
      (add-root db (pkg :path) gc-root)))))

    (optimistic-build-lock-cleanup)
    
    nil)

(defn send-pkg-closure
  [out in pkg-root]

  (match (protocol/recv-msg in)
    [:challenge-trust challenge]
    (with [tempdir (tempdir/tempdir)]
      (def pub-key (os/realpath (string *store-path* "/etc/hermes/signing-key.pub")))
      (def sec-key (os/realpath (string *store-path* "/etc/hermes/signing-key.sec")))
      (def msg-path (string (tempdir :path) "/challenge"))
      (def sig-path (string (tempdir :path) "/challenge.sig"))
      (spit msg-path challenge)
      (def key-name (path/basename pub-key))
      (sh/$ hermes-signify -q -S -s ,sec-key -m ,msg-path -x ,sig-path)
      (protocol/send-msg out [:challenge-response {:key-name key-name :sig (slurp sig-path)}]))
    (error "protocol error, expected :challenge-trust"))

  (with [flock (acquire-gc-lock :block :shared)]
  (with [db (open-db)]
    
    (def pkg-path (os/realpath pkg-root))
    
    (unless (if-let [[hash name] (path-to-pkg-parts pkg-path)]
              (has-pkg-with-hash db hash))
      (error (string/format "unable to send %v, not a package" pkg-path)))

    (var refs @[])
    (walk-store-closure [pkg-root] (fn [path info _]
                                     (array/push refs (pkg-dir-name-from-parts (info :hash) (info :name)))))
    (set refs (reverse refs))

    (protocol/send-msg out [:send-closure refs])
    (match (protocol/recv-msg in)
      [:ack-closure want]
        (let [want-lut (reduce |(put $0 $1 true) @{} want)]
          (set refs (filter want-lut refs)))
      (error "protocol error, expected [:ack-closure refs]"))
    
    (each ref refs
      (protocol/send-msg out [:sending-pkg ref])
      (protocol/send-dir out (string *store-path* "/hpkg/" ref)))

    (protocol/send-msg out :end-of-send)

    (unless (= :ok (protocol/recv-msg in))
      (error "remote did not acknowledge send")))))

(defn recv-pkg-closure
  [out in gc-root &keys {:allow-untrusted allow-untrusted}]

  (when allow-untrusted
    (unless (= (_hermes/getuid) *store-owner-uid*)
      (error "only the store owner can allow untrusted recieve")))

  (def challenge (os/cryptorand 8192))
  (protocol/send-msg out [:challenge-trust challenge])

  (with [tempdir (tempdir/tempdir)]
    (match (protocol/recv-msg in)
      [:challenge-response {:key-name key-name :sig sig}]
      (unless allow-untrusted
        (when (string/find "/" key-name)
          (error "key name cannot contain '/'"))
        (def other-pub-key (string *store-path* "/etc/hermes/trusted-pub-keys/" key-name))
        (def our-pub-key (string *store-path* "/etc/hermes/" key-name))
        (def pub-key
          (cond
            (os/stat other-pub-key)
              other-pub-key
            (os/stat our-pub-key)
              our-pub-key
            (error (string "store does not trust key - " key-name))))

        (def msg-path (string (tempdir :path) "/challenge"))
        (def sig-path (string (tempdir :path) "/challenge.sig"))

        (spit msg-path challenge)
        (spit sig-path sig)

        (unless (sh/$? hermes-signify -V -x ,sig-path -m ,msg-path -p ,pub-key
                  > [stdout :null] > [stderr :null])
          (error "sender failed trust challenge, check /etc/hermes/trusted-pub-keys/*")))
      (error "protocol error, expected :challenge-response")))

  (with [flock (acquire-gc-lock :block :shared)]
  (with [db (open-db)]
    (def root-ref
      (match (protocol/recv-msg in)
        [:send-closure incoming]
          (let [want (filter |(not (has-pkg-with-dirname db $)) incoming)]
            (protocol/send-msg out [:ack-closure want])
            (last incoming))
        (error "protocol error, expected :send-closure")))
    
    (defn recv-pkgs
      []
      (match (protocol/recv-msg in)
        [:sending-pkg ref]
          (do
            (def [pkg-hash pkg-name] (pkg-parts-from-dir-name ref))
            (with [build-lock (acquire-build-lock pkg-hash :block :exclusive)]
              (def pkg-path (string *store-path* "/hpkg/" ref))
              (when (os/stat pkg-path)
                (_hermes/nuke-path pkg-path))
              (protocol/recv-dir in pkg-path)
              (_hermes/storify pkg-path *store-owner-uid* *store-owner-gid*)
              (sqlite3/eval db "insert into Pkgs(Hash, Name) Values(:hash, :name);"
                {:hash pkg-hash :name pkg-name}))
            (recv-pkgs))
        :end-of-send
          (protocol/send-msg out :ok)
        (error "protocol error, expected :end-of-send or :sending-pkg")))
    
    (recv-pkgs)

    (when gc-root
      (add-root db (string *store-path* "/hpkg/" root-ref) gc-root)))))