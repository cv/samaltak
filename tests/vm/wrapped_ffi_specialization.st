Object subclass: #WrappedFFIProof
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'WrappedFFIProof'!

!WrappedFFIProof class methodsFor: 'testing'!
require: condition description: description
	condition ifFalse: [self error: description]
!
reject: aBlock
	^[aBlock value. false] on: FFIError do: [:error | true]
!
scalars
	| step other mixed floats signed count void probe maxUnsigned minSigned maxU32 big before n |
	step := FFI bind: #(call 'wrapped' 'wrapped_step' (i32) i32).
	other := FFI bind: #(call 'wrapped' 'wrapped_other' (i32) i32).
	mixed := FFI bind: #(call 'wrapped' 'wrapped_mixed' (i32 f64 u64 i64 u32 f64) u64).
	floats := FFI bind: #(call 'wrapped' 'wrapped_floats' (f64 f64 f64 f64 f64 f64) f64).
	signed := FFI bind: #(call 'wrapped' 'wrapped_signed' (i64) i64).
	count := FFI bind: #(call 'wrapped' 'wrapped_calls' () u32).
	void := FFI bind: #(call 'wrapped' 'wrapped_void' () void).
	probe := FFI bind: #(call 'wrapped' 'wrapped_prove_target' (i32) i32).
	self require: (probe tryInvoke1: -17) == -17 description: 'executed packet lacks fixed target or inline boxing'.
	self require: (probe invoke: #(3125)) == 3125 description: 'array must use the same fixed-target path'.
	maxUnsigned := (1 bitShift: 64) - 1.
	minSigned := (1 bitShift: 63) negated.
	maxU32 := (1 bitShift: 32) - 1.
	big := 1.0e200.
	self require: big class == BoxedFloat64 description: 'expected boxed Float'.
	self require: (step tryInvoke1: 1) == 0 description: 'native zero is success'.
	self require: (other tryInvoke1: 1) == 21 description: 'same signature uses a distinct target'.
	self require: void tryInvoke0 isNil description: 'native void is success'.
	self require: (floats invoke: {big. 1.0. -2.0. 3.0. -4.0. 5.0}) = big description: 'boxed Float result'.
	self require: (count invoke: #()) = 4 description: 'each native target entered once'.
	self require: (signed invoke: {minSigned}) = minSigned description: 'large signed return'.
	self require: (signed invoke: {minSigned negated - 1}) = (minSigned negated - 1) description: 'large positive signed return'.
	self rejectedScalars: step mixed: mixed signed: signed count: count.
	before := Smalltalk vm statistics.
	"Warm tuples are all different. Alternate public Array and direct sends."
	n := 0.
	2048 timesRepeat: [
		n := n + 1.
		self require: (self callMixed: mixed n: n unsigned: maxUnsigned signed: minSigned u32: maxU32)
			description: 'mixed GP/FP lanes or wide integer conversion'.
		self require: (self callFloat: floats n: n) description: 'six FP lanes or return'.
		self require: (step tryInvoke1: n negated) = (n + 1) description: 'dynamic scalar'].
	self require: (count invoke: #()) = (6 + (3 * n)) description: 'lost or replayed native side effect'.
	self tokens: step other: other count: count.
	self deoptProbe: step count: count.
	^Smalltalk vm statistics - before
!
deoptProbe: step count: count
	| before result |
	before := count tryInvoke0.
	512 timesRepeat: [result := self nativeThenAdd: step marker: 7].
	self require: result = 5 description: 'warm speculative addition after native entry'.
	result := self nativeThenAdd: step marker: 0.25.
	self require: result = -1.75 description: 'changed type after native entry'.
	self require: count tryInvoke0 = (before + 513) description: 'side effect replay after native call'
!
nativeThenAdd: step marker: marker
	^(step tryInvoke1: 3) + marker
!
callMixed: mixed n: n unsigned: maxUnsigned signed: minSigned u32: maxU32
	| a b c d e f |
	a := n negated.
	b := n asFloat * 0.25.
	c := maxUnsigned - n.
	d := minSigned + n.
	e := maxU32 - n.
	f := n asFloat * -0.125.
	^(n odd
		ifTrue: [mixed tryInvoke6: a with: b with: c with: d with: e with: f]
		ifFalse: [mixed invoke: {a. b. c. d. e. f}]) = c
!
callFloat: floats n: n
	| f |
	f := n asFloat.
	^(floats tryInvoke6: f with: 1.25 with: -2.25 with: 3.125 with: -4.5 with: 5.5) = (f + 122.5)
!
rejectedScalars: step mixed: mixed signed: signed count: count
	| before |
	before := count invoke: #().
	{nil. #(). #(1 2). #[1]. '1'. #(nil). #(1.0). #(true). #($a).
		{-2147483649}. {2147483648}. {16r100000001}} do: [:args |
		self require: (self reject: [step invoke: args]) description: 'array shape, arity, type, or i32 range'].
	self require: (step tryInvoke1: 0.0) == false description: 'direct Float rejected'.
	self require: (step tryInvoke3: 1 with: 1 with: 1) == false description: 'direct arity rejected'.
	self require: (self reject: [signed invoke: {16r8000000000000000}]) description: 'i64 overflow rejected'.
	self require: (self reject: [signed invoke: {16r8000000000000001 negated}]) description: 'i64 underflow rejected'.
	{#(-1 1 2 -3 4 -0.25). #(-1 1.0 -1 -3 4 -0.25).
		{-1. 1.0. 16r10000000000000000. -3. 4. -0.25}.
		#(-1 1.0 2 -3 -1 -0.25). #(-1 1.0 2 -3 4294967296 -0.25).
		#(-1 1.0 2 -3 4 -1)} do: [:args |
		self require: (self reject: [mixed invoke: args]) description: 'mixed type or unsigned overflow'].
	self require: (count invoke: #()) = before description: 'rejections must not enter native code'
!
borrows
	| borrow compare count before bytes other left right args expect |
	borrow := FFI bind: #(call 'wrapped' 'wrapped_borrows' (u64 bytesWithLength bytesWithLength u64) u64).
	compare := FFI bind: #(call 'libc' 'memcmp' (byteSlice byteSlice u64) i32).
	count := FFI bind: #(call 'wrapped' 'wrapped_calls' () u32).
	bytes := #[255 17 18 19 254] copy.
	other := #[17 18 21 253] copy.
	left := {bytes. 2. 3}.
	right := {other. 1. 3}.
	args := {7. left. right. 23}.
	expect := [:seed :prefix :tail | (prefix inject: seed into: [:a :b | a * 33 + b]) + tail].
	self require: (borrow invoke: args) = (expect value: 7 value: #(17 18 19 17 18 21) value: 23)
		description: 'borrow pointer + count in both positions'.
	Smalltalk vm garbageCollect.
	Smalltalk vm scavenge.
	bytes at: 4 put: 22.
	self require: (borrow invoke: args) = (expect value: 7 value: #(17 18 22 17 18 21) value: 23)
		description: 'read moved bytes from current oops'.
	self require: (compare tryInvoke3: left with: right with: 2) = 0 description: 'memcmp prefix'.
	self require: (compare tryInvoke3: left with: right with: 3) > 0 description: 'memcmp order'.
	self require: (compare tryInvoke3: right with: left with: 3) < 0 description: 'memcmp reversed'.
	self require: (compare tryInvoke3: {bytes. 6. 0} with: {ByteArray new: 0. 1. 0} with: 0) = 0
		description: 'memcmp empty end slices'.
	self require: (borrow invoke: {7. {bytes. 6. 0}. {ByteArray new: 0. 1. 0}. 23}) = 30
		description: 'borrow empty end slices'.
	before := count invoke: #().
	{(left copyFrom: 1 to: 2). {bytes. 0. 1}. {bytes. 6. 1}. {bytes. 7. 0}.
		{bytes. 1. -1}. {bytes. 1. 1.0}. {bytes. 1. 16rFFFFFFFFFFFFFFFF}.
		{bytes. 16rFFFFFFFFFFFFFFFF. 1}. {'not ByteArray'. 1. 1}} do: [:bad |
		self require: (self reject: [borrow invoke: {7. left. bad. 23}]) description: 'invalid second borrow'.
		self require: (self reject: [borrow invoke: {7. bad. right. 23}]) description: 'invalid first borrow'].
	self require: (count invoke: #()) = before description: 'borrow rejection entered target'.
	self require: (compare tryInvoke3: left with: right with: -1) == false description: 'negative count'.
	self require: (compare tryInvoke3: left with: right with: 16rFFFFFFFFFFFFFFFF) == false description: 'wide count'.
	self require: (compare tryInvoke3: {bytes. 2. 1} with: right with: 2) == false description: 'left bound'.
	self require: (compare tryInvoke3: left with: {other. 1. 1} with: 2) == false description: 'right bound'
! !

!WrappedFFIProof class methodsFor: 'GC and token proof'!
tokens: step other: other count: count
	| before token forged wrong malformed |
	before := count tryInvoke0.
	token := step instVarNamed: 'bindingToken'.
	self require: token isInteger description: 'expected a prepared token'.
	forged := FFIBinding new.
	forged instVarNamed: 'bindingToken' put: token.
	forged beReadOnlyObject.
	self require: (forged tryInvoke1: 1) == false description: 'copied token without a descriptor'.
	self require: (self reject: [forged invoke: #(1)]) description: 'copied token Array call'.
	self require: count tryInvoke0 = before description: 'copied token entered native target'.
	wrong := FFIBinding new.
	wrong instVarNamed: 'bindingToken' put: token.
	wrong initializeDescriptor: (other instVarNamed: 'descriptor').
	self require: (wrong tryInvoke1: 2) == false description: 'copied current-session token must not retry'.
	self require: (self reject: [wrong invoke: #(2)]) description: 'copied token with a valid descriptor'.
	malformed := FFIBinding new.
	malformed instVarNamed: 'bindingToken' put: #notAToken.
	malformed initializeDescriptor: (other instVarNamed: 'descriptor').
	self require: (malformed tryInvoke1: 2) == false description: 'malformed token must not retry'.
	self require: count tryInvoke0 = before description: 'malformed or copied token entered native target'
!
boxingGC
	| signed count min args direct before stats result countBefore |
	signed := FFI bind: #(call 'wrapped' 'wrapped_signed' (i64) i64).
	count := FFI bind: #(call 'wrapped' 'wrapped_calls' () u32).
	min := (1 bitShift: 63) negated.
	args := {min}.
	self require: (signed tryInvoke1: min) = min description: 'bound direct boxing'.
	self require: (signed invoke: args) = min description: 'bound Array boxing'.
	#(1 2) do: [:mode |
		direct := mode = 1.
		countBefore := count tryInvoke0.
		Smalltalk vm scavenge.
		before := Smalltalk vm statistics.
		"Reuse args and never construct a tuple or numeric value in the loop.
		With 1 MiB eden even one allocation per result must collect."
		90000 timesRepeat: [
			result := direct ifTrue: [signed tryInvoke1: min] ifFalse: [signed invoke: args].
			result = min ifFalse: [self error: 'corrupted boxed signed result']].
		stats := Smalltalk vm statistics - before.
		self require: stats scavenges + stats fullGCs > 0 description: 'allocating native result must trigger GC'.
		self require: count tryInvoke0 = (countBefore + 90000) description: 'boxing GC replayed target']
! !

!WrappedFFIProof class methodsFor: 'PTY'!
pty
	| terminal handle ready selectors classes saved original |
	terminal := PseudoTerminal
		spawn: #('/bin/sh' '-c' 'stty -echo; printf X; while read line; do case "$line" in size) stty size;; quit) exit 0;; esac; done')
		environment: nil directory: nil rows: 24 columns: 80.
	[
		ready := ByteArray new: 1.
		self require: (self read: terminal into: ready) = 1 description: 'child ready byte'.
		self require: ready first = $X asciiValue description: 'child readiness marker'.
		handle := terminal instVarNamed: 'handle'.
		selectors := #(legacyForeground: legacyResize:rows:columns: tryInvoke: invoke:).
		classes := {PseudoTerminal class. PseudoTerminal class. FFIBinding. FFIBinding}.
		saved := selectors with: classes collect: [:selector :class | class compiledMethodAt: selector].
		[
			Compiler compile: 'legacyForeground: h self error: ''unexpected legacy foreground''' in: PseudoTerminal class.
			Compiler compile: 'legacyResize: h rows: r columns: c self error: ''unexpected legacy resize''' in: PseudoTerminal class.
			Compiler compile: 'tryInvoke: args self error: ''unexpected Array invocation''' in: FFIBinding.
			Compiler compile: 'invoke: args self error: ''unexpected Array invocation''' in: FFIBinding.
			self require: (PseudoTerminal primForeground: handle) = terminal pid description: 'foreground wrapper result'.
			self resize: handle rows: 25 columns: 81.
			self requireSize: '25 81' terminal: terminal.
			self require: (self hotPTY: handle pid: terminal pid) > 0 description: 'PTY hot run'.
			self requireSize: '24 80' terminal: terminal
		] ensure: [
			1 to: saved size do: [:i |
				original := saved at: i.
				(classes at: i) addSelector: (selectors at: i) withMethod: original]].
		terminal nextPutAll: 'quit', (String with: Character lf).
		self require: terminal waitForExit = 0 description: 'PTY child exit'
	] ensure: [terminal close].
	self require: (Smalltalk vm platformHandleCounts at: #ptys ifAbsent: [0]) = 0 description: 'PTY cleanup'
!
read: terminal into: buffer
	| count deadline |
	deadline := Time millisecondClockValue + 3000.
	[(count := terminal readInto: buffer) notNil or: [Time millisecondClockValue >= deadline]]
		whileFalse: [terminal semaphore waitTimeoutMSecs: 20].
	^count
!
resize: handle rows: rows columns: columns
	self require: (PseudoTerminal primResize: handle rows: rows columns: columns) == PseudoTerminal
		description: 'resize wrapper result'
!
requireSize: expected terminal: terminal
	| output buffer count deadline |
	terminal nextPutAll: 'size', (String with: Character lf).
	output := ''.
	buffer := ByteArray new: 64.
	deadline := Time millisecondClockValue + 3000.
	[(output includesSubstring: expected) or: [Time millisecondClockValue >= deadline]]
		whileFalse: [
			count := self read: terminal into: buffer.
			(count notNil and: [count > 0]) ifTrue: [output := output, (buffer first: count) asString]].
	self require: (output includesSubstring: expected) description: 'child did not see dimensions ', expected, ': ', output
!
hotPTY: handle pid: pid
	| vm before bytes n result group |
	vm := Smalltalk vm.
	n := 10000.
	"First trip warms both production call sites; the second measures allocation only."
	2 timesRepeat: [
		before := vm statistics bytesAllocated.
		1 to: n do: [:i |
			group := PseudoTerminal primForeground: handle.
			result := PseudoTerminal primResize: handle rows: 24 + (i bitAnd: 1) columns: 80 + (i bitAnd: 1)].
		bytes := vm statistics bytesAllocated - before.
		self require: group = pid description: 'wrong hot foreground result'.
		self require: result == PseudoTerminal description: 'wrong hot resize result'].
	self require: bytes < (n * 4) description: 'PTY wrapper allocated: ', bytes printString.
	^n
! !
