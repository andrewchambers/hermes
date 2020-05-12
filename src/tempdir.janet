(import posix-spawn)

(defn tempdir
  [&opt ssh-host ssh-config]
  (def cmd
    (if ssh-host
      @["ssh" ssh-host ;(if ssh-config ["-F" ssh-config] []) "--" "hermes-tempdir"]
      @["hermes-tempdir"]))

  (def [r1 w1] (posix-spawn/pipe))
  (def [r2 w2] (posix-spawn/pipe))
  (def proc 
    (posix-spawn/spawn cmd :file-actions [[:dup2 r1 stdin] [:dup2 w2 stdout]]))
  (file/close r1)
  (file/close w2)
  (def tmpdir (-?>> (file/read r2 :line) string/trimr))
  (file/close r2)
  (when (or (proc :exit-code) (nil? tmpdir))
    (error "hermes-tempdir failed"))
  @{:path tmpdir :close (fn [&] (file/close w1) (:close proc))})
 
