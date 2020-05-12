(import posix-spawn)

(defn download
  [url on-data]
  
  (def [pipe> pipe<] (posix-spawn/pipe))
  (defer (do (:close pipe>)
             (:close pipe<))
    (with [errorf (file/temp)]
    (with [curl (posix-spawn/spawn 
                  ["curl" "--silent" "--show-error" "--fail" "-L" url]
                  :file-actions [[:dup2 pipe< stdout] [:dup2 errorf stderr]])]
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

      (if (zero? (posix-spawn/wait curl))
        :ok
        (do
          (file/seek errorf :set 0)
          (def err-msg (string "download of " url " failed:\n" (file/read errorf :all)))
          [:fail err-msg]))))))