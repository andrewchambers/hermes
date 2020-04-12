(import process)
(import jdn)

(def- sz-buf @"")

(defn send-msg [f msg]
  (def msg-buf (jdn/encode msg))
  (buffer/push-word (buffer/clear sz-buf) (length msg-buf))
  (file/write f sz-buf)
  (file/write f msg-buf)
  (file/flush f))

(defn short-read-error
  []
  (error "remote unexpectedly terminated the connection"))

(defn- read-sz
  [f]
  (file/read f 4 (buffer/clear sz-buf))
  (unless (= (length sz-buf) 4)
    (short-read-error))

  (bor 
             (in sz-buf 0)
    (blshift (in sz-buf 1) 8)
    (blshift (in sz-buf 2) 16)
    (blshift (in sz-buf 3) 24)))

(defn recv-msg [f]
  (def sz (read-sz f))
  (def buf (file/read f sz))
  (unless (= (length buf) sz)
    (short-read-error))
  (jdn/decode buf))

(defn send-file
  [f to-send]
  (def buf @"")
  (defn send-file-chunks []
    (file/read to-send 262144 (buffer/clear buf))
    (buffer/push-word (buffer/clear sz-buf) (length buf))
    (file/write f sz-buf)
    (file/write f buf)
    (if (empty? buf)
      nil
      (send-file-chunks)))
  (send-file-chunks))


(defn recv-file
  [f recv-to]
  (def buf @"")
  (defn recv-file-chunks []
    (def sz (read-sz f))
      (if (zero? sz)
        nil
        (do 
          (file/read f sz (buffer/clear buf))
          (unless (= (length buf) sz)
            (short-read-error))
          (file/write recv-to buf)
          (recv-file-chunks))))
  (recv-file-chunks))

(defn send-dir
  [f path]
  (def [p1 p2] (process/pipe))
  (defer (do
           (file/close p1)
           (file/close p2))
    (with [tar (process/spawn
                  ["tar" # Note compression is done via the transport, e.g. ssh -C
                   "-C" path
                   "--numeric-owner"
                   "--owner=0"
                   "--group=0"
                   "-c" "-f" "-" "."]
                  :redirects [[stdout p2]])]
      (file/close p2)
      (send-file f p1)
      (unless (zero? (process/wait tar))
        (error "sending directory failed")))))

(defn recv-dir
  [f path]
  (os/mkdir path)
  (def [p1 p2] (process/pipe))
  (defer (do
           (file/close p1)
           (file/close p2))
    (with [tar (process/spawn
                  ["tar"
                   "-C" path
                   "-p" "-x" "-f" "-"]
                  :redirects [[stdin p1]])]
      (file/close p1)
      (recv-file f p2)
      (file/close p2)
      (unless (zero? (process/wait tar))
        (error "receiving directory failed")))))