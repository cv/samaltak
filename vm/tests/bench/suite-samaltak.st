| cls b out |
cls := Object subclass: #Bench instanceVariableNames: '' classVariableNames: '' package: 'Bench'.
#('fib: n ^n < 2 ifTrue: [n] ifFalse: [(self fib: n - 1) + (self fib: n - 2)]'
  'loop | r | r := 0. 1 to: 30000000 do: [:i | r := r + i]. ^r'
  'floats | r | r := 0.0. 1 to: 3000000 do: [:i | r := r + (i * 1.5)]. ^r'
  'sends | r | r := 0. 1 to: 10000000 do: [:i | r := self id: r]. ^r'
  'id: x ^x + 1'
  'dict | d | d := Dictionary new. 1 to: 300000 do: [:i | d at: i put: i]. 1 to: 300000 do: [:i | d at: i]. ^d size'
  'strings | s | s := WriteStream on: String new. 1 to: 300000 do: [:i | s nextPutAll: i printString]. ^s contents size'
  'alloc | a | 1 to: 3000000 do: [:i | a := Array new: 4]. ^a'
  'blocks | r b | r := 0. b := [:x | x + 1]. 1 to: 10000000 do: [:i | r := b value: r]. ^r') do: [:src | cls compile: src classified: 'bench'].
b := cls new. out := WriteStream on: String new.
#(#('fib: 30' #fib) #('loop 30M' #loop) #('floats 3M' #floats) #('sends 10M' #sends) #('blocks 10M' #blocks) #('dict 300k' #dict) #('strings 300k' #strings) #('alloc 3M' #alloc)) do: [:pair |
  | t | t := Time millisecondsToRun: [(pair at: 2) == #fib ifTrue: [b fib: 30] ifFalse: [b perform: (pair at: 2)]].
  out nextPutAll: (pair at: 1); space; print: t; nextPutAll: ' ms'; cr].
out nextPutAll: '1000! x30 '; print: (Time millisecondsToRun: [30 timesRepeat: [1000 factorial]]); nextPutAll: ' ms'.
out contents
