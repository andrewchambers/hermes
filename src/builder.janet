(import sh)
(import path)
(import ./fetch)
(import ../build/_hermes)

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

(def builder-env (make-env root-env))
(put builder-env 'pkg
  @{:value (fn [&] (error "pkg cannot be invoked inside a builder"))})
(put builder-env 'fetch*  @{:value fetch/fetch*})
(put builder-env 'unpack @{:value unpack})
(put builder-env 'sh/$   @{:value sh/$})
(put builder-env 'sh/$$  @{:value sh/$$})
(put builder-env 'sh/$$_ @{:value sh/$$_})
(put builder-env 'sh/$?  @{:value sh/$?})
(put builder-env 'sh/glob  @{:value sh/glob})
(put builder-env '*pkg-noop-build* (fn [&] nil))
(def builder-load-registry (env-lookup builder-env))
(def builder-registry (invert builder-load-registry))
