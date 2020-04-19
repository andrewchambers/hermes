(import process)

(defn download
  [url on-data]
  
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
          nil
          (do
            (on-data buf)
            (get-file-chunks))))
      (get-file-chunks)

      (if (zero? (process/wait curl))
        :ok
        (do
          (file/seek errorf :set 0)
          (def err-msg (string "download of " url " failed:\n" (file/read errorf :all)))
          [:fail err-msg]))))))