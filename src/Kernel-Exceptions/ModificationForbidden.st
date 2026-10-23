Error subclass: #ModificationForbidden
	instanceVariableNames: 'object fieldIndex newValue retrySelector'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

ModificationForbidden comment: 'I am signaled when code tries to store newValue into field fieldIndex of a read-only object (see Object>>beReadOnlyObject). A handler can make the object writable and send retryModification, which performs the store and resumes; watchpoints work this way.'!

!ModificationForbidden methodsFor: 'accessing'!
object
	^object
!
object: anObject
	object := anObject
!
fieldIndex
	^fieldIndex
!
fieldIndex: anInteger
	fieldIndex := anInteger
!
newValue
	^newValue
!
newValue: anObject
	newValue := anObject
!
retrySelector
	^retrySelector
!
retrySelector: aSymbol
	retrySelector := aSymbol
!
messageText
	^messageText ifNil: [
		'Modification forbidden: ', object class name, ' instance is read-only'
			, (fieldIndex isNil ifTrue: [''] ifFalse: [' (field ', fieldIndex printString, ')'])]
! !

!ModificationForbidden methodsFor: 'retrying'!
retryModification
	"Perform the forbidden store again (the object should be writable by now) and resume."
	fieldIndex isNil
		ifTrue: [object perform: retrySelector with: newValue]
		ifFalse: [object perform: retrySelector with: fieldIndex with: newValue].
	self resumeUnchecked: newValue
! !

!ModificationForbidden methodsFor: 'testing'!
isResumable
	^true
! !
