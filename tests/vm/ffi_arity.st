Object subclass: #FFIArityProof
	instanceVariableNames: ''
	classVariableNames: 'Approved Bindings Calls'
	package: 'FFIArityProof'!

!FFIArityProof class methodsFor: 'signatures'!
signatures
	"Name, argument types, result: tests/vm/ffi_arity_fixture.c's launcher grants and the approved ffi_test_arity* exports
	 (whose arity8 slice is writable). Past six integer or eight floating-point lanes they use the stack."
	^#(
		(arity7 (i32 i64 u32 u64 i32 i64 i32) u64)
		(arity8 (i32 i64 i32 i64 i32 i64 i32 bytesWithLength) u64)
		(arity9 (i32 i64 i32 i64 i32 bytesWithLength f64 f32 i64) f32)
		(arity14 (u64 i32 i32 i32 i32 i32 bytesWithLength u64 i32 u64 i32 bytesWithLength u64 i32) u64)
		(arity16 (f64 i32 f32 i64 f64 u32 f32 u64 f64 i32 f32 i64 f64 i32 f32 f64) f64))
!
typesOf: row
	| types |
	types := row second copy.
	(Approved and: [row first == #arity8]) ifTrue: [types at: 8 put: #writableBytesWithLength].
	^types
!
bind: approved
	Approved := approved.
	Bindings := IdentityDictionary new.
	self signatures do: [:row |
		Bindings at: row first put: (FFI bind: {#call.
			approved ifTrue: ['vm:core'] ifFalse: ['arity'].
			(approved ifTrue: ['ffi_test_'] ifFalse: ['']) , row first.
			self typesOf: row.
			row third})].
	approved ifFalse: [Calls := FFI bind: #(call 'arity' 'arity_calls' () u32)]
! !

!FFIArityProof class methodsFor: 'expected'!
mix: h with: v
	^((h bitXor: v) * 16r100000001B3) bitAnd: 16rFFFFFFFFFFFFFFFF
!
lane: x type: type
	"The 64 bits the natives hash for an argument."
	| b |
	type == #f64 ifTrue: [^x asIEEEBits bitAnd: 16rFFFFFFFFFFFFFFFF].
	type == #f32 ifTrue: [
		b := ByteArray new: 4.
		b float32At: 1 put: x.
		^b uint32At: 1].
	^x bitAnd: 16rFFFFFFFFFFFFFFFF
!
hash: args types: types
	| h |
	h := 16rCBF29CE484222325.
	1 to: args size do: [:k | | a |
		a := args at: k.
		(types at: k) == #bytesWithLength | ((types at: k) == #writableBytesWithLength)
			ifTrue: [
				(a at: 2) to: (a at: 2) + (a at: 3) - 1 do: [:i | h := self mix: h with: ((a at: 1) at: i)].
				h := self mix: h with: (a at: 3)]
			ifFalse: [h := self mix: h with: (self lane: a type: (types at: k))]].
	^h
!
expect: name args: args types: types
	| h |
	h := self hash: args types: types.
	name == #arity9 ifTrue: [^(h bitAnd: 16rFFFFFF) asFloat].
	name == #arity16 ifTrue: [^(h bitShift: -11) asFloat].
	^h
!
value: type at: k iteration: n
	"Different in every lane and iteration, with each type's limits now and then."
	| m bytes |
	m := n * 31 + (k * 7).
	type == #i32 ifTrue: [
		m \\ 11 = 0 ifTrue: [^m even ifTrue: [-2147483648] ifFalse: [2147483647]].
		^(m * 7919) \\ 2000001 - 1000000].
	type == #u32 ifTrue: [m \\ 11 = 0 ifTrue: [^4294967295]. ^m * 104729 \\ 4294967296].
	type == #i64 ifTrue: [
		m \\ 13 = 0 ifTrue: [^m even ifTrue: [-9223372036854775808] ifFalse: [9223372036854775807]].
		^(m * 16r12345678) negated + k].
	type == #u64 ifTrue: [m \\ 13 = 0 ifTrue: [^18446744073709551615]. ^16rFEDCBA9876543210 - m].
	type == #f64 ifTrue: [^(m * 0.25) - 1000.5].
	type == #f32 ifTrue: [^(m \\ 4096) * 0.5 - 1000.25].
	bytes := ByteArray new: 9.
	1 to: 9 do: [:i | bytes at: i put: (m + i) * 37 \\ 256].
	^{bytes. m \\ 3 + 1. m \\ 6}
!
argumentsFor: types iteration: n
	^(1 to: types size) collect: [:k | self value: (types at: k) at: k iteration: n]
! !

!FFIArityProof class methodsFor: 'calls'!
positional: name args: a
	"One send site per arity: optimized code binds each to the wrapper."
	| b |
	b := Bindings at: name.
	name == #arity7 ifTrue: [
		^b tryInvoke7: (a at: 1) with: (a at: 2) with: (a at: 3) with: (a at: 4) with: (a at: 5) with: (a at: 6) with: (a at: 7)].
	name == #arity8 ifTrue: [
		^b tryInvoke8: (a at: 1) with: (a at: 2) with: (a at: 3) with: (a at: 4) with: (a at: 5) with: (a at: 6) with: (a at: 7)
			with: (a at: 8)].
	name == #arity9 ifTrue: [
		^b tryInvoke9: (a at: 1) with: (a at: 2) with: (a at: 3) with: (a at: 4) with: (a at: 5) with: (a at: 6) with: (a at: 7)
			with: (a at: 8) with: (a at: 9)].
	name == #arity14 ifTrue: [
		^b tryInvoke14: (a at: 1) with: (a at: 2) with: (a at: 3) with: (a at: 4) with: (a at: 5) with: (a at: 6) with: (a at: 7)
			with: (a at: 8) with: (a at: 9) with: (a at: 10) with: (a at: 11) with: (a at: 12) with: (a at: 13) with: (a at: 14)].
	^b tryInvoke16: (a at: 1) with: (a at: 2) with: (a at: 3) with: (a at: 4) with: (a at: 5) with: (a at: 6) with: (a at: 7)
		with: (a at: 8) with: (a at: 9) with: (a at: 10) with: (a at: 11) with: (a at: 12) with: (a at: 13) with: (a at: 14)
		with: (a at: 15) with: (a at: 16)
