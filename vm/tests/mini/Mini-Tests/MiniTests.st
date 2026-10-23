Object subclass: #MiniTests
	instanceVariableNames: 'escaper'
	classVariableNames: 'Shared'
	package: 'Mini-Tests'!

Object subclass: #Vec
	instanceVariableNames: 'x y'
	classVariableNames: ''
	package: 'Mini-Tests'!

ProtoObject subclass: #ProtoThing
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Tests'!

!MiniTests class methodsFor: 'running'!
run: aName
	('--- ' , aName) displayNl.
	self new perform: ('test' , aName) asSymbol
! !

!Vec methodsFor: 'accessing'!
describe
	^'vec ' , x printString , ',' , y printString
! !

!MiniTests methodsFor: 'arithmetic'!
testArith
	(3 + 4) printNl.
	(3 - 10) printNl.
	(6 * 7) printNl.
	(7 // 2) printNl.
	(-7 // 2) printNl.
	(7 \\ 2) printNl.
	(-7 \\ 2) printNl.
	(-7 rem: 2) printNl.
	(-7 quo: 2) printNl.
	(12 / 4) printNl.
	(7 / 2) printNl.
	(1 bitShift: 10) printNl.
	(-16 bitShift: -2) printNl.
	(5 bitAnd: 3) printNl.
	(5 bitOr: 3) printNl.
	(5 bitXor: 3) printNl.
	(3 < 4) printNl.
	(3 > 4) printNl.
	(3 = 3) printNl.
	(3 ~= 3) printNl.
	(3 max: 9) printNl.
	SmallInteger maxVal printNl.
	(SmallInteger maxVal + 1) printNl.
	(SmallInteger maxVal + 1) class printNl.
	(SmallInteger minVal - 1) printNl.
	(SmallInteger minVal - 1) class printNl.
	(SmallInteger maxVal + 1 - 1) class printNl.
	(SmallInteger maxVal * 2) printNl.
	SmallInteger minVal negated printNl.
	20 factorial printNl.
	30 factorial printNl.
	(1 bitShift: 64) printNl.
	100 factorial printNl.
	12345678901234567890123 printNl.
	-12345678901234567890123 printNl.
	(12345678901234567890123 - 12345678901234567890000) printNl.
	(12345678901234567890123 - 12345678901234567890000) class printNl.
	16rFF printNl.
	2r1010 printNl.
	-5 abs printNl.
	1e3 printNl.
	$a value printNl.
	(Character value: 65) printNl.
	(3 @ 4) printNl.
	((3 @ 4) + (1 @ 1)) printNl
! !

!MiniTests methodsFor: 'floats'!
testFloat
	(0.1 + 0.2) printNl.
	(1.5 * 2) printNl.
	(1 / 4) printNl.
	3.75 class printNl.
	1.0e300 class printNl.
	(1.0e300 * 10) printNl.
	(1.0e300 * 1.0e300) printNl.
	(1.0e300 * 1.0e300) class printNl.
	1.0e-300 printNl.
	2.0 sqrt printNl.
	3.7 truncated printNl.
	-3.7 truncated printNl.
	(2 raisedTo: 10) asFloat printNl.
	0.0 printNl.
	-0.0 printNl.
	(3 + 0.5) printNl.
	(0.5 < 1) printNl.
	1.0 exp printNl.
	(1.0 timesTwoPower: 10) printNl.
	1.5 asIEEEBits printNl.
	(Float fromIEEEBits: 4609434218613702656) printNl.
	-1.5 asIEEEBits printNl.
	1.0e15 printNl.
	1.0e16 printNl.
	123.456 printNl.
	2.5e-7 printNl.
	(1.0e300 / 1.0e299) printNl.
	(10 raisedTo: 20) printNl
! !

!MiniTests methodsFor: 'strings'!
testStrings
	('abc' , 'def') printNl.
	'hello' size printNl.
	('abc' < 'abd') printNl.
	('abc' = 'abc') printNl.
	(#foo == 'foo' asSymbol) printNl.
	(('foo' , 'bar') asSymbol == #foobar) printNl.
	('newSym' , 'bol') asSymbol printNl.
	(('newSym' , 'bol') asSymbol == ('new' , 'Symbol') asSymbol) printNl.
	#with:with: numArgs printNl.
	#+ numArgs printNl.
	'αβγ' size printNl.
	'αβγ' class printNl.
	('a' , 'β') class printNl.
	('a' , 'β') size printNl.
	('αβγ' at: 2) value printNl.
	#'wide→sym' class printNl.
	(#abc hash = 'abc' hash) printNl.
	'abc' hash printNl.
	((Smalltalk at: #MiniTests) == MiniTests) printNl.
	(Smalltalk at: #SnapCounter) printNl.
	#(1 $a 'str' #sym sym foo: at:put: (1 2) #(3) true false nil 2.5 -3 #+ #[7 8]) printNl.
	#[1 2 255] printNl.
	{1 + 1. 'x'. #y} printNl.
	('hello world' copyFrom: 7 to: 11) printNl.
	(ByteString new: 3) size printNl.
	'bang!!' displayNl.
	'it''s' size printNl.
	(Smalltalk packageList at: 1) printNl.
	(Smalltalk primitiveNames at: 1) printNl.
	(Smalltalk primitiveNames at: 198) printNl
! !

!MiniTests methodsFor: 'closures'!
makeCounter
	| n |
	n := 0.
	^[n := n + 1]
!
findFirstEven: arr
	arr do: [:x | x even ifTrue: [^x]].
	^nil
!
nlrFromNested
	#(1 2) do: [:a | #(3 4) do: [:b | (a + b) = 5 ifTrue: [^a * 10 + b]]].
	^0
!
makeEscaper
	^[:x | ^x]
!
testClosures
	| adder add5 counter c1 c2 sum i b |
	adder := [:x | [:y | x + y]].
	add5 := adder value: 5.
	(add5 value: 3) printNl.
	counter := [| n | n := 0. [n := n + 1]] value.
	counter value.
	counter value printNl.
	c1 := self makeCounter.
	c2 := self makeCounter.
	c1 value. c1 value. c2 value.
	c1 value printNl.
	c2 value printNl.
	(self findFirstEven: #(1 3 6 7 8)) printNl.
	self nlrFromNested printNl.
	((self makeEscaper) value: 42) printNl.
	([:a :b2 :c :d | a + b2 + c + d] value: 1 value: 2 value: 3 value: 4) printNl.
	([:a :b2 | a * b2] valueWithArguments: #(6 7)) printNl.
	([:a | a] value: 1 value: 2) printNl.
	(#(1 2 3) inject: 0 into: [:a :e | a + e]) printNl.
	(#(1 2 3) collect: [:e | e * e]) printNl.
	sum := 0. i := 1.
	[i <= 100] whileTrue: [sum := sum + i. i := i + 1].
	sum printNl.
	sum := 0.
	10 to: 1 by: -2 do: [:k | sum := sum * 10 + k].
	sum printNl.
	i := 0.
	b := [i < 5].
	b whileTrue: [i := i + 1].
	i printNl.
	(nil ifNil: [1] ifNotNil: [:x | x]) printNl.
	(3 ifNil: [1] ifNotNil: [:x | x + 1]) printNl.
	(nil ifNotNil: [:x | x]) printNl.
	(5 ifNil: [0]) printNl.
	(7 ifNotNil: [:x | x * 2] ifNil: [0]) printNl.
	i := 0.
	4 timesRepeat: [i := i + 10].
	i printNl.
	(true and: [false]) printNl.
	(false or: [true]) printNl.
	(1 to: 3 do: [:k | k]) printNl.
	sum := 0.
	1 to: 3 do: [:k | | t | t isNil ifTrue: [sum := sum + 1]. t := k].
	sum printNl
! !

!MiniTests methodsFor: 'unwinding'!
ensureNormal
	^['body' displayNl. 7] ensure: ['ensure ran' displayNl]
!
ensureNLR
	[^3] ensure: ['ensure on nlr' displayNl].
	^4
!
ensureNested
	[[^5] ensure: ['inner' displayNl]] ensure: ['outer' displayNl].
	^6
!
callBlock: aBlock
	^aBlock value
!
ensureDeep
	[self callBlock: [^9]] ensure: ['deep ensure' displayNl].
	^0
!
testUnwind
	| count |
	self ensureNormal printNl.
	self ensureNLR printNl.
	self ensureNested printNl.
	self ensureDeep printNl.
	count := 0.
	[count := count + 1] ensure: [count := count + 10].
	count printNl
! !

!MiniTests methodsFor: 'errors'!
testErrors
	| p |
	(3 foo: 4) printNl.
	nil bar printNl.
	(3 ifTrue: ['yes'] ifFalse: ['no']) printNl.
	p := 3 @ 4.
	p beImmutable.
	p setX: 10.
	p printNl.
	p isImmutable printNl.
	#(1 2 3) isImmutable printNl.
	(#(1 2 3) at: 1 put: 9) printNl.
	'abc' copy isImmutable printNl.
	'abc' isImmutable printNl.
	#foo isImmutable printNl.
	(#sym at: 1 put: $x) printNl.
	p beMutable.
	p setX: 10.
	p printNl
! !

!MiniTests methodsFor: 'processes'!
testProcesses
	| main s s2 p q counters w1 w2 done t |
	['high ran' displayNl] forkAt: 50.
	'after high fork' displayNl.
	['low ran' displayNl] forkAt: 30.
	'after low fork' displayNl.
	Processor sleep: 10.
	'main woke' displayNl.
	main := Processor activeProcess.
	[(Processor lastPreempted == main) printNl] forkAt: 60.
	s := Semaphore new.
	p := [s wait. 'consumer got 1' displayNl. s wait. 'consumer got 2' displayNl] forkAt: 45.
	'signal 1' displayNl.
	s signal.
	'signal 2' displayNl.
	s signal.
	s signal. s signal.
	s excessSignals printNl.
	s wait.
	s excessSignals printNl.
	[1 to: 3 do: [:i | ('A' , i printString) displayNl. Processor yield]] fork.
	[1 to: 3 do: [:i | ('B' , i printString) displayNl. Processor yield]] fork.
	Processor sleep: 20.
	counters := Array with: 0 with: 0.
	w1 := [[true] whileTrue: [counters at: 1 put: (counters at: 1) + 1]] forkAt: 30.
	w2 := [[true] whileTrue: [counters at: 2 put: (counters at: 2) + 1]] forkAt: 30.
	done := Semaphore new.
	[20 timesRepeat: [Processor sleep: 2]. done signal] forkAt: 60.
	done wait.
	((counters at: 1) > 0 and: [(counters at: 2) > 0]) printNl.
	w1 terminate.
	w2 terminate.
	(w1 cpuTime > 0) printNl.
	t := Smalltalk millisecondClock.
	Processor sleep: 30.
	((Smalltalk millisecondClock - t) >= 30) printNl.
	s2 := Semaphore new.
	q := [s2 wait. 'never' displayNl] forkAt: 45.
	q suspend.
	s2 signal.
	s2 excessSignals printNl.
	main priority printNl
! !

!MiniTests methodsFor: 'gc'!
deep: n
	n = 0 ifTrue: [^0].
	^(self deep: n - 1) + 1
!
testGC
	| keep sum old bad bm |
	keep := Array new: 1000.
	1 to: 3000000 do: [:i | keep at: i \\ 1000 + 1 put: (Array with: i with: nil)].
	sum := 0.
	keep do: [:a | sum := sum + (a at: 1)].
	sum printNl.
	1 to: 200000 do: [:i | keep at: i \\ 1000 + 1 put: (Array with: i with: i printString)].
	bad := 0.
	keep do: [:a | (a at: 2) = (a at: 1) printString ifFalse: [bad := bad + 1]].
	bad printNl.
	(self deep: 100000) printNl.
	Smalltalk gc.
	sum := 0.
	keep do: [:a | sum := sum + (a at: 1)].
	sum printNl.
	old := Array new: 100.
	Smalltalk gc.
	1 to: 1000000 do: [:i | old at: i \\ 100 + 1 put: (Array with: i)].
	(old inject: 0 into: [:a :e | a + (e at: 1)]) printNl.
	(Array new: 100000) size printNl.
	(ByteArray new: 1000000) size printNl.
	bm := Bitmap new: 3.
	bm at: 2 put: 4000000000.
	(bm at: 2) printNl.
	((Smalltalk vmStats at: 1) > 5) printNl.
	((Smalltalk vmStats at: 2) > 0) printNl.
	Smalltalk scavenge.
	(keep at: 1) printNl
! !

!MiniTests methodsFor: 'gc'!
testOutOfMemory
	"Run with --max-heap 64: requests that can never fit fail with error code 1 (PRIM_ERR_NO_MEMORY)."
	| keep big |
	(Array basicNew: 1099511627776) printNl.
	(ByteArray basicNew: 1180591620717411303424) printNl.
	(Array basicNew: 10000000) printNl.
	(Point basicNew: 1) printNl.
	(Array basicNew: -1) printNl.
	keep := Array with: (ByteArray basicNew: 30000000) with: nil.
	(ByteArray basicNew: 40000000) printNl.
	(keep at: 1) shallowCopy size printNl.
	keep at: 2 put: (ByteArray basicNew: 20000000).
	(keep at: 1) shallowCopy printNl.
	keep at: 1 put: nil.
	big := ByteArray basicNew: 40000000.
	big size printNl.
	1 to: 200000 do: [:i | keep at: 1 put: (Array with: i)].
	((keep at: 1) at: 1) printNl
! !

!MiniTests methodsFor: 'snapshot'!
testSnapshot
	| path resumed |
	path := Smalltalk getenv: 'MINI_SNAPSHOT'.
	SnapCounter := 41.
	Shared := 'shared state'.
	resumed := Smalltalk snapshot: path.
	resumed
		ifTrue: [
			SnapCounter := SnapCounter + 1.
			('resumed ' , SnapCounter printString , ' ' , Shared) displayNl.
			(3 + 4) printNl.
			(self deep: 1000) printNl]
		ifFalse: [
			'saved' displayNl.
			Smalltalk quit]
! !

!MiniTests methodsFor: 'reflection'!
testContext
	| ctx |
	thisContext method selector printNl.
	thisContext sender method selector printNl.
	(thisContext receiver == self) printNl.
	ctx := thisContext.
	[thisContext home == ctx] value printNl.
	[thisContext closure notNil] value printNl.
	(thisContext method methodClass == MiniTests) printNl.
	thisContext pc class printNl.
	((MiniTests lookup: #testContext) == thisContext method) printNl.
	(MiniTests lookup: #nonexistent) printNl.
	MiniTests class printNl.
	MiniTests class class printNl.
	(MiniTests class superclass == Object class) printNl.
	(ProtoObject class superclass == Class) printNl.
	(Smalltalk class == SystemDictionary) printNl
!
testPerform
	(3 perform: #+ with: 4) printNl.
	(3 perform: #factorial) printNl.
	(3 perform: #between:and: withArguments: #(1 5)) printNl.
	(3 perform: #zork) printNl.
	(Array perform: #with:with:with: withArguments: #(1 2 3)) printNl.
	(3 perform: #+ with: 4 with: 5) printNl
!
testInstances
	| before pts p a b |
	before := Point allInstances size.
	pts := Array with: 1 @ 2 with: 3 @ 4 with: 5 @ 6.
	(Point allInstances size - before) printNl.
	p := 1 @ 2.
	p changeClassTo: Vec.
	p class printNl.
	p describe printNl.
	(p changeClassTo: Array) printNl.
	a := 'old' copy.
	b := Array with: a with: a.
	a becomeForward: 'new'.
	b printNl.
	(1 @ 2) copy printNl.
	((3 @ 4) instVarAt: 2) printNl.
	(Object new identityHash > 0) printNl.
	pts size printNl
!
testSampling
	| s count a info t |
	s := Semaphore new.
	Smalltalk registerExternal: s at: 1.
	count := Array with: 0.
	[[s wait. count at: 1 put: (count at: 1) + 1] repeat] forkAt: 70.
	Smalltalk samplerInterval: 1000 index: 1.
	t := Smalltalk millisecondClock.
	[Smalltalk millisecondClock < (t + 50)] whileTrue.
	Smalltalk samplerInterval: 0 index: 1.
	((count at: 1) >= 10) printNl.
	a := Semaphore new.
	Smalltalk registerExternal: a at: 2.
	info := Array with: nil with: 0.
	[[a wait. info at: 1 put: Smalltalk allocationSampleInfo. info at: 2 put: (info at: 2) + 1] repeat] forkAt: 70.
	Smalltalk allocationSampling: 100000 index: 2.
	1 to: 100000 do: [:i | Array new: 10].
	Smalltalk allocationSampling: 0 index: 2.
	((info at: 2) > 10) printNl.
	(((info at: 1) at: 2) > 0) printNl.
	(#(#Array #Context) includes: ((info at: 1) at: 1) name) printNl.
	a := Processor activeProcess cpuMicroseconds.
	t := Smalltalk millisecondClock.
	[Smalltalk millisecondClock < (t + 20)] whileTrue.
	(Processor activeProcess cpuMicroseconds - a >= 15000) printNl
! !

!MiniTests methodsFor: 'fatal'!
recurse: n
	^(self recurse: n + 1) + 1
!
testRecurse
	(self recurse: 0) printNl
!
testFatalDNU
	ProtoThing new foo
! !

!MiniTests methodsFor: 'benchmarks'!
fib: n
	n < 2 ifTrue: [^n].
	^(self fib: n - 1) + (self fib: n - 2)
!
testBench
	| t r n sends loops |
	n := 32.
	t := Smalltalk microsecondClock.
	r := self fib: n.
	t := Smalltalk microsecondClock - t.
	sends := (self fib: n + 1) * 2 - 1.
	self stderr: 'fib(' , n printString , ')=' , r printString , ' ' , (t // 1000) printString , ' ms, '
		, (sends * 1000000 // t) printString , ' sends/s' , Character lf asString.
	t := Smalltalk microsecondClock.
	loops := 0.
	1 to: 100000000 do: [:i | loops := loops + 1].
	t := Smalltalk microsecondClock - t.
	self stderr: 'loop 1e8: ' , (t // 1000) printString , ' ms, ' , (1400000000 * 1000000 // t) printString
		, ' bytecodes/s' , Character lf asString.
	r printNl
! !

!Vec methodsFor: 'cache test'!
alpha
	^1
!
beta
	^2
! !

!MiniTests methodsFor: 'misc'!
testMisc
	| b v |
	b := ByteArray new: 16.
	b uint32At: 1 put: 16r01020304.
	(b uint16At: 1) printNl.
	(b uint32At: 1) printNl.
	(b uint16BigEndianAt: 1) printNl.
	(b uint32BigEndianAt: 1) printNl.
	b at: 5 put: 255; at: 6 put: 255.
	(b int16At: 5) printNl.
	(b int16BigEndianAt: 5) printNl.
	b float64At: 9 put: 1.5.
	(b float64At: 9) printNl.
	b float32At: 1 put: 0.5.
	(b float32At: 1) printNl.
	(b uint32At: 14) printNl.
	(thisContext tryPrimitive: 1 receiver: 3 args: #(4)) printNl.
	(thisContext tryPrimitive: 1 receiver: 3 args: #(nil)) printNl.
	(thisContext tryPrimitive: 81 receiver: 3 args: #(#factorial)) printNl.
	(thisContext tryPrimitive: 999 receiver: 3 args: #()) printNl.
	(thisContext tryPrimitive: 73 receiver: #(5 6) args: #(2)) printNl.
	v := Vec new.
	v alpha printNl.
	Vec methodDict at: #alpha put: (Vec lookup: #beta).
	#alpha flushCache.
	v alpha printNl.
	Processor relinquish: 1000.
	'relinquished' displayNl.
	(Smalltalk utcMicroseconds > 1700000000000000) printNl.
	(Smalltalk imagePath size > 0) printNl.
	1.0 sin printNl.
	0.0 cos printNl.
	1.0 arcTan printNl.
	1.0 ln printNl.
	3.75 fractionPart printNl.
	8.0 exponent printNl
! !

Object weakSubclass: #WeakPair
	instanceVariableNames: 'tag'
	classVariableNames: ''
	package: 'Mini-Tests'!

!WeakPair methodsFor: 'accessing'!
tag
	^tag
!
tag: x
	tag := x
! !

!MiniTests methodsFor: 'weak'!
nils: aWeakArray
	^aWeakArray inject: 0 into: [:n :e | e == nil ifTrue: [n + 1] ifFalse: [n]]
!
testWeak
	| w kept o p fin count many keep |
	w := WeakArray new: 4.
	kept := 'kept' copy.
	w at: 1 put: kept; at: 2 put: 'dropped' copy; at: 3 put: 42; at: 4 put: #sym.
	Smalltalk scavenge.
	w printNl.
	o := Array with: 'old'.
	Smalltalk gc.
	w at: 2 put: o.
	o := nil.
	Smalltalk scavenge.
	(w at: 2) printNl.
	Smalltalk gc.
	(w at: 2) printNl.
	p := WeakPair new: 2.
	p tag: 'strong tag' copy.
	p at: 1 put: 'weak' copy; at: 2 put: kept.
	Smalltalk gc.
	p tag printNl.
	(p at: 1) printNl.
	(p at: 2) printNl.
	Smalltalk gc.
	w := WeakArray new: 100.
	Smalltalk gc.
	keep := Array new: 100.
	1 to: 100 do: [:i | w at: i put: (keep at: i put: (Array with: i))].
	2 to: 100 by: 2 do: [:i | keep at: i put: nil].
	1 to: 20 do: [:k | 1 to: 20000 do: [:i | Array new: 4]].
	(self nils: w) printNl.
	((w at: 99) at: 1) printNl.
	fin := Semaphore new.
	Smalltalk specialObjectsArray at: 36 put: fin.
	count := Array with: 0.
	[[fin wait. count at: 1 put: (count at: 1) + 1] repeat] forkAt: 60.
	w at: 1 put: 'soon gone' copy.
	Smalltalk scavenge.
	self yourself.
	(count at: 1) printNl.
	(w at: 1) printNl.
	keep := Array new: 10000.
	1 to: 10000 do: [:i | keep at: i put: (Array with: i)].
	many := Array new: 10000.
	1 to: 10000 do: [:i | many at: i put: ((WeakArray new: 1) at: 1 put: (keep at: i); yourself)].
	2 to: 10000 by: 2 do: [:i | keep at: i put: nil].
	Smalltalk gc.
	(many inject: 0 into: [:n :e | (e at: 1) == nil ifTrue: [n + 1] ifFalse: [n]]) printNl.
	(((many at: 9999) at: 1) at: 1) printNl.
	(count at: 1) > 1
		ifTrue: ['finalization signaled' displayNl]
		ifFalse: [(count at: 1) printNl].
	((Smalltalk vmStats at: 12) > 5000) printNl.
	keep size printNl
! !
