ByteArray variableByteSubclass: #WritableFFIBytesSubclass
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'WritableFFIProof'!

Array variableSubclass: #WritableFFIArraySubclass
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'WritableFFIProof'!

Object subclass: #WritableFFIProof
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'WritableFFIProof'!

!WritableFFIProof class methodsFor: 'invoking'!
binding
	^FFI bind: #(call 'vm:core' 'ffi_test_writable_pair' (writableBytesWithLength f64 i32 writableBytesWithLength) i64)
!
positional: binding first: first marker: marker status: status second: second
	^binding tryInvoke4: first with: marker with: status with: second
!
legacyBind: library symbol: symbol types: types result: result
	<primitive: 'ffiBind'>
	^#denied
!
legacyInvoke: id library: library symbol: symbol types: types result: result arguments: arguments
	<primitive: 'ffiInvoke'>
	^#denied
! !

!WritableFFIProof class methodsFor: 'checks'!
require: condition description: description
	condition ifFalse: [self error: description]
!
reject: aBlock
	^[aBlock value. false] on: FFIError do: [:error | true]
!
checkBinding: binding
	| a b first second |
	a := #[10 11 12 13 14] copy.
	b := #[20 21 22 23 24 25 26 27 28] copy.
	first := {a. 2. 3}.
	second := {b. 7. 2}.
	first beReadOnlyObject.
	self require: (binding invoke: {first. 1.25. -3. second}) = (-16r7000000000000000 + 47)
		description: 'Array path: wrong signed result, marker or lengths'.
	self require: (a = #[10 12 13 14 14] and: [b = #[20 21 22 23 24 25 28 29 28]])
		description: 'Array path wrote outside the selected ranges or did not enter once'.
	self require: (self positional: binding first: first marker: 1.25 status: -71 second: second) == -71
		description: 'positional path: a completed error status must not reject'.
	self require: (a = #[10 13 14 15 14] and: [b = #[20 21 22 23 24 25 30 31 28]])
		description: 'positional path wrote outside the selected ranges or replayed an error'.
	self require: (binding invoke: {{a. 6. 0}. 1.25. 0. {ByteArray new: 0. 1. 0}}) = -16r7000000000000000
		description: 'empty slice at end or empty ByteArray'.
	self require: a = #[10 13 14 15 14] description: 'empty slice wrote bytes'.
	self require: (binding invoke: {first. 1.25. -71. {a. 4. 1}}) == -71
		description: 'overlapping slices on the same ByteArray'.
	self require: a = #[10 14 15 18 14] description: 'writable ranges must alias original storage'
!
checkRejections: binding
	| a b first second immutable subSlice max |
	a := #[10 11 12 13 14] copy.
	b := #[20 21 22 23 24] copy.
	first := {a. 2. 3}.
	second := {b. 2. 2}.
	immutable := #[1 2 3] copy.
	immutable beReadOnlyObject.
	max := SmallInteger maxVal.
	subSlice := WritableFFIArraySubclass new: 3.
	subSlice at: 1 put: b; at: 2 put: 1; at: 3 put: 2.
	{nil. 1. subSlice. #(). first, {1}. {a. 1}. {nil. 1. 0}.
		{immutable. 1. 0}. {immutable. 1. 1}.
		{WritableFFIBytesSubclass new: 2. 1. 2}. {'bytes'. 1. 1}. {#(1 2). 1. 2}.
		{a. nil. 2}. {a. 1. nil}. {a. 0. 0}. {a. -1. 2}. {a. 1. -1}. {a. 2. 5}.
		{a. 6. 1}. {a. 7. 0}. {a. 1. 1.0}. {a. 1.25. 1}.
		{a. 1. max}. {a. max. max}. {a. max. 0}. {a. 1. max + 1}. {a. max + 1. 0}.
		{a. 1. 16rFFFFFFFFFFFFFFFF}. {ByteArray new: 0. 2. 0}} do: [:bad |
		self require: (self reject: [binding invoke: {bad. 1.25. 0. second}])
			description: 'Array path accepted invalid first slice'.
		self require: (self positional: binding first: first marker: 1.25 status: 0 second: bad) == false
			description: 'positional path accepted invalid final slice'.
		self require: (a = #[10 11 12 13 14] and: [b = #[20 21 22 23 24]])
			description: 'target entered with an invalid slice'].
	self require: immutable = #[1 2 3] description: 'wrote to read-only storage'.
	{nil. 1. '1.25'} do: [:bad |
		self require: (self reject: [binding invoke: {first. bad. 0. second}])
			description: 'Array path accepted invalid f64'].
	{nil. true. 2147483648. -2147483649. 16r8000000000000000} do: [:bad |
		self require: (self positional: binding first: first marker: 1.25 status: bad second: second) == false
			description: 'positional path accepted invalid i32'].
	{nil. #(). {first. 1.25. 0}. {first. 1.25. 0. second. 0}} do: [:bad |
		self require: (self reject: [binding invoke: bad]) description: 'logical arity must be exact'].
	self require: (a = #[10 11 12 13 14] and: [b = #[20 21 22 23 24]])
		description: 'target entered with an invalid scalar or argument Array'
!
checkAuthorization
	| args a b tags oversized library symbol oversizedTags |
	a := #[10 11] copy.
	b := #[20 21] copy.
	args := {{a. 1. 2}. 1.25. 0. {b. 1. 2}}.
	tags := #[9 6 1 9].
	self require: (self legacyBind: 'vm:core' symbol: 'ffi_test_writable_pair' types: tags result: 3) == #denied
		description: '250 accepted a prepared-only row'.
	self require: (self legacyInvoke: 5119 library: 'vm:core' symbol: 'ffi_test_writable_pair' types: tags result: 3 arguments: args) == #denied
		description: '251 accepted a prepared-only row'.
	self require: (self reject: [FFI bind: #(call 'vm:core' 'ffi_test_writable_pair' (bytesWithLength f64 i32 writableBytesWithLength) i64)])
		description: 'writable row weakens to a read-only signature'.
	self require: (self reject: [FFI bind: #(call 'libc' 'memcmp' (writableBytesWithLength byteSlice u64) i32)])
		description: 'libc gained writable authority'.
	self require: (self reject: [FFI bind: #(call 'vm:core' 'ffi_test_writable_pair' () writableBytesWithLength)])
		description: 'writable used as result'.
	self require: (self reject: [FFI bind: #(call 'vm:core' 'ffi_test_writable_pair' (writableBytesWithLength f64 i32 writableBytesWithLength u64) i64)])
		description: 'descriptor with seven ABI lanes'.
	library := 'vm:core' copy.
	symbol := 'ffi_test_writable_pair' copy.
	oversizedTags := #[9 6 1 9 4] copy.
	library beReadOnlyObject.
	symbol beReadOnlyObject.
	oversizedTags beReadOnlyObject.
	oversized := {library. symbol. oversizedTags. 3}.
	oversized beReadOnlyObject.
	self require: (FFIBinding new initializeDescriptor: oversized) prepare == false
		description: 'forged internal descriptor with seven ABI lanes'.
	self require: (a = #[10 11] and: [b = #[20 21]]) description: 'denied route entered target'
!
boxing: binding
	| before a b first second answer after |
	before := Smalltalk vm statistics fullGCs.
	1 to: 36 do: [:i |
		"Fresh young inputs; keep the ByteArrays live across the result GC."
		a := #[10 11 12 13 14] copy.
		b := #[20 21 22 23 24] copy.
		first := {a. 2. 2}.
		second := {b. 4. 2}.
		answer := self positional: binding first: first marker: 1.25 status: i second: second.
		self require: answer = (-16r7000000000000000 + 34 + i) description: 'box after positional borrow'.
		answer := binding invoke: {first. 1.25. i. second}.
		self require: answer = (-16r7000000000000000 + 34 + i) description: 'box after Array borrow'.
		self require: (a = #[10 13 14 13 14] and: [b = #[20 21 22 27 28]])
			description: 'mutation lost after movement or native entry replayed'].
	after := Smalltalk vm statistics fullGCs.
	self require: after - before >= 72 description: 'post-native allocation did not run full GC'
!
run
	| binding |
	binding := self binding.
	self checkBinding: binding.
	self checkRejections: binding.
	self checkAuthorization.
	self boxing: binding.
	"Same positional send site when hot: execute rejection and completion, no retry."
	self checkBinding: binding.
	self checkRejections: binding.
	^true
! !
