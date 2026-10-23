Object subclass: #UndefinedObject
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Objects'!

UndefinedObject comment: 'I have a single instance, nil: the value of uninitialized variables and the answer of "nothing". I am also the superclass of root classes and the end of every handler search.'!

!UndefinedObject methodsFor: 'testing'!
isNil
	^true
!
notNil
	^false
!
isEmptyOrNil
	^true
!
ifNil: nilBlock
	^nilBlock value
!
ifNotNil: notNilBlock
	^nil
!
ifNil: nilBlock ifNotNil: notNilBlock
	^nilBlock value
!
ifNotNil: notNilBlock ifNil: nilBlock
	^nilBlock value
!
isLiteral
	^true
! !

!UndefinedObject methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'nil'
!
storeOn: aStream
	aStream nextPutAll: 'nil'
! !

!UndefinedObject methodsFor: 'copying'!
shallowCopy
	^self
!
deepCopy
	^self
! !

!UndefinedObject methodsFor: 'class hierarchy'!
subclass: aSymbol instanceVariableNames: ivars classVariableNames: cvars package: aString
	"Create a root class (one without superclass)."
	^ClassBuilder new
		superclass: nil
		subclass: aSymbol
		instanceVariableNames: ivars
		classVariableNames: cvars
		package: aString
		type: #normal
!
subclasses
	^#()
!
allSubclassesDo: aBlock
!
canUnderstand: aSymbol
	^false
!
handleSignal: exception
	"No handler was found: run the exception's default action and resume with its value."
	^exception resumeUnchecked: exception defaultAction
! !

!UndefinedObject class methodsFor: 'instance creation'!
new
	^self error: 'There is only one nil'
!
basicNew
	^self error: 'There is only one nil'
! !
