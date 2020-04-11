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
    [hash url]
    (def [pipe> pipe<] (process/pipe))
    (send-msg [:stdout (string/format "fetching %s" url)])
    (defer (do (:close pipe>)
               (:close pipe<))
      (with [errorf (file/temp)]
      (with [curl (process/spawn 
                    ["curl" "--silent" "--show-error" "--fail" "-L" "-O" "-" url]
                    :redirect [[stdout pipe<] [stderr ]])]
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
                (protocol/send-msg
                  [:stderr (string/format "mirror %s gave hash %s, expected %s" url expected hash)])
                (file/close outf)
                nil)
            (error nil))
          (do
            (file/seek errorf :set 0)
            (def err-msg (string "fetch failed:\n" (file/read errorf :all)))
            (send-msg [:stderr err-msg])))))))

  (defn fetch-from-mirrors
    [hash mirrors out-path]
    (defn fetch-from-mirrors
      [mirrors]
      (if (empty? mirrors)
        (die (string "no mirrors provided " hash))
        (do
          (def m (array/pop mirrors))
          (if-let [outf (fetch-from-url c hash m)]
            outf
            (fetch-from-mirrors hash mirrors)))))
    (fetch-from-mirrors hash mirrors out-path))

  (match (protocol/recv-msg c)
    [:fetch {:hash hash}]
      (if-let [mirrors (content-map hash)
               outf (fetch-from-mirrors c hash mirrors)]
        (do
          (protocol/send-msg :sending-data)
          (protocol/send-file outf))
        (die (string "no known mirrors for " hash)))
    (die "fetch protocol error")))

(defn fetch-server
  [listener-socket content-map]
  (var active-workers @[])
  (defn handle-connection
    []
    (def c (:accept listener))
    (if-let [worker (process/fork)]
      (do
        (file/close c)
        (array/append active-workers worker)
        (set active-workers (filter |(nil? ($ :exit-code)) active-workers)))
      (do
        (handle-fetch-client c content-map)
        (os/exit 0)))
    (handle-connections))
  (handle-connections))

(defn spawn-fetch-server
  [listener-socket content-map]
  (if-let [child (process/fork)]
    child
    (do
      (fetch-server listener-socket content-map)
      (os/exit 0))))