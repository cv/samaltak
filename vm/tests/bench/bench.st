| fib t r out c txt |
out := WriteStream on: String new.
fib := nil.
Smalltalk at: #BenchFib put: nil.
t := Time microsecondClockValue.
r := (Integer compile: 'benchFib ^self < 2 ifTrue: [self] ifFalse: [(self - 1) benchFib + (self - 2) benchFib]' classified: 'bench') isNil.
t := Time microsecondClockValue. r := 30 benchFib. t := Time microsecondClockValue - t.
out nextPutAll: 'fib30 '; print: t // 1000; nextPutAll: ' ms, '; print: (r * 2 - 1) * 1000000 // t // 1000000; nextPutAll: 'M sends/s'; cr.
t := Time microsecondClockValue. r := 0. 1 to: 30000000 do: [:i | r := r + i]. t := Time microsecondClockValue - t.
out nextPutAll: 'loop30M '; print: t // 1000; nextPutAll: ' ms'; cr.
t := Time microsecondClockValue. r := 0.0. 1 to: 3000000 do: [:i | r := r + (i * 1.5)]. t := Time microsecondClockValue - t.
out nextPutAll: 'float3M '; print: t // 1000; nextPutAll: ' ms'; cr.
txt := 'The quick brown fox jumps over the lazy dog 0123456789 := ^self'.
t := Time microsecondClockValue.
200 timesRepeat: [c := Canvas extent: 900 @ 500 scale: 2. 1 to: 40 do: [:y | c drawString: txt at: 4 @ (y * 12) font: Font code color: Color black]. c displayList].
t := Time microsecondClockValue - t.
out nextPutAll: 'text '; print: (200 * 40 * txt size) * 1000000 // t; nextPutAll: ' glyphs/s'; cr.
t := Time microsecondClockValue. 30 timesRepeat: [1000 factorial]. t := Time microsecondClockValue - t.
out nextPutAll: '1000! x30 '; print: t // 1000; nextPutAll: ' ms'.
Integer removeSelector: #benchFib.
out contents
