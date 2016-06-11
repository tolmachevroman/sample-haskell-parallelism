import Control.DeepSeq
import Control.Parallel.Strategies

-- Looped n times square root function application
longComputation n = (!! n) . iterate sqrt

main = print $ s where
  s = sum results :: Float
  results = map (longComputation 100) [1..10000] `using` parListChunk 100 rdeepseq