(import ./protocol)
(import ../build/_hermes)

(defn- handle-fetch-client
  [c content-map]
  
  (defn die
    [msg]
    (protocol/send-msg [:error msg])
    (os/exit 1))

  (defn do-fetch
    [c hash mirrors]
    (protocol/send-msg c [:stderr "TODO"])
    (die "..."))

  (match (protocol/read-msg c))
    {:hash hash}
      (if-let [mirrors (content-map hash)]
        (do-fetch c hash mirrors)
        (die (string/format "%v no known mirrors for hash" hash))
    (die "fetch protocol error"))

(defn fetch-server
  [listener-socket content-map]

  (var num-active-clients 0)

  (defn handle-connection
    []
    (def c (:accept listener))
    (def worker-pid (_hermes/fork))
    (if (zero? worker-pid)
      (do
        (handle-fetch-client c content-map)
        (os/exit 0))
      (do
        (file/close c)
        (++ num-active-clients)
        (while (not (zero? num-active-clients))
          (match (_hermes/wait-pid -1 _hermes/WNOHANG)
            [0 _]
              (-- num-active-clients)
            (break)))))
    (handle-connections))
    (handle-connections))