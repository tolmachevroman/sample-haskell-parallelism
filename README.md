Haskell is known for it’s exceptional support for parallelising programs. Being highly abstract, pure and lazy means that using Haskell one can construct some meaningful stuff in a few lines of code, be aware of any probable side effects and let the runtime distribute the computational load. This latter, however, also brings some subtle problems with _evaluation_, when one may end up with a bunch of weakly evaluated _thunks_ causing space leaks and affecting overall performance. 

Overall, optimising a program so that it can benefit from parallelising is a beautiful craftsmanship, since it depends deeply on the algorithms used, the input data and the output desired.  

In the example below, based on the Chapter 2 of [Parallel and Concurrent Programming in Haskell book](http://chimera.labs.oreilly.com/books/1230000000929/pt01.html), I tried to play with and understand the simplest form of parallel computation - a _deterministic_ one. This means that there are no side effects, and calculation of one element of the input list no affects calculation of any other element. This way one can confidently reason about the program, since there won’t be unexpected differences between running it on one or several cores.

So let’s say we have a function called `longComputation`, performing some mathematical calculations. In this particular case, it sequentially applies square root `n` times. We want to `map` this function over an input list and show the `sum` of the resulting list later:

```
--Square root function applied n times
longComputation n = foldr (.) id (replicate n sqrt)

main = print $ s where
  s = sum results :: Float
  results = map (longComputation 100) [1..10000]
```
  
First, let’s see the performance without any parallelism.

```
$ ghc -o program program.hs
```

`-o` means optimised here

```
$ ./program +RTS -s
```

```
10000.0
    66,044,808 bytes allocated in the heap
     2,872,632 bytes copied during GC
       989,928 bytes maximum residency (3 sample(s))
        69,480 bytes maximum slop
             3 MB total memory in use (0 MB lost due to fragmentation)

                                   Tot time (elapsed)  Avg pause  Max pause
Gen  0       105 colls,     0 par    0.003s   0.005s     0.0000s    0.0016s
Gen  1         3 colls,     0 par    0.001s   0.002s     0.0006s    0.0010s

INIT    time    0.000s  (  0.002s elapsed)
MUT     time    0.023s  (  0.026s elapsed)
GC      time    0.005s  (  0.007s elapsed)
EXIT    time    0.000s  (  0.000s elapsed)
Total   time    0.032s  (  0.035s elapsed)

%GC     time      14.7%  (19.5% elapsed)

Alloc rate    2,873,262,333 bytes per MUT second

Productivity  84.8% of total user, 77.9% of total elapsed
```
  
Function terminated after 0.035 seconds.

Now, let’s add some parallelism. We’ll use a function `parList :: Strategy a -> Strategy [a]` from `Control.Parallel.Strategies` which takes `Strategy` as an argument and evaluates each element of the list according to it. Since we need to fully evaluate each computation in parallel, we use `rdeepseq` from `Control.DeepSeq`

```
import Control.DeepSeq import Control.Parallel.Strategies

--Square root function applied n times
longComputation n = foldr (.) id (replicate n sqrt)

main = print $ s where
  s = sum results :: Float
  results = map (longComputation 100) [1..10000] `using` parList rdeepseq
```
  
Haskell provides a handy function `using :: a -> Strategy a -> a` which evaluates a value with `runEval` method from the `Eval` Monad.  

```
$ ghc -threaded -o program program.hs
```

`-threaded` indicates to optimise the program so that it can run on multiple cores.

First, let’s try it on one core, as before, to see if there’s any difference.

```
$ ./program +RTS -N1 -s
```

```
10000.0
   125,328,872 bytes allocated in the heap
     4,893,200 bytes copied during GC
     1,597,560 bytes maximum residency (3 sample(s))
        80,680 bytes maximum slop
             4 MB total memory in use (0 MB lost due to fragmentation)

                                   Tot time (elapsed)  Avg pause  Max pause
Gen  0       218 colls,     0 par    0.010s   0.011s     0.0001s    0.0011s
Gen  1         3 colls,     0 par    0.002s   0.003s     0.0010s    0.0020s

TASKS: 4 (1 bound, 3 peak workers (3 total), using -N1)

SPARKS: 10000 (0 converted, 1809 overflowed, 0 dud, 32 GC'd, 8159 fizzled)

INIT    time    0.000s  (  0.002s elapsed)
MUT     time    0.020s  (  0.020s elapsed)
GC      time    0.013s  (  0.014s elapsed)
EXIT    time    0.000s  (  0.000s elapsed)
Total   time    0.038s  (  0.036s elapsed)

Alloc rate    6,373,842,852 bytes per MUT second

Productivity  66.2% of total user, 69.5% of total elapsed
```
  
Not surprisingly, a worse result here. Parallelism added a small overhead, so we ended up with a bit slower time. It’s easy to see how badly are _sparks_ distributed using just one core.
  
Now, let’s try it on 4 cores:
  
```
./program +RTS -N4 -s
```
  
```
10000.0
   123,535,648 bytes allocated in the heap
     5,226,464 bytes copied during GC
     1,489,032 bytes maximum residency (4 sample(s))
       317,840 bytes maximum slop
             6 MB total memory in use (0 MB lost due to fragmentation)

                                   Tot time (elapsed)  Avg pause  Max pause
Gen  0        73 colls,    73 par    0.031s   0.010s     0.0001s    0.0010s
Gen  1         4 colls,     3 par    0.014s   0.005s     0.0012s    0.0036s

Parallel GC work balance: 9.77% (serial 0%, perfect 100%)

TASKS: 10 (1 bound, 9 peak workers (9 total), using -N4)

SPARKS: 10000 (9490 converted, 510 overflowed, 0 dud, 0 GC'd, 0 fizzled)

INIT    time    0.000s  (  0.001s elapsed)
MUT     time    0.039s  (  0.013s elapsed)
GC      time    0.045s  (  0.015s elapsed)
EXIT    time    0.000s  (  0.000s elapsed)
Total   time    0.090s  (  0.029s elapsed)

Alloc rate    3,156,895,839 bytes per MUT second

Productivity  49.5% of total user, 152.2% of total elapsed
```
  
Again, looking at the _sparks_ one can see a better distribution using 4 cores. Overall gain is 0.035/0.029, roughly 1.2 times faster. 
  
Now, using `parList` one lets the system control how many sparks got created. In the example below we see some sparks `overflowed`, which means that overall spark number is probably too high. Let’s tinker with it and try to "chop" the list manually using a function `parListChunk :: Int -> Strategy a -> Strategy [a]` which gets one extra parameter compared to `parList`, a number of items per chunk.
  
```
import Control.DeepSeq import Control.Parallel.Strategies

-- Looped n times sqrt function application
longComputation n = foldr (.) id (replicate n sqrt)

main = print $ s where
  s = sum results :: Float
  results = map (longComputation 100) [1..10000] `using` parListChunk 100 rdeepseq
```

```
10000.0
   111,734,304 bytes allocated in the heap
     4,749,976 bytes copied during GC
       942,376 bytes maximum residency (4 sample(s))
        76,896 bytes maximum slop
             5 MB total memory in use (0 MB lost due to fragmentation)

                                   Tot time (elapsed)  Avg pause  Max pause
Gen  0        58 colls,    58 par    0.024s   0.006s     0.0001s    0.0005s
Gen  1         4 colls,     3 par    0.007s   0.003s     0.0007s    0.0014s

Parallel GC work balance: 15.39% (serial 0%, perfect 100%)

TASKS: 10 (1 bound, 9 peak workers (9 total), using -N4)

SPARKS: 100 (100 converted, 0 overflowed, 0 dud, 0 GC'd, 0 fizzled)

INIT    time    0.000s  (  0.001s elapsed)
MUT     time    0.024s  (  0.010s elapsed)
GC      time    0.031s  (  0.009s elapsed)
EXIT    time    0.000s  (  0.000s elapsed)
Total   time    0.061s  (  0.020s elapsed)

Alloc rate    4,678,990,954 bytes per MUT second

Productivity  48.6% of total user, 147.1% of total elapsed
```

I tried different numbers, and found that the best results are obtained within 100 - 200 chunks generated. Overall gain in this case is 0.035/0.020, 1.75 times faster.

This seems like a fairly low improvement rate, less then 2 times on 4 cores! Admittedly, the example above has some room for improvement, how much could it be? What would be the theoretical maximum value? 

[Amdahl’s law](https://en.wikipedia.org/wiki/Amdahl%27s_law) can tell us. The logic is to separate sequential and parallelised parts, and obviously the whole program won’t run faster than the sequential part. Then it can be shown mathematically that adding whatever number of processors to the parallel part has a speed up limitation.  

![](https://cloud.githubusercontent.com/assets/560815/15988066/dd9e08bc-3010-11e6-919e-d2c3de7a2a98.png)

, where `p` is a portion of the program that can be parallelised, and `n` is a number of cores. 

Looking into the example above, the parallel part is calculating mapped functions, and the sequential one is calculating the final sum going through the whole list. On one core, that second part takes about 20% of the whole computation time. I measured it by running a simple program calculating sum of the same sized list. That means that the parallelised portion is about 80%. Which in turn leads us to

![](https://cloud.githubusercontent.com/assets/560815/15988065/dd986a56-3010-11e6-8554-86355fd3b2da.png)

, 2.5 maximum speed up on 4 cores.

Probably, playing with some finer grain control stuff like `Par` Monad would bring us somewhat closer to that value; probably I just miscalculated the parallelised portion and the maximum speed up is lower.

[ThreadScope](https://wiki.haskell.org/ThreadScope) shows that 1 core (`HEC 0`) of 4 is occupied managing the spark pool and doing garbage collection: 

![](https://cloud.githubusercontent.com/assets/560815/15988064/dd97b1b0-3010-11e6-957a-e30b78c1d093.png)

So while the computation is evenly distributed over all 4 cores, one core in particular manages the spark pool, which might not be the most efficient way. 
