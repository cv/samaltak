TestCase subclass: #CoreBytesFFITest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

CoreBytesFFITest comment: 'The VM''s typed byte exports (vm:core, docs/ffi-fork.md) through their descriptors: what they answer, and the arguments and signatures they refuse.'!

!CoreBytesFFITest methodsFor: 'tests'!
mismatch
	^FFI bind: #(call 'vm:core' 'core_bytes_mismatch' (rawBytesWithLength i64 rawBytesWithLength i64 i64) i64)
!
lastMismatch
	^FFI bind: #(call 'vm:core' 'core_bytes_last_mismatch' (rawBytesWithLength i64 rawBytesWithLength i64 i64) i64)
!
testMismatch
	| a b |
	a := (0 to: 99) asByteArray.
	b := a copy.
	b at: 20 put: 0; at: 70 put: 1.
	self assert: (self mismatch invoke: {a. 1. b. 1. 100}) equals: 20.
	self assert: (self mismatch invoke: {a. 21. b. 21. 49}) equals: 0.
	self assert: (self mismatch invoke: {a. 101. b. 101. 0}) equals: 0.
	self assert: (self lastMismatch invoke: {a. 1. b. 1. 100}) equals: 70.
	self assert: (self lastMismatch invoke: {a. 1. b. 1. 69}) equals: 20.
	self assert: (self lastMismatch invoke: {a. 21. a. 21. 80}) equals: 0
!
testMismatchOfWords
	"A Bitmap's words are its bytes as the CPU stores them (little-endian)."
	| w |
	w := Bitmap new: 2.
	w at: 1 put: 16r03020100; at: 2 put: 16r07060504.
	self assert: (self mismatch invoke: {(0 to: 7) asByteArray. 1. w. 1. 8}) equals: 0.
	self assert: (self mismatch invoke: {#[0 1 2 3 4 5 6 9]. 1. w. 1. 8}) equals: 8.
	self assert: (self lastMismatch invoke: {w. 1. #[9 1 2 3 4 5 6 7]. 1. 8}) equals: 1
!
testRangesOutsideAnswerMinusOne
	| a |
	a := ByteArray new: 10.
	#(#(0 1 1) #(1 0 1) #(1 1 -1) #(2 1 10) #(1 2 10) #(12 1 0)) do: [:r |
		self assert: (self mismatch invoke: {a. r first. a. r second. r third}) equals: -1.
		self assert: (self lastMismatch invoke: {a. r first. a. r second. r third}) equals: -1]
!
testRefusedArguments
	"Not a slice: the object itself; and no pointer objects, immediates or non-Integers."
	| a |
	a := ByteArray new: 4.
	{{{a. 1. 4}. 1. a. 1. 4}. {#(1 2 3 4). 1. a. 1. 4}. {a. 1. 3. 1. 4}. {a. 1. nil. 1. 4}. {a. 1. a. 1. 4.0}. {a. nil. a. 1. 4}} do: [:args |
		self should: [self mismatch invoke: args] raise: FFIError.
		self assert: (self mismatch tryInvoke: args) equals: false]
!
testSignaturesAreExact
	self should: [FFI bind: #(call 'vm:core' 'core_bytes_mismatch' (bytesWithLength i64 bytesWithLength i64 i64) i64)] raise: FFIError.
	self should: [FFI bind: #(call 'vm:core' 'core_bytes_mismatch' (rawBytesWithLength i64 rawBytesWithLength i64 i64) i32)] raise: FFIError.
	self should: [FFI bind: #(call 'vm:core' 'core_bytes_mismatch' (writableRawBytesWithLength i64 rawBytesWithLength i64 i64) i64)] raise: FFIError
!
testRawBytesOnlyForApprovedExports
	"A launcher grant or the fixed libc rows never take a raw object; neither is a result type."
	self should: [FFI bind: #(call 'demo' 'demo_sum' (u64 rawBytesWithLength) u64)] raise: FFIError.
	self should: [FFI bind: #(call 'libc' 'memcmp' (rawBytesWithLength rawBytesWithLength u64) i32)] raise: FFIError.
	self should: [FFI bind: #(call 'vm:core' 'core_bytes_mismatch' (i64) rawBytesWithLength)] raise: FFIError
!
testByteArrayUsesTheExports
	| a b |
	a := (0 to: 99) asByteArray.
	b := a copy.
	b at: 40 put: 0.
	self assert: (a indexOfMismatchAt: 1 with: b at: 1 size: 100) equals: 40.
	self assert: (a lastIndexOfMismatchAt: 1 with: b at: 1 size: 100) equals: 40.
	self assert: (a indexOfMismatchAt: 1 with: b at: 1 size: 39) equals: 0.
	self assert: (a indexOfMismatchAt: 1 with: #(0 1 7) at: 1 size: 3) equals: 3.
	self should: [a indexOfMismatchAt: 1 with: b at: 2 size: 100] raise: Error.
	self should: [a lastIndexOfMismatchAt: 0 with: b at: 1 size: 1] raise: Error
! !
