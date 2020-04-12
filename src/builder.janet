(import sh)
(import ./fetch)

(defn- unpack
  [path &opt &keys {
    :dest dest
    :strip nstrip
  }]
  (default dest "./")
  (default nstrip 0)
  (unless (os/stat dest)
    (os/mkdir dest))
  (def tar-bin (comptime (sh/$$_ ["which" "tar"])))
  (sh/$ [tar-bin (string "--strip-components=" nstrip) "-avxf" path "-C" dest]))

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
