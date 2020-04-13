(import ../build/_hermes)

(defn hash
  [algo item]

  (def is-dir
    (if (= (type item) :core/file)
      false
      (if-let [st (os/stat item)]
        (= (st :mode) :directory)
        (error (string "unable to stat " item)))))
    
  (string algo ":" 
    (match algo
      "sha256"
        (if is-dir
          (_hermes/sha256-dir-hash item)
          (_hermes/sha256-file-hash item))
        _ 
          (error (string "unsupported hash algorithm - " algo)))))

(defn check
  [item expected]
  (def algo 
    (if-let [idx (string/find ":" expected)]
      (string/slice expected 0 idx)
      (error (string/format "expected ALGO:VALUE, got %v" expected))))
  (def actual
    (hash algo item))
  (if (= expected actual)
    :ok
    [:fail actual]))

(defn assert
  [item expected]
  (match (check item expected)
    :ok nil
    [:fail actual] (error (string/format "expected %s to have hash %s, got hash %s" item expected actual))))