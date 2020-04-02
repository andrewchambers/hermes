(import sh)

(defn- fetch
  [url &opt dest]
  (def url
    (if (or (string/has-prefix? "." url)
            (string/has-prefix? "/" url))
      (do
        (def readlink-bin (comptime (sh/$$_ ["which" "readlink"])))
        (string "file://" (sh/$ [readlink-bin "-f" url])))
      url))
  (default dest (last (string/split "/" url)))
  (def curl-bin (comptime (sh/$$_ ["which" "curl"])))
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
  (def tar-bin (comptime (sh/$$_ ["which" "tar"])))
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
(put builder-env '*pkg-noop-build* (fn [&] nil))
(def builder-load-registry (env-lookup builder-env))
(def builder-registry (invert builder-load-registry))
