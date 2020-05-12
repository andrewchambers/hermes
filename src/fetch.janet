(import fork)
(import ./download)
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

    (def outf (file/temp))

    (defn dl-progress
      [buf]
      # TODO send progress report to client
      (file/write outf buf))

    (match (download/download url dl-progress)
      :ok
        (do
          (file/seek outf :set 0)
          (match (hash/check outf hash)
            :ok
              (do
                (file/seek outf :set 0)
                outf)
            [:fail actual]
              (do
                (protocol/send-msg c
                  [:stderr (string/format "expected hash %s, mirror gave %s\n" hash actual)])
                (file/close outf)
                nil)))
      [:fail err-msg]
        (do 
          (protocol/send-msg c [:stderr err-msg])
          (file/close outf)
          nil)))

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
    (if-let [child (fork/fork)]
      (do
        (file/close c)
        (fork/wait child))
      # Double fork to prevent zombies and ensure
      # we cleanup all resources asap.
      (if-let [child (fork/fork)]
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
  (if-let [child (fork/fork)]
    child
    (do
      (serve listener-socket content-map)
      (os/exit 0))))

(defn fetch*
  [hash dest]
  (def fetch-socket (dyn :fetch-socket))
  (unless (and fetch-socket (os/stat fetch-socket))
    (error "fetch only possible in packages that specify :content"))
  (with [destf (or (file/open dest :wb) (error (string "unable to open " dest)))]
  (with [c (_hermes/unix-connect fetch-socket)]
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