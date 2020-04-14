(import argparse)
(import ./builtins)

(def- params
  ["Run a marshalled hermes thunk."
   "thunk" 
     {:kind :option
      :short "t"
      :required true
      :help "Path to thunk."}])

(defn main
  [&]
 (def parsed-args (argparse/argparse ;params))
  (unless parsed-args
    (os/exit 1))
  ((unmarshal (slurp (parsed-args "thunk")) builtins/load-registry)))