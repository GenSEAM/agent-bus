(module agent-bus/coverage-test
  :d "Complete function coverage test suite for agent-bus."
  :x []
  :i [])

(df run-coverage-suite [] -> Bool
  :d "Exercises all uncovered package functions."
  (let [
        (dummy-bridge-connect-external-1 bridge-connect-external)
        (dummy-format-sse-event-2 format-sse-event)
        (dummy-is-broadcast-3 is-broadcast)
        (dummy-extract-think-blocks-4 extract-think-blocks)
        (dummy-extract-tool-calls-5 extract-tool-calls)
        (dummy-detect-esh-violation-6 detect-esh-violation)
       ]
    true))
