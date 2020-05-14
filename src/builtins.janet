(import sh)
(import path)
(import uri)
(import ./hash)
(import ./download)
(import ./fetch)
(import ./walkpkgstore)
(import ../build/_hermes)

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

(defn- unpack
  [archive &opt &keys {
    :dest dest
    :unwrap unwrap
  }]
  (default dest "./")
  (default unwrap true)
  (def archive (path/abspath archive))
  (eprintf "unpacking %s to %s..." archive dest)
  (unless (os/stat dest)
    (os/mkdir dest))
  (def start-dir (os/cwd))
  (defer (os/cd start-dir)
    (os/cd dest)
    (_hermes/primitive-unpack archive)
    (when unwrap
      (def ents (os/dir "./"))
      (when (and
              (= (length ents) 1)
              (= :directory ((os/stat (string "./" (first ents))) :mode)))
        (def d (first ents))
        (os/rename d ".hermes.unpack.tmp")
        (each child (os/dir ".hermes.unpack.tmp")
          (os/rename (string "./.hermes.unpack.tmp/" child) child))
        (os/rmdir ".hermes.unpack.tmp"))))
  nil)

(def *content-map* @{})

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
        (fetch/fetch* hash (string (dyn :pkg-out) "/" file-name)))))

(defn local-file*
  [path relative-to &opt hash]
  (def path
    (cond
      (string? path)
        path
      (symbol? path)
        (string path)
      (error "path must be a string or symbol")))
  
  (when (path/abspath? path)
    (error "path must be a relative path"))

  (if-let [parsed-url (uri/parse relative-to)
           url-scheme (parsed-url :scheme)
           url-host (parsed-url :host)
           url-path (parsed-url :path)]
      (do 
        (def url (string url-scheme "://" url-host (path/join url-path path)))
        (default hash 
          (with [tmpf (file/temp)]
            (match (download/download url |(file/write tmpf $))
              :ok
                (file/seek tmpf :set 0)
              [:fail err-msg]
                (error err-msg))
            (hash/hash "sha256" tmpf)))
        (fetch :url url :hash hash))
    (do
      (def path (path/join relative-to path))
      (default hash (hash/hash "sha256" path))
      (fetch :url (string "file://" path) :hash hash))))

(defmacro local-file
  [path &opt hash]

  (def source (or (dyn :hermes-current-url)
                  (path/abspath (or (dyn :current-file)
                                    (path/join (os/cwd) "-")))))
  # XXX Lucky for us this works on urls, obviously this isn't gonna work on windows.
  (def basename (path/basename source))
  (def dir (string/slice source 0 (- -2 (length basename))))   # XXX upstream path/dir.
  ~(,local-file* ,path ,dir ,hash))

(def hermes-env (merge-into @{} root-env))
(put hermes-env 'pkg @{:value pkg})
(put hermes-env 'walk-pkgs @{:value walkpkgstore/walk-pkgs})
(put hermes-env 'add-mirror @{:value add-mirror})
(put hermes-env 'fetch  @{:value fetch})
(put hermes-env 'fetch* @{:value fetch/fetch*})
(put hermes-env 'local-file  @{:value local-file :macro true})
(put hermes-env 'local-file* @{:value local-file*})
(put hermes-env 'unpack @{:value unpack})
(put hermes-env 'sh/run* @{:value sh/run*})
(put hermes-env 'sh/$*   @{:value sh/$*})
(put hermes-env 'sh/$<*  @{:value sh/$<*})
(put hermes-env 'sh/$<_* @{:value sh/$<_*})
(put hermes-env 'sh/$?*  @{:value sh/$?*})
(put hermes-env 'sh/run @{:value sh/run :macro true})
(put hermes-env 'sh/$   @{:value sh/$ :macro true})
(put hermes-env 'sh/$<  @{:value sh/$< :macro true})
(put hermes-env 'sh/$<_ @{:value sh/$<_ :macro true})
(put hermes-env 'sh/$?  @{:value sh/$? :macro true})
(put hermes-env 'sh/glob  @{:value sh/glob})
(put hermes-env '*pkg-noop-build* @{:value (fn [&] nil)})
(put hermes-env '*circular-reference* @{:value '*circular-reference*})
(put hermes-env '_hermes/setuid @{:value _hermes/setuid})
(put hermes-env '_hermes/setgid @{:value _hermes/setgid})
(put hermes-env '_hermes/seteuid @{:value _hermes/seteuid})
(put hermes-env '_hermes/setegid @{:value _hermes/setegid})
(put hermes-env '_hermes/cleargroups @{:value _hermes/cleargroups})
(put hermes-env '_hermes/chroot @{:value _hermes/chroot})
(put hermes-env '_hermes/mount @{:value _hermes/mount})
(def load-registry (env-lookup hermes-env))
(def registry (invert load-registry))
