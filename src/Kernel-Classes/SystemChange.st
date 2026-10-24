Object subclass: #SystemChange
	instanceVariableNames: 'kind behavior selector oldMethod newMethod'
	classVariableNames: ''
	package: 'Kernel-Classes'!

SystemChange comment: 'I describe one change to the system, announced by SystemChanges: kind is #methodAdded, #methodChanged, #methodRemoved or #classDefined; behavior is the class or metaclass changed; for methods also selector and the old and new CompiledMethod (nil when absent).'!

!SystemChange methodsFor: 'accessing'!
kind
	^kind
!
behavior
	^behavior
!
theClass
	"The instance side of the changed behavior."
	^behavior instanceSide
!
selector
	^selector
!
oldMethod
	^oldMethod
!
newMethod
	^newMethod
!
isMethodChange
	^selector notNil
! !

!SystemChange methodsFor: 'testing'!
affects: aClass
	"Answer true if I changed aClass or one of its subclasses (instance or class side)."
	^self theClass == aClass or: [self theClass inheritsFrom: aClass]
!
affectsAnyOf: aCollection
	^aCollection anySatisfy: [:each | self affects: each]
!
isInPackageNamed: aString
	^self theClass packageName = aString
! !

!SystemChange methodsFor: 'private'!
setKind: aSymbol behavior: aBehavior selector: aSelectorOrNil old: oldOrNil new: newOrNil
	kind := aSymbol.
	behavior := aBehavior.
	selector := aSelectorOrNil.
	oldMethod := oldOrNil.
	newMethod := newOrNil
! !

!SystemChange methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a SystemChange('; nextPutAll: kind; space; print: behavior.
	selector isNil ifFalse: [aStream nextPutAll: '>>'; nextPutAll: selector].
	aStream nextPut: $)
! !

!SystemChange class methodsFor: 'instance creation'!
kind: aSymbol behavior: aBehavior selector: aSelectorOrNil old: oldOrNil new: newOrNil
	^self new setKind: aSymbol behavior: aBehavior selector: aSelectorOrNil old: oldOrNil new: newOrNil
! !
