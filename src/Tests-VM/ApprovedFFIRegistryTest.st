TestCase subclass: #ApprovedFFIRegistryTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

!ApprovedFFIRegistryTest methodsFor: 'fixtures'!
withNativeFixture: sources do: aBlock
	| selectors module |
	selectors := OrderedCollection new.
	[
		sources do: [:s |
			selectors add: (Compiler compile: s in: FFIPrimitives classified: 'test only') selector].
		module := (VMTranslator modules: {FFIPrimitives} header: 'test')
			moduleFor: FFIPrimitives.
		aBlock value: (selectors collect: [:sel | module functionAt: sel])]
		ensure: [selectors do: [:sel | FFIPrimitives removeSelector: sel]]
! !

!ApprovedFFIRegistryTest methodsFor: 'tests'!
testDeclarationFoldsStableID
	self withNativeFixture: #('ffiRegistryTest: n
		<function>
		<approvedFFI: 3999 symbol: ''ffi_registry_test'' arguments: #(3) result: 3>
		<var: #n type: ''int64_t''>
		<returns: ''int64_t''>
		^n')
		do: [:functions |
			| row |
			row := (TApprovedFFI fromFunctions: functions) first.
			self assert: row id equals: 5023.
			self assert: row owner equals: 'FFIPrimitives'.
			self assert: row name equals: 'ffi_registry_test']
!
testPrototypeMismatchRejected
	self withNativeFixture: #('ffiRegistryTest: n
		<function>
		<approvedFFI: 3999 symbol: ''ffi_registry_test'' arguments: #(3) result: 3>
		<var: #n type: ''oop''>
		<returns: ''int64_t''>
		^0')
		do: [:functions | [
			TApprovedFFI fromFunctions: functions]
				on: TranslationError
				do: [:e | self assert: (e messageText includesSubstring: 'argument tag does not match'). ^self].
			self fail]
!
testDuplicateIDRejected
	self withNativeFixture: #('ffiRegistryTest
		<function>
		<approvedFFI: 3999 symbol: ''ffi_registry_test'' arguments: #() result: 3>
		<returns: ''int64_t''>
		^1'
		'ffiRegistryTestOther
		<function>
		<approvedFFI: 3999 symbol: ''ffi_registry_test_other'' arguments: #() result: 3>
		<returns: ''int64_t''>
		^2')
		do: [:functions | self should: [TApprovedFFI fromFunctions: functions] raise: TranslationError]
!
sourceWithSlots: n
	"An approved export of n parameters: a float, then int64s."
	| s |
	s := WriteStream on: String new.
	s nextPutAll: 'ffiRegistryTest: a1'.
	2 to: n do: [:i | s nextPutAll: ' with: a'; print: i].
	s nextPutAll: '
	<function>
	<approvedFFI: 3999 symbol: ''ffi_registry_test'' arguments: #(16'.
	2 to: n do: [:i | s nextPutAll: ' 3'].
	s nextPutAll: ') result: 16>
	<var: #a1 type: ''float''>'.
	2 to: n do: [:i | s nextPutAll: '
	<var: #a'; print: i; nextPutAll: ' type: ''int64_t''>'].
	s nextPutAll: '
	<returns: ''float''>
	^a1'.
	^s contents
!
testSixteenSlotsAccepted
	self withNativeFixture: {self sourceWithSlots: 16}
		do: [:functions | self assert: (TApprovedFFI fromFunctions: functions) first id equals: 5023]
!
testSeventeenSlotsRejected
	self withNativeFixture: {self sourceWithSlots: 17}
		do: [:functions | self should: [TApprovedFFI fromFunctions: functions] raise: TranslationError]
!
testRawBytesTakeTwoSlots
	"rawBytesWithLength (17) is a read-only address and a byte size, writableRawBytesWithLength (18) a writable one."
	self withNativeFixture: #('ffiRegistryTest: a size: n into: b size: m
		<function>
		<approvedFFI: 3999 symbol: ''ffi_registry_test'' arguments: #(17 18) result: 3>
		<var: #a type: ''const uint8_t *''>
		<var: #n type: ''uint64_t''>
		<var: #b type: ''uint8_t *''>
		<var: #m type: ''uint64_t''>
		<returns: ''int64_t''>
		^0')
		do: [:functions | self assert: (TApprovedFFI fromFunctions: functions) first id equals: 5023]
!
testReadOnlyRawBytesAreConst
	self withNativeFixture: #('ffiRegistryTest: a size: n
		<function>
		<approvedFFI: 3999 symbol: ''ffi_registry_test'' arguments: #(17) result: 3>
		<var: #a type: ''uint8_t *''>
		<var: #n type: ''uint64_t''>
		<returns: ''int64_t''>
		^0')
		do: [:functions | self should: [TApprovedFFI fromFunctions: functions] raise: TranslationError]
! !
