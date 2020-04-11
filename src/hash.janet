(import ../build/_hermes)

(defn check
  [item expected]
  
  (def is-dir
    (if (= (type item) :core/file)
      false
      (if-let [st (os/stat item)]
        (= (st :mode) :directory)
        (error (string "unable to stat " item)))))

  (def actual
    (match (string/split ":" expected)
      ["sha256" _]
        (string
          "sha256:"
          (if is-dir
            (_hermes/sha256-dir-hash item)
            (_hermes/sha256-file-hash item)))
      _ 
        (error (string "unsupported hash format - " expected))))
  (if (= expected actual)
    :ok
    [:fail actual]))

(defn assert
  [item expected]
  (match (check item expected)
    :ok nil
    [:fail actual] (error (string/format "expected %s to have hash %s, got hash %s" item expected actual))))