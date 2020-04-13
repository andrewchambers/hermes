(import process)
(import ./protocol)
(import ./hash)
(import ../build/_hermes)

(defn- handle-fetch-client
  [c content-map]
  
  (defn die
    [msg]
    (protocol/send-msg c [:error msg])
    (os/exit 1))

  (defn fetch-from-url
    [url hash]
    (def [pipe> pipe<] (process/pipe))
    (defer (do (:close pipe>)
               (:close pipe<))
      (with [errorf (file/temp)]
      (with [curl (process/spawn 
                    ["curl" "--silent" "--show-error" "--fail" "-L" url]
                    :redirects [[stdout pipe<] [stderr errorf]])]
        (:close pipe<)
        
        (def outf (file/temp))
        (def buf @"")

        (defn get-file-chunks []
          (file/read pipe> 131072 (buffer/clear buf))
          (if (empty? buf)
            (do
              (file/seek outf :set 0)
              nil)
            (do
              (file/write outf buf)
              (get-file-chunks))))
        (get-file-chunks)

        (if (zero? (process/wait curl))
          (match (hash/check outf hash)
            :ok
              (do
                (file/seek outf :set 0)
                outf)
            [:fail expected]
              (do
                (protocol/send-msg c
                  [:stderr (string/format "expected hash %s, mirror gave %s\n" expected hash)])
                (file/close outf)
                nil))
          (do
            (file/seek errorf :set 0)
            (def err-msg (string "fetch failed:\n" (file/read errorf :all)))
            (protocol/send-msg c [:stderr err-msg])))))))

  (defn fetch-from-mirrors
    [mirrors hash]
    (defn fetch-from-mirrors
      []
      (if (empty? mirrors)
        (die (string "no mirrors provided " hash "\n"))
        (do
          (def m (array/pop mirrors))
          (protocol/send-msg c [:stderr (string "trying mirror " m "...\n")])
          (if-let [outf (fetch-from-url m hash)]
            outf
            (fetch-from-mirrors)))))
    (fetch-from-mirrors))

  (match (protocol/recv-msg c)
    ([:fetch-content hash] (string? hash))
      (do
        (protocol/send-msg c [:stderr (string "fetching " hash "...\n")])
        (if-let [mirrors (content-map hash)
                 outf (fetch-from-mirrors mirrors hash)]
          (do
            (protocol/send-msg c :sending-content)
            (protocol/send-file c outf)
            (file/close outf))
          (die (string "no known mirrors for " hash "\n"))))
    (die "fetch protocol error")))

(defn serve
  [listener-socket content-map]
  (defn handle-connections
    []
    (def c (:accept listener-socket))
    (if-let [child (process/fork)]
      (do
        (file/close c)
        (process/wait child))
      # Double fork to prevent zombies and ensure
      # we cleanup all resources asap.
      (if-let [child (process/fork)]
        (_hermes/exit 0)
        (try
          (do
            (handle-fetch-client c content-map)
            (_hermes/exit 0))
          ([err f]
            (debug/stacktrace f err)
            (_hermes/exit 1)))))
    (handle-connections))
  (handle-connections))

(defn spawn-server
  [listener-socket content-map]
  (if-let [child (process/fork)]
    child
    (do
      (serve listener-socket content-map)
      (os/exit 0))))

(defn fetch*
  [hash dest]
  (with [destf (file/open dest :wb)]
  (with [c (_hermes/unix-connect (dyn :fetch-socket))]
    (protocol/send-msg c [:fetch-content hash])
    (while true
      (match (protocol/recv-msg c)
        [:error msg]
          (error msg)
        [:stderr ln]
          (eprin ln)
        :sending-content
          (break)
        (error "protocol error")))
    (protocol/recv-file c destf)))
  (hash/assert dest hash)
  nil)

# Repl helpers
# (def content {"sha256:XXXX" @["https://google.com"]})
# (def listener (_hermes/unix-listen "/tmp/fetch.sock"))
# (fetch-server listener content)
# (def c (_hermes/unix-connect "/tmp/fetch.sock"))
# (protocol/send-msg c [:fetch {:hash "notfound"}])
# (protocol/send-msg c [:fetch {:hash "sha256:XXXX"}])
# (protocol/recv-msg c)