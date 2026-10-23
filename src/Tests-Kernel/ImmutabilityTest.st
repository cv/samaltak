TestCase subclass: #ImmutabilityTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

ImmutabilityTest comment: 'Tests read-only objects: literals, beReadOnlyObject, ModificationForbidden for indexed and instance variable stores, and retryModification.'!

!ImmutabilityTest methodsFor: 'tests'!
testLiteralsAreReadOnly
	self assert: #(1 2 3) isReadOnlyObject.
	self assert: 'literal' isReadOnlyObject.
	self deny: 'literal' copy isReadOnlyObject.
	self should: [#(1 2 3) at: 1 put: 9] raise: ModificationForbidden.
	self should: ['abc' at: 1 put: $x] raise: ModificationForbidden
!
testBeReadOnly
	| a |
	a := Array new: 3.
	self deny: a isReadOnlyObject.
	self deny: a beReadOnlyObject.
	self assert: a isReadOnlyObject.
	self should: [a at: 1 put: 1] raise: ModificationForbidden.
	self assert: a beWritableObject.
	a at: 1 put: 1.
	self assert: a first = 1
!
testInstanceVariableStore
	| assoc |
	assoc := 1 -> 2.
	assoc beReadOnlyObject.
	self should: [assoc value: 3] raise: ModificationForbidden.
	self assert: assoc value = 2.
	self assert: ([assoc value: 3] on: ModificationForbidden do: [:e |
		e object == assoc and: [e fieldIndex = 2 and: [e newValue = 3]]])
!
testRetryModification
	| assoc a |
	assoc := 1 -> 2.
	assoc beReadOnlyObject.
	[assoc value: 3] on: ModificationForbidden do: [:e |
		e object beWritableObject.
		e retryModification].
	self assert: assoc value = 3.
	a := Array new: 2.
	a beReadOnlyObject.
	self assert: ([a at: 2 put: #x] on: ModificationForbidden do: [:e |
		a beWritableObject.
		e retryModification]) = #x.
	self assert: (a at: 2) = #x
!
testResumeSkipsStore
	| assoc |
	assoc := 1 -> 2.
	assoc beReadOnlyObject.
	[assoc value: 3] on: ModificationForbidden do: [:e | e resume: nil].
	self assert: assoc value = 2
!
testMessageText
	self assert: ([#(1) at: 1 put: 2] on: ModificationForbidden do: [:e | e messageText])
		= 'Modification forbidden: Array instance is read-only (field 1)'
! !
