ClassDescription subclass: #Metaclass
	instanceVariableNames: 'thisClass'
	classVariableNames: ''
	package: 'Kernel-Classes'!

Metaclass comment: 'I am the class of a class. Each class has its own metaclass with exactly one instance, thisClass; class-side methods and class-side instance variables live in me. My field order is fixed by the VM.'!

!Metaclass methodsFor: 'accessing'!
thisClass
	^thisClass
!
soleInstance
	^thisClass
!
instanceClass
	^thisClass
!
theNonMetaClass
	^thisClass
!
name
	thisClass isNil ifTrue: [^'a Metaclass'].
	^thisClass name, ' class'
!
classPool
	^thisClass classPool
!
sharedPools
	^thisClass sharedPools
!
bindingOf: aSymbol
	^thisClass bindingOf: aSymbol
!
subclasses
	"Answer the metaclasses of my sole instance's subclasses."
	thisClass isNil ifTrue: [^#()].
	^thisClass subclasses collect: [:c | c class]
! !

!Metaclass methodsFor: 'private'!
thisClass: aClass
	thisClass := aClass
! !

!Metaclass methodsFor: 'testing'!
isMeta
	^true
! !

!Metaclass methodsFor: 'instance creation'!
new
	"Classes are created with subclass:instanceVariableNames:... and are unique."
	^self error: 'A metaclass has exactly one instance'
! !
