VMModule subclass: #LowtalkSample
	instanceVariableNames: 'libc counter table points total'
	classVariableNames: 'TABLE_SIZE'
	package: 'Tests-VM'!

LowtalkSample comment: 'A small Lowtalk program for LowtalkTest: it runs as Smalltalk (VMSimulation) and as C (VMTranslator) and must print the same.'!

!LowtalkSample class methodsFor: 'declaring'!
declarations
	^#((libc LibC) (counter int64_t 5) (table 'int32_t[TABLE_SIZE]') (points 'SamplePoint[4]') (total uint64_t))
!
initialize
	TABLE_SIZE := 8
! !

!LowtalkSample methodsFor: 'running'!
main: argc argv: argv
	<c: 'int main(int argc, char **argv)'>
	| sum p last |
	sum := 0.
	1 to: 10 do: [:i | sum := sum + i].
	self report: 'sum' value: sum.
	self report: 'counter' value: counter.
	0 to: TABLE_SIZE - 1 do: [:i | table at: i put: i * i].
	self report: 'table' value: (table at: 7).
	self report: 'squares' value: self sumOfSquares.
	p := points.
	0 to: 3 do: [:i |
		(p + i) x: i.
		(p + i) y: i * 10.
		(p + i) next: (i < 3 ifTrue: [p + (i + 1)] ifFalse: [self null])].
	self report: 'chain' value: (self chainSum: p).
	last := p + 3.
	self report: 'distance' value: last - p.
	self report: 'fib' value: (self fib: 20).
	self report: 'clamp' value: (self clamp: 300).
	self report: 'case' value: (self classify: 2) + (self classify: 7).
	self report: 'overflow' value: (self checkedAdd: 16r7FFFFFFFFFFFFFFF to: 1).
	self report: 'nooverflow' value: (self checkedAdd: 40 to: 2).
	self report: 'wrap' value: (self cCoerce: (self tagged: -3) to: 'int64_t').
	self report: 'untag' value: (self untag: (self tagged: -3)).
	self twice: [total := total + 21].
	self report: 'twice' value: (self cCoerce: total to: 'int64_t').
	self report: 'hash' value: (self cCoerce: (self hashOf: (self cString: 'Samaltak')) to: 'int64_t').
	self report: 'loop' value: self countdown.
	libc printf: 'argc=%d %s
' with: argc with: (argv at: 0).
	^0
!
report: label value: v
	<c: 'void report(const char *label, int64_t v)'>
	libc printf: '%s=%lld
' with: label with: v
! !

!LowtalkSample methodsFor: 'computing'!
sumOfSquares
	<c: 'int64_t sum_of_squares(void)'>
	| s |
	s := 0.
	0 to: TABLE_SIZE - 1 do: [:i | s := s + (table at: i)].
	^s
!
chainSum: first
	<c: 'int64_t chain_sum(SamplePoint *first)'>
	| s p |
	s := 0.
	p := first.
	[p notNull] whileTrue: [
		s := s + p x + p y.
		p := p next].
	^s
!
fib: n
	<c: 'int64_t fib(int64_t n)'>
	n < 2 ifTrue: [^n].
	^(self fib: n - 1) + (self fib: n - 2)
!
clamp: x
	^(x max: 0) min: 255
!
classify: n
	<c: 'int64_t classify(int64_t n)'>
	^n caseOf: {
		[1] -> [10].
		[2] -> [20]}
		otherwise: [-1]
!
checkedAdd: a to: b
	<c: 'int64_t checked_add(int64_t a, int64_t b)'>
	a ifNoOverflowAdd: b do: [:r | ^r].
	^-1
!
tagged: v
	"A SmallInteger oop."
	^((v << 1) bitOr: 1) asUInt64
!
untag: anOop
	^anOop asInt64 >> 1
!
twice: aBlock
	aBlock value.
	aBlock value
!
hashOf: aString
	<c: 'uint32_t hash_of(const char *aString)'>
	| h i c |
	h := 2166136261.
	i := 0.
	[(c := aString at: i) ~= 0] whileTrue: [
		h := ((h bitXor: c) * 16777619) asUInt32.
		i := i + 1].
	^h asUInt32
!
countdown
	<c: 'int64_t countdown(void)'>
	| n steps |
	n := 100.
	steps := 0.
	[n > 0] whileTrue: [
		n := (n bitAnd: 1) = 0 ifTrue: [n quo: 2] ifFalse: [n - 1].
		steps := steps + 1].
	^steps
! !

VMStruct subclass: #SamplePoint
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

!SamplePoint class methodsFor: 'declaring'!
fields
	^#((x int32_t) (y int32_t) (next 'SamplePoint *'))
! !
