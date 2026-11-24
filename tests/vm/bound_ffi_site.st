Object subclass: #BoundFFISiteProof
	instanceVariableNames: 'count'
	classVariableNames: ''
	package: 'BoundFFISiteProof'!

Object subclass: #BoundFFIAlternateReceiver
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'BoundFFISiteProof'!

!BoundFFIAlternateReceiver methodsFor: 'testing'!
tryInvoke1: n
	^n + 100
! !

!FFIBinding methodsFor: 'fixture-only selector'!
fixtureStep: n
	<primitive: 'ffiBoundInvoke'>
	^false
! !

!BoundFFISiteProof class methodsFor: 'running'!
saveWitness: path
	| resumed |
	"File-in runs before the snapshot, with tracing off. On resume, bypass
	startup/shutdown hooks so only the witness uses the positional primitive."
	resumed := Smalltalk primSnapshot: path.
	resumed == false ifTrue: [^#saved].
	resumed == true ifFalse: [self error: 'could not save witness image'].
	[
		| route |
		route := self new initialize witness.
		"Array invoke keeps logging out of the positional counters."
		(FFI bind: #(call 'vm:core' 'core_stdout_text' (countedText) void))
			invoke: {route, (String with: Character lf)}.
		Smalltalk primQuit: 0
	] on: Error do: [:e |
		Smalltalk vm stderrWrite: e messageText, (String with: Character lf).
		Smalltalk primQuit: 1]
!
leaf
	^self new initialize runLeaf
!
boxing
	^self new initialize runBoxing
!
reuse
	^self new initialize runSlotReuse
!
deopt: requireDeopt
	^self new initialize runDeopt: requireDeopt
!
snapshot: path
	^self new initialize snapshot: path
! !

!BoundFFISiteProof methodsFor: 'testing'!
initialize
	count := FFI bind: #(call 'wrapped' 'wrapped_calls' () u32)
!
require: aBoolean description: description
	aBoolean ifFalse: [self error: description]
!
step
	^FFI bind: #(call 'wrapped' 'wrapped_step' (i32) i32)
!
other
	^FFI bind: #(call 'wrapped' 'wrapped_other' (i32) i32)
!
nativeCount
	"Do not use the positional primitive under test when measuring its bypass."
	^count invoke: #()
! !

!BoundFFISiteProof methodsFor: 'machine-code witness'!
fixtureSite: binding n: n
	^binding fixtureStep: n
!
witness
	| binding other answer before code |
	binding := self step.
	other := self other.
	before := self nativeCount.
	1 to: 4096 do: [:i | answer := self fixtureSite: binding n: i].
	self require: answer = -4095 description: 'alias native target'.
	self require: (self fixtureSite: other n: 9) = 29 description: 'alias same-class identity miss'.
	self require: (self fixtureSite: binding n: 1) == 0 description: 'alias return-zero hit'.
	self require: (self fixtureSite: binding n: nil) == false description: 'alias rejection, without retry'.
	self require: self nativeCount = (before + 4098) description: 'alias exact native entry count'.
	"Inspect the same compiler note as the annotated disassembly, without
	running the disassembler (which itself uses bound FFI)."
	code := (BoundFFISiteProof >> #fixtureSite:n:) jitCode: #opt.
	self require: (code notNil and: [(code at: 6) = 'opt']) description: 'no optimized caller code'.
	^((code at: 4) includes: 'bound FFI site: direct wrapper')
		ifTrue: ['witness direct wrapper']
		ifFalse: ['witness ordinary send']
! !

!BoundFFISiteProof methodsFor: 'leaf call sites'!
mono: binding argument: n
	^binding tryInvoke1: n
!
mixedReceiver: binding argument: n
	^binding tryInvoke1: n
!
zeroArgs: binding
	^binding tryInvoke0
!
warm: binding
	| answer |
	1 to: 4000 do: [:i | answer := self mono: binding argument: i].
	self require: answer = -3999 description: 'warming dynamic receiver'
!
runLeaf
	| binding other void impostor forged before vm token |
	vm := Smalltalk vm.
	binding := self step.
	other := self other.
	void := FFI bind: #(call 'wrapped' 'wrapped_void' () void).
	impostor := BoundFFIAlternateReceiver new.
	self require: binding class == other class description: 'alternate native target must be same class'.
	self warm: binding.
	before := self nativeCount.
	1 to: 128 do: [:i |
		self require: (self mono: binding argument: i) = (1 - i) description: 'monomorphic dynamic argument'].
	self require: (self mono: binding argument: 1.0) == false description: 'wrapper rejection returns false'.
	self require: (self mono: binding argument: 2147483648) == false description: 'wrapper rejects i32 overflow'.
	self require: self nativeCount = (before + 128) description: 'monomorphic target exactly once, including zero'.
	before := self nativeCount.
	self require: (self mono: other argument: 7) = 27 description: 'abrupt exact-identity miss to different target'.
	self require: (self mono: impostor argument: 3) = 103 description: 'abrupt receiver-class miss'.
	self require: (self mono: binding argument: 7) = -6 description: 'original binding after abrupt misses'.
	self require: self nativeCount = (before + 2) description: 'miss native calls or replay'.
	before := self nativeCount.
	1 to: 4000 do: [:i |
		self require: (self mixedReceiver: binding argument: i) = (1 - i) description: 'polymorphic first target'.
		self require: (self mixedReceiver: other argument: i) = (i + 20) description: 'polymorphic same-class target'.
		self require: (self mixedReceiver: impostor argument: i) = (i + 100) description: 'polymorphic alternate class'].
	self require: self nativeCount = (before + 8000) description: 'polymorphic native calls exactly once'.
	before := self nativeCount.
	4000 timesRepeat: [
		self require: (self zeroArgs: void) isNil description: 'void never becomes failure'].
	self require: self nativeCount = (before + 4000) description: 'void replay'.
	self warm: binding.
	vm scavenge.
	vm garbageCollect.
	before := self nativeCount.
	self require: (self mono: binding argument: 13) = -12 description: 'moved binding or wrapper after GC'.
	token := binding instVarNamed: 'bindingToken'.
	forged := FFIBinding new.
	forged instVarNamed: 'bindingToken' put: token.
	forged initializeDescriptor: (other instVarNamed: 'descriptor').
	self require: (self mono: forged argument: 13) == false description: 'copied live token must be rejected'.
	self require: self nativeCount = (before + 1) description: 'wrong/current owner entry count'.
	self methodChange: binding.
	self thaw: binding using: other.
	self unprepared: other.
	^true
!
coldSite: binding n: n
	^binding tryInvoke1: n
!
unprepared: ready
	| invalid binding before |
	invalid := FFIBinding new initializeDescriptor: #().
	1000 timesRepeat: [
		self require: (self coldSite: invalid n: 7) == false description: 'cold invalid descriptor warmup'].
	binding := FFIBinding new initializeDescriptor: (ready instVarNamed: 'descriptor').
	before := self nativeCount.
	self require: (self coldSite: binding n: 9) = 29 description: 'first optimized send must prepare normally'.
	1 to: 128 do: [:i |
		self require: (self coldSite: binding n: i) = (i + 20) description: 'previously unprepared owner'].
	self require: self nativeCount = (before + 129) description: 'cold prepare lost or replayed call'
!
methodChange: binding
	| original before |
	self warm: binding.
	before := self nativeCount.
	original := FFIBinding compiledMethodAt: #tryInvoke1:.
	[
		Compiler compile: 'tryInvoke1: n ^n + 1000' in: FFIBinding.
		self require: (self mono: binding argument: 9) = 1009 description: 'method replacement must not enter previous wrapper'.
		self require: self nativeCount = before description: 'native entry after method replacement'
	] ensure: [FFIBinding addSelector: #tryInvoke1: withMethod: original].
	self require: (self mono: binding argument: 9) = -8 description: 'method restored'.
	self require: self nativeCount = (before + 1) description: 'restored method native count'
!
thaw: binding using: other
	| before token |
	self warm: binding.
	before := self nativeCount.
	token := binding instVarNamed: 'bindingToken'.
	self require: binding beWritableObject description: 'binding not frozen before thaw'.
	self require: (self mono: binding argument: 9) == false description: 'thawed exact owner must miss/reject'.
	binding instVarNamed: 'descriptor' put: #().
	binding beReadOnlyObject.
	self require: (self mono: binding argument: 9) == false description: 'invalid descriptor must not reuse old wrapper'.
	self require: self nativeCount = before description: 'thawed or invalid descriptor entered native'.
	binding beWritableObject.
	binding initializeDescriptor: (other instVarNamed: 'descriptor').
	self require: (self mono: binding argument: 9) = 29 description: 'same identity with new descriptor/target'.
	self require: (self mono: binding argument: 11) = 31 description: 'warmed new target'.
	self require: (binding instVarNamed: 'bindingToken') ~= token description: 'thaw must expire session token'.
	self require: self nativeCount = (before + 2) description: 'rebound native count'
! !

!BoundFFISiteProof methodsFor: 'weak owner slot reuse'!
reuseSite: binding n: n
	^binding tryInvoke1: n
!
seedTemporaryOwner
	| binding weak answer |
	binding := self step.
	weak := WeakArray new: 1.
	weak at: 1 put: binding.
	4000 timesRepeat: [answer := self reuseSite: binding n: 7].
	self require: answer = -6 description: 'old slot target'.
	^{binding instVarNamed: 'bindingToken'. weak}
!
runSlotReuse
	| old binding before occupied |
	old := self seedTemporaryOwner.
	Smalltalk vm garbageCollect.
	self require: old second first isNil description: 'bound site must not retain its owner'.
	"Earlier slots may also have died during GC: occupy them before reusing this one."
	occupied := OrderedCollection new.
	[
		binding := self other.
		occupied add: binding.
		(binding instVarNamed: 'bindingToken') ~= old first and: [occupied size < 64]
	] whileTrue.
	self require: (binding instVarNamed: 'bindingToken') = old first
		description: 'expected reused slot with same-session token: old ', old first printString, ' new ', (binding instVarNamed: 'bindingToken') printString.
	before := self nativeCount.
	self require: (self reuseSite: binding n: 7) = 27 description: 'reused slot must not invoke old wrapper'.
	self require: (self reuseSite: binding n: 8) = 28 description: 'new publication at reused slot'.
	self require: self nativeCount = (before + 2) description: 'slot reuse exact side effects'.
	^true
! !

!BoundFFISiteProof methodsFor: 'allocating call sites'!
wide: binding n: n keep: kept
	| answer |
	answer := binding tryInvoke1: n.
	^kept first == kept second ifTrue: [answer] ifFalse: [#lostRoot]
!
wideUnsigned: binding with: args keep: kept
	| answer |
	answer := binding tryInvoke6: args first with: args second with: args third
		with: args fourth with: (args at: 5) with: (args at: 6).
	^kept first == kept second ifTrue: [answer] ifFalse: [#lostRoot]
!
floating: binding n: n keep: kept
	| answer |
	answer := binding tryInvoke6: n with: 0.0 with: 0.0 with: 0.0 with: 0.0 with: 0.0.
	^kept first == kept second ifTrue: [answer] ifFalse: [#lostRoot]
!
mixedReturns: signed unsigned: unsigned float: float wide: min positive: max number: big args: args
	| fresh keep a b c |
	fresh := ByteArray new: 29.
	fresh at: 17 put: 101.
	keep := {fresh. fresh}.
	a := self wide: signed n: min keep: keep.
	b := self wideUnsigned: unsigned with: args keep: keep.
	c := self floating: float n: big keep: keep.
	"Both arguments and earlier results are live across later, possibly collecting calls."
	^(a = min and: [b = max and: [c = big and: [(fresh at: 17) = 101]]])
!
runBoxing
	| signed unsigned float min max big args keep vm initial before delta forced warmups repeats |
	vm := Smalltalk vm.
	forced := (vm getenv: 'SAMALTAK_FFI_BOX_FULL_GC') notNil.
	warmups := forced ifTrue: [40] ifFalse: [3000].
	repeats := forced ifTrue: [8] ifFalse: [60000].
	signed := FFI bind: #(call 'wrapped' 'wrapped_signed' (i64) i64).
	unsigned := FFI bind: #(call 'wrapped' 'wrapped_mixed' (i32 f64 u64 i64 u32 f64) u64).
	float := FFI bind: #(call 'wrapped' 'wrapped_floats' (f64 f64 f64 f64 f64 f64) f64).
	min := 16r8000000000000000 negated.
	max := 16rFFFFFFFFFFFFFFFE.
	big := 1.0e200.
	args := {-1. 0.25. max. min + 1. 16rFFFFFFFE. -0.125}.
	keep := {args. args}.
	warmups timesRepeat: [
		self require: (self mixedReturns: signed unsigned: unsigned float: float wide: min positive: max number: big args: args)
			description: 'warming boxed return sites'].
	before := self nativeCount.
	vm scavenge.
	initial := vm statistics.
	repeats timesRepeat: [
		self require: (self mixedReturns: signed unsigned: unsigned float: float wide: min positive: max number: big args: args)
			description: 'boxed return or live root corrupted'].
	delta := vm statistics - initial.
	self require: delta gcCount > 0 description: 'no GC during boxing stress (run with --eden 1)'.
	forced ifTrue: [
		self require: delta fullGCs >= (3 * repeats) description: 'no full GC in native result boxing'].
	self require: self nativeCount = (before + (3 * repeats)) description: 'boxing GC replayed or skipped native call'.
	before := self nativeCount.
	self require: (self wide: signed n: min keep: keep) = min description: 'boxed signed'.
	self require: (self wide: signed n: 0 keep: keep) == 0 description: 'immediate signed zero at same site'.
	self require: (self wide: signed n: nil keep: keep) == false description: 'allocating signature rejection'.
	self require: (self floating: float n: 1.25 keep: keep) = 1.25 description: 'immediate float at same site'.
	self require: (self floating: float n: big keep: keep) class == BoxedFloat64 description: 'boxed float at same site'.
	self require: self nativeCount = (before + 4) description: 'mixed immediate and boxed results must not replay'.
	^true
! !

!BoundFFISiteProof methodsFor: 'post-call and process boundaries'!
nativeThenAdd: binding marker: marker
	^(binding tryInvoke1: 3) + marker
!
runDeopt: requireDeopt
	| step signed min args before initial delta |
	step := self step.
	signed := FFI bind: #(call 'wrapped' 'wrapped_signed' (i64) i64).
	min := 16r8000000000000000 negated.
	args := {min. min}.
	before := self nativeCount.
	initial := Smalltalk vm statistics.
	4000 timesRepeat: [
		self require: (self nativeThenAdd: step marker: 7) = 5 description: 'arithmetic after native entry'.
		self require: (self wide: signed n: min keep: args) = min description: 'boxed return across deopt'].
	self require: (self nativeThenAdd: step marker: 0.25) = -1.75 description: 'changed type after native entry'.
	delta := Smalltalk vm statistics - initial.
	requireDeopt ifTrue: [
		self require: delta optDeoptimizations > 0 description: 'no stress deoptimization'].
	self require: self nativeCount = (before + 8001) description: 'deopt replay at original send PC'.
	^true
!
snapshot: path
	| binding other before expected |
	binding := self step.
	other := self other.
	self warm: binding.
	self require: (self mono: other argument: 6) = 26 description: 'warm both descriptors before snapshot'.
	(Smalltalk snapshot: path) ifTrue: [
		expected := (Smalltalk vm getenv: 'SITEFFI_SNAPSHOT_DENIED') isNil ifTrue: [-8] ifFalse: [false].
		before := self nativeCount.
		self require: (self mono: binding argument: 9) == expected description: 'restored descriptor or removed grant'.
		self require: (self mono: other argument: 9) = 29 description: 'restored same-class alternate target'.
		self require: (self mono: binding argument: 11) == (expected == false ifTrue: [false] ifFalse: [-10])
			description: 'warmed restored owner/token'.
		self require: self nativeCount = (before + (expected == false ifTrue: [1] ifFalse: [3]))
			description: 'saved wrapper replay or old target entry'.
		^#restored].
	^#saved
! !
