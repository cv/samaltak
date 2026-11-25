Object subclass: #CudaTrace
	instanceVariableNames: 'entries limit calls since lock'
	classVariableNames: 'Default Tracing Quiet'
	package: 'System-CUDA'!

CudaTrace comment: 'I am the record of recent CUDA work that the GPU Monitor shows, kept only while tracing is on (start, stop; the monitor starts me while it is open). Two kinds: operations (CudaMatrix products, cuRAND fills, copies, norms, cuOpt solves: what the System-CUDA classes do, with their shapes) as CudaTraceEntry, each timed on the host and, for work queued on the device, on the device by a pair of CUDA events read when done; and every call of a binding (CudaLibraryAPI check:in:), counted by C function. Off, a traced operation costs a test of a class variable.

	CudaTrace start.
	(CudaMatrix uniformRows: 512 cols: 512) * (CudaMatrix uniformRows: 512 cols: 512).
	CudaTrace default entries.
	CudaTrace default calls.     "C function -> count"
	CudaTrace stop'!

!CudaTrace class methodsFor: 'tracing'!
default
	^Default ifNil: [Default := self new]
!
start
	"Record from now on."
	self default.
	Tracing := true
!
stop
	Tracing := false
!
isOn
	^Tracing == true
!
reset
	Default := nil
!
operation: aString detail: aBlock during: workBlock
	"Run workBlock; while tracing, record it as aString with aBlock's description of it (evaluated only then) and its times, the device's too."
	Tracing == true ifFalse: [^workBlock value].
	^self default operation: aString detail: aBlock value device: true during: workBlock
!
hostOperation: aString detail: aBlock during: workBlock
	"The same for work that is done when it returns (a copy, a solve): its host time is its time."
	Tracing == true ifFalse: [^workBlock value].
	^self default operation: aString detail: aBlock value device: false during: workBlock
!
call: functionName
	"A binding's call of functionName returned (CudaLibraryAPI check:in:)."
	(Tracing == true and: [Quiet ~~ true]) ifTrue: [self default count: functionName]
!
quietly: aBlock
	"Run aBlock without counting its calls: my own events."
	| was |
	was := Quiet.
	Quiet := true.
	^aBlock ensure: [Quiet := was]
! !

!CudaTrace methodsFor: 'initialization'!
initialize
	entries := OrderedCollection new.
	limit := 200.
	calls := Dictionary new.
	since := Time millisecondClockValue.
	lock := Semaphore forMutualExclusion
! !

!CudaTrace methodsFor: 'recording'!
operation: aString detail: detailString device: aBoolean during: workBlock
	| entry start result |
	entry := CudaTraceEntry new name: aString detail: detailString.
	start := (aBoolean and: [CudaRuntimeAPI isAvailable])
		ifTrue: [self class quietly: [[CudaEvent new record; yourself] on: CudaError do: [:e | nil]]]
		ifFalse: [nil].
	entry startAt: Time microsecondClockValue.
	[result := workBlock value]
		ensure: [
			entry stopAt: Time microsecondClockValue.
			start isNil ifFalse: [self class quietly: [entry start: start stop: ([CudaEvent new record; yourself] on: CudaError do: [:e | nil])]].
			self add: entry].
	^result
!
add: anEntry
	lock critical: [
		entries addLast: anEntry.
		[entries size > limit] whileTrue: [self class quietly: [entries removeFirst release]]]
!
count: functionName
	lock critical: [| c |
		c := calls at: functionName ifAbsent: [nil].
		c isNil ifTrue: [calls at: functionName put: (c := Array with: 0 with: 0)].
		c at: 1 put: (c at: 1) + 1.
		c at: 2 put: Time millisecondClockValue]
!
clear
	lock critical: [
		self class quietly: [entries do: [:e | e release]].
		entries := OrderedCollection new.
		calls := Dictionary new.
		since := Time millisecondClockValue]
! !

!CudaTrace methodsFor: 'accessing'!
entries
	"The recorded operations, oldest first (their device times read where done)."
	| copy |
	lock critical: [copy := entries asArray].
	self class quietly: [copy do: [:e | e resolve]].
	^copy
!
recent: n
	| all |
	all := self entries.
	^(all copyFrom: (all size - n + 1 max: 1) to: all size) reverse
!
calls
	"C function name -> number of calls since tracing started (or clear)."
	| d |
	d := Dictionary new.
	lock critical: [calls keysAndValuesDo: [:k :v | d at: k put: v first]].
	^d
!
callsByCount
	"{name. count. millisecond clock of the last call} for every function called, the most called first."
	| list |
	list := OrderedCollection new.
	lock critical: [calls keysAndValuesDo: [:k :v | list add: (Array with: k with: v first with: v last)]].
	^(list asSortedCollection: [:a :b | (a at: 2) > (b at: 2) or: [(a at: 2) = (b at: 2) and: [(a at: 1) <= (b at: 1)]]]) asArray
!
callCount
	| n |
	n := 0.
	lock critical: [calls do: [:v | n := n + v first]].
	^n
!
since
	^since
!
limit: anInteger
	limit := anInteger
! !