!
case: row iteration: n array: useArray
	"{row. arguments. expected result. array?. the writable slice's bytes before}"
	| types args slice |
	types := self typesOf: row.
	args := self argumentsFor: types iteration: n.
	slice := (types includes: #writableBytesWithLength) ifTrue: [args at: (types indexOf: #writableBytesWithLength)].
	^{row. args. self expect: row first args: args types: types. useArray. slice ifNotNil: [slice first copy]}
!
call: case
	^(case at: 4)
		ifTrue: [(Bindings at: (case at: 1) first) invoke: (case at: 2)]
		ifFalse: [self positional: (case at: 1) first args: (case at: 2)]
!
check: case result: result
	| slice before |
	result = (case at: 3) ifFalse: [
		self error: (case at: 1) first , ((case at: 4) ifTrue: [' invoke: '] ifFalse: [' positional: ']) , 'answered ' ,
			result printString , ', not ' , (case at: 3) printString , ' for ' , (case at: 2) printString].
	before := case at: 5.
	before ifNil: [^self].
	slice := (case at: 2) at: ((self typesOf: (case at: 1)) indexOf: #writableBytesWithLength).
	1 to: before size do: [:i |
		(slice first at: i) = ((i between: slice second and: slice second + slice third - 1)
			ifTrue: [(before at: i) + 1 \\ 256] ifFalse: [before at: i])
				ifFalse: [self error: (case at: 1) first , ': wrong writable bytes']]
!
rejections
	"Wrong values in stack lanes reject before the native entry."
	| count a |
	count := Calls ifNotNil: [Calls invoke: #()].
	a := self argumentsFor: #(i32 i64 u32 u64 i32 i64 i32) iteration: 1.
	a at: 7 put: 2147483648.
	(self positional: #arity7 args: a) == false ifFalse: [self error: 'arity7 took an out-of-range i32 stack lane'].
	a at: 7 put: 1.5.
	(self positional: #arity7 args: a) == false ifFalse: [self error: 'arity7 took a Float i32 stack lane'].
	a := self argumentsFor: (self typesOf: self signatures fourth) iteration: 2.
	a at: 13 put: -1.
	(self positional: #arity14 args: a) == false ifFalse: [self error: 'arity14 took a negative u64 stack lane'].
	a := self argumentsFor: (self typesOf: self signatures fourth) iteration: 3.
	a at: 12 put: {ByteArray new: 2. 2. 5}.
	(self positional: #arity14 args: a) == false ifFalse: [self error: 'arity14 took an oversized slice'].
	a := self argumentsFor: (self signatures at: 5) second iteration: 4.
	a at: 16 put: 3.
	(self positional: #arity16 args: a) == false ifFalse: [self error: 'arity16 took an Integer f64 stack lane'].
	a at: 16 put: 1.0.
	a at: 15 put: nil.
	(self positional: #arity16 args: a) == false ifFalse: [self error: 'arity16 took nil for an f32 lane'].
	[(Bindings at: #arity16) invoke: a. self error: 'invoke: took nil for an f32 lane'] on: FFIError do: [:e | ].
	(Calls notNil and: [(Calls invoke: #()) ~= count]) ifTrue: [self error: 'a rejected call entered the native'].
	[FFI bind: #(call 'arity' 'arity7' (i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32) i32).
	 self error: 'seventeen arguments bound'] on: FFIError do: [:e | ].
	[FFI bind: #(call 'arity' 'arity7' (i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 bytesWithLength) i32).
	 self error: 'seventeen C slots bound'] on: FFIError do: [:e | ]
!
run: approved iterations: count
	"Every signature positionally (a bound site once optimized) and every eighth call through an Array.
	 The calls run apart from the arithmetic computing their arguments and results."
	| cases results |
	self bind: approved.
	cases := OrderedCollection new.
	1 to: count do: [:n |
		self signatures do: [:row |
			cases add: (self case: row iteration: n array: false).
			n \\ 8 = 0 ifTrue: [cases add: (self case: row iteration: n + 1000 array: true)]]].
	results := cases collect: [:case | self call: case].
	cases with: results do: [:case :result | self check: case result: result].
	self rejections.
	Calls ifNotNil: [
		(Calls invoke: #()) = (count * 5 + (count // 8 * 5)) ifFalse: [self error: 'wrong native call count']].
	^true
!
witness: approved iterations: count
	"Only the float-result signatures, with fixed arguments and no LargeInteger arithmetic in the loop
	 (whose own FFI calls would blur the bound-site counters): ffi_arity_test.sh counts the hits."
	| a9 a16 r9 r16 |
	self bind: approved.
	a9 := self argumentsFor: (self typesOf: (self signatures at: 3)) iteration: 5.
	a16 := self argumentsFor: (self typesOf: (self signatures at: 5)) iteration: 5.
	r9 := self positional: #arity9 args: a9.
	r16 := self positional: #arity16 args: a16.
	(r9 isFloat and: [r16 isFloat]) ifFalse: [self error: 'witness calls failed'].
	2 to: count do: [:n |
		((self positional: #arity9 args: a9) = r9 and: [(self positional: #arity16 args: a16) = r16])
			ifFalse: [self error: 'witness calls changed']].
	^true
! !
