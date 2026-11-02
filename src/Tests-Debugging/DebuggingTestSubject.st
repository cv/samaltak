Object subclass: #DebuggingTestSubject
	instanceVariableNames: 'count'
	classVariableNames: ''
	package: 'Tests-Debugging'!

DebuggingTestSubject comment: 'Methods the debugger tests break in, step through and recompile.'!

!DebuggingTestSubject methodsFor: 'examples'!
helper
	^20
!
compute
	^self helper * 2
!
sumOf: aCollection
	^aCollection inject: 0 into: [:sum :each | sum + each]
!
callsDivide
	| x |
	x := 1 / 0.
	^x
!
callsCompute
	| r |
	r := self compute.
	^r + 1
!
count
	^count
!
spin
	"A busy loop without temporaries: its frame is empty at the backward jump."
	[true] whileTrue: [count := (count ifNil: [0]) + 1]
!
haltingAdd: x
	| y |
	y := x + 1.
	self halt.
	^y * 2
!
sumTwice
	| sum |
	sum := 0.
	#(1 2) do: [:each | sum := sum + each].
	^sum * 2
!
doubledPlusOne
	^#(1 2) collect: [:each | | d | d := each * 2. d + 1]
!
callsHalting
	^(self haltingAdd: 4) + 1
!
haltingHandler
	"A handler that halts, between an unwind block below the signal and one around the handler."
	| log |
	log := OrderedCollection new.
	[log add: ([[1 / 0] ensure: [log add: #unwound]] on: ZeroDivide do: [:e | | v | v := 6. self halt. log add: #handled. v + 1])]
		ensure: [log add: #ensured].
	^log
!
loop
	| i |
	i := 0.
	[true] whileTrue: [i := i + 1. count := i]
! !

!DebuggingTestSubject class methodsFor: 'sources'!
restoreSources
	"Undo the tests' edits of helper and compute."
	#('helper
	^20' 'compute
	^self helper * 2') do: [:source | | sel |
		sel := (source copyUpTo: Character lf) asSymbol.
		(self compiledMethodAt: sel) sourceCode = source
			ifFalse: [self compile: source classified: 'examples']]
! !
