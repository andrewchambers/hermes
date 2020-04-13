(import process)

(defn tempdir
  [&opt ssh-host ssh-config]
  (def [r1 w1] (process/pipe))
  (def [r2 w2] (process/pipe))
  (def cmd
    (if host
      @["ssh" ssh-host ;(if ssh-config ["-F" ssh-config] []) "--" "hermes-tempdir"]
      @["hermes-tempdir"]))
  (def proc (process/spawn cmd :redirects [[stdin r1] [stdout w2]]))
  (file/close r1)
  (file/close w2)
  (def path (string (file/read r2 :line)))
  (when (proc :exit-code)
    (error "tempdir process exited unexpectedly"))
  @{:path path :close (fn [&] (file/close w) (process/wait proc))})
 