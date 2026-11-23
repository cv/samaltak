TestCase subclass: #FFIBindingTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

!FFIBindingTest methodsFor: 'tests'!
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
	  (call 'libm' 'sqrt' (f64) byteSlice)) do: [:descriptor |
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
testCompareByteSlices
	| compare left right |
	compare := FFI bind: #(call 'libc' 'memcmp' (byteSlice byteSlice u64) i32).
	left := {#[255 10 0 20]. 2. 3}.
	right := {#[10 0 30 254]. 1. 3}.
	self assert: (compare invoke: {left. right. 2}) equals: 0.
	self assert: (compare invoke: {left. right. 3}) < 0.
	self assert: (compare invoke: {right. left. 3}) > 0.
	self assert: (compare invoke: {{#[1]. 2. 0}. {#[]. 1. 0}. 0}) equals: 0
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
