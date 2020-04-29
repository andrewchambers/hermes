(import sh)

(def version
  (or (os/getenv "HERMES_BUILD_VERSION")
      (sh/$$_ ~[git describe  --always --dirty])))
