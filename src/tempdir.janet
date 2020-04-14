(import process)

(defn tempdir
  [&opt ssh-host ssh-config]
  (def [r1 w1] (process/pipe))
  (def [r2 w2] (process/pipe))
  (def cmd
    (if ssh-host
      @["ssh" ssh-host ;(if ssh-config ["-F" ssh-config] []) "--" "hermes-tempdir"]
      @["hermes-tempdir"]))
  (def proc (process/spawn cmd :redirects [[stdin r1] [stdout w2] [stderr :null]]))
  (file/close r1)
  (file/close w2)
  (def tmpdir (-?>> (file/read r2 :line) string/trimr))
  (file/close r2)
  (when (or (proc :exit-code) (nil? tmpdir))
    (error "hermes-tempdir failed"))
  @{:path tmpdir :close (fn [&] (file/close w1) (:close proc) (process/wait proc))})
 
