Object subclass: #FirmwareVariablesTestStub
	instanceVariableNames: 'values resets'
	classVariableNames: ''
	package: 'Tests-Storage'!

FirmwareVariablesTestStub comment: 'I stand in for FirmwareVariables in FirmwareBootTest: global variables in a Dictionary, resets counted.'!

!FirmwareVariablesTestStub methodsFor: 'initialization'!
initialize
	values := Dictionary new.
	resets := 0
! !

!FirmwareVariablesTestStub methodsFor: 'variables'!
names
	^(values keys asSortedCollection collect: [:k | k -> FirmwareVariables globalGuid]) asArray
!
at: aName
	^values at: aName ifAbsent: [nil]
!
at: aName put: aByteArray
	aByteArray isEmpty ifTrue: [values removeKey: aName ifAbsent: [nil]] ifFalse: [values at: aName put: aByteArray copy].
	^aByteArray
!
removeKey: aName
	values removeKey: aName ifAbsent: [nil]
!
resetCold
	resets := resets + 1
!
resets
	^resets
! !
