(import sh)
(import path)
(import ./hash)
(import ./fetch)
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

(def hermes-env (merge-into @{} root-env))
(put hermes-env 'pkg @{:value pkg})
(put hermes-env 'add-mirror @{:value add-mirror})
(put hermes-env 'fetch  @{:value fetch})
(put hermes-env 'fetch* @{:value fetch/fetch*})
(put hermes-env 'local-file  @{:value local-file :macro true})
(put hermes-env 'local-file* @{:value local-file*})
(put hermes-env 'unpack @{:value unpack})
(put hermes-env 'sh/$   @{:value sh/$})
(put hermes-env 'sh/$$  @{:value sh/$$})
(put hermes-env 'sh/$$_ @{:value sh/$$_})
(put hermes-env 'sh/$?  @{:value sh/$?})
(put hermes-env 'sh/glob  @{:value sh/glob})
(put hermes-env '*pkg-noop-build* @{:value (fn [&] nil)})
(def load-registry (env-lookup hermes-env))
(def registry (invert load-registry))
