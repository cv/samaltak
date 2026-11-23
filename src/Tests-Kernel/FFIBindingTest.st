TestCase subclass: #FFIBindingTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

!FFIBindingTest class methodsFor: 'accessing'!
testSelectors
	Machine hasFirmware ifTrue: [
		^#(testInvalidDescriptors testUnregisteredExportsAndMismatchedSignatures testFreestandingBindingsAreDenied)].
	^super testSelectors reject: [:selector | selector == #testFreestandingBindingsAreDenied]
! !

!FFIBindingTest methodsFor: 'tests'!
testFreestandingBindingsAreDenied
	#((call 'libm' 'sqrt' (f64) f64)
	  (call 'libc' 'memcmp' (byteSlice byteSlice u64) i32)
	  (notification vsync coalesce 2 1)
	  (notification sdlLog queued dropNewestAndCount 1 (category priority messageBytes) 1)
	  (notification external 'fixture' 'subscribe' (u32 context u64) i32)) do: [:descriptor |
		self should: [FFI bind: descriptor] raise: FFIError]
!
testLiteralAndComputedDescriptors
	| literal computed descriptor |
	literal := FFI bind: #(call 'libm' 'sqrt' (f64) f64).
	descriptor := {#call. #libm. 'sq', 'rt'. {#f64}. #f64}.
	computed := FFI bind: descriptor.
	self assert: (literal invoke: #(9.0)) equals: 3.0.
	self assert: (computed invoke: {16.0}) equals: 4.0
!
testMixedArgumentTypes
	| bind |
	bind := FFI bind: #(call 'libm' 'ldexp' (f64 i32) f64).
	self assert: (bind invoke: #(1.25 -3)) equals: 0.15625.
	self assert: (bind invoke: #(1.25 4)) equals: 20.0
!
testBindingKeepsItsOwnNamesAndSignature
	| library symbol types descriptor binding |
	library := 'libm' copy.
	symbol := 'sqrt' copy.
	types := {#f64}.
	descriptor := {#call. library. symbol. types. #f64}.
	binding := FFI bind: descriptor.
	library at: 1 put: $x.
	symbol at: 1 put: $x.
	types at: 1 put: #i32.
	descriptor at: 5 put: #i32.
	Smalltalk vm garbageCollect.
	self assert: (binding invoke: #(25.0)) equals: 5.0
!
testInvalidDescriptors
	#(nil
	  ()
	  (unknown)
	  ('call' 'libm' 'sqrt' (f64) f64)
	  (call 'libm' 'sqrt')
	  (call '' 'sqrt' (f64) f64)
	  (call 'libm' 17 (f64) f64)
	  (call 'libm' 'sqrt' f64 f64)
	  (call 'libm' 'sqrt' (f64 f64 f64 f64 f64 f64 f64) f64)
	  (call 'libm' 'sqrt' ('f64') f64)
	  (call 'libm' 'sqrt' (void) f64)
	  (call 'libm' 'sqrt' (ptr) f64)
	  (call 'libm' 'sqrt' (f64) byteSlice)
	  (call 'libc' 'getenv' (cText) ownedText)
	  (call 'fixture' 'write' (countedText) void)
	  (call 'vm:core' 'core_stdout_text' (countedText countedText) void)
	  (call 'vm:core' 'core_stdout_text' (countedText) i32)
	  (call 'vm:core' 'core_getenv_text' (cText) void)
	  (call 'vm:core' 'core_getenv_text' (ownedText) cText)) do: [:descriptor |
		self should: [FFI bind: descriptor] raise: FFIError].
	self should: [FFI bind: {#call. 'libm'. 'sqrt', (String with: Character null). #(f64). #f64}]
		raise: FFIError.
	self should: [FFI bind: #(call 'libm' '√' (f64) f64)] raise: FFIError.
	self should: [FFI bind: {#call. 'libm'. String new: 128. #(f64). #f64}] raise: FFIError
!
testUnregisteredExportsAndMismatchedSignatures
	#((call 'not-a-granted-library' 'sqrt' (f64) f64)
	  (call 'libm' 'pow' (f64 f64) f64)
	  (call 'libc' 'memcmp' (byteSlice byteSlice u32) i32)
	  (call 'libm' 'sqrt' (i32) f64)
	  (call 'libm' 'sqrt' (f64) void)) do: [:descriptor |
		self should: [FFI bind: descriptor] raise: FFIError]
!
testInvalidArguments
	| bind |
	bind := FFI bind: #(call 'libm' 'ldexp' (f64 i32) f64).
	self should: [bind invoke: nil] raise: FFIError.
	self should: [bind invoke: #(2.0)] raise: FFIError.
	self should: [bind invoke: #(2.0 1 1)] raise: FFIError.
	self should: [bind invoke: #('2.0' 1)] raise: FFIError.
	self should: [bind invoke: #(2.0 2147483648)] raise: FFIError
!
testPlatformInvocationDistinguishesRejectionFromZero
	| binding |
	self assert: (PlatformFFI bind: #(call 'not-a-granted-library' 'missing' () void)) isNil.
	binding := PlatformFFI bind: #(call 'libm' 'ilogb' (f64) i32).
	self assert: (binding tryInvoke: #(1.0)) identicalTo: 0.
	self assert: (binding tryInvoke: #(1)) identicalTo: false.
	self assert: (binding tryInvoke: #()) identicalTo: false.
	self assert: (binding tryInvoke: nil) identicalTo: false.
	self assert: (binding tryInvoke1: 1.0) identicalTo: 0.
	self assert: (binding tryInvoke1: 1) identicalTo: false.
	self assert: binding tryInvoke0 identicalTo: false.
	self assert: (binding tryInvoke2: 1.0 with: 1.0) identicalTo: false.
	self assert: (binding tryInvoke1: 2.0) identicalTo: 1
!
testUninitializedBinding
	| binding |
	binding := FFIBinding new.
	self assert: (binding tryInvoke: #()) identicalTo: false.
	self assert: (binding tryInvoke1: 1) identicalTo: false.
	self should: [binding invoke: #()] raise: FFIError
!
testCompareByteSlices
	| compare left right |
	compare := FFI bind: #(call 'libc' 'memcmp' (byteSlice byteSlice u64) i32).
	left := {#[255 10 0 20]. 2. 3}.
	right := {#[10 0 30 254]. 1. 3}.
	self assert: (compare invoke: {left. right. 2}) equals: 0.
	self assert: (compare invoke: {left. right. 3}) < 0.
	self assert: (compare invoke: {right. left. 3}) > 0.
	self assert: (compare invoke: {{#[1]. 2. 0}. {#[]. 1. 0}. 0}) equals: 0.
	self assert: (compare tryInvoke3: left with: right with: 2) identicalTo: 0.
	self assert: (compare tryInvoke3: left with: right with: 4) identicalTo: false
!
testRejectInvalidByteSlices
	| compare goodSlice |
	compare := FFI bind: #(call 'libc' 'memcmp' (byteSlice byteSlice u64) i32).
	goodSlice := {#[1 2 3]. 1. 2}.
	self should: [compare invoke: {goodSlice. goodSlice. 3}] raise: FFIError.
	self should: [compare invoke: {goodSlice. goodSlice. -1}] raise: FFIError.
	self should: [compare invoke: {goodSlice. {#[1]. 1. 1}. 2}] raise: FFIError.
	self should: [compare invoke: {{#[1]. 0. 1}. goodSlice. 1}] raise: FFIError.
	self should: [compare invoke: {{#[1]. 1. 2}. goodSlice. 1}] raise: FFIError.
	self should: [compare invoke: {{#[1]. 2. 1}. goodSlice. 1}] raise: FFIError.
	self should: [compare invoke: {{#[1]. 1. -1}. goodSlice. 0}] raise: FFIError.
	self should: [compare invoke: {{'a'. 1. 1}. goodSlice. 1}] raise: FFIError.
	self should: [compare invoke: {16rDEADBEEF. goodSlice. 1}] raise: FFIError
! !
