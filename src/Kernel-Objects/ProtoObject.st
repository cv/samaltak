nil subclass: #ProtoObject
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Objects'!

ProtoObject comment: 'I am the root of the class hierarchy. I define the minimal protocol every object needs: identity, the identity hash and message-not-understood handling. Proxies subclass me directly so that almost every message reaches their doesNotUnderstand:.'!

!ProtoObject methodsFor: 'comparing'!
== anObject
	"Answer whether the receiver and anObject are the same object. Never sent: the compiler emits a bytecode."
	<primitive: 'identical'>
	self primitiveFailed
!
~~ anObject
	"Answer whether the receiver and anObject are different objects."
	^(self == anObject) not
!
identityHash
	"Answer a SmallInteger kept in the object header. It never changes, even when the object moves."
	<primitive: 'identityHash'>
	self primitiveFailed
! !

!ProtoObject methodsFor: 'testing'!
isNil
	^false
!
notNil
	^true
!
ifNil: nilBlock
	^self
!
ifNotNil: notNilBlock
	^notNilBlock numArgs = 0
		ifTrue: [notNilBlock value]
		ifFalse: [notNilBlock value: self]
!
ifNil: nilBlock ifNotNil: notNilBlock
	^notNilBlock numArgs = 0
		ifTrue: [notNilBlock value]
		ifFalse: [notNilBlock value: self]
!
ifNotNil: notNilBlock ifNil: nilBlock
	^notNilBlock numArgs = 0
		ifTrue: [notNilBlock value]
		ifFalse: [notNilBlock value: self]
! !

!ProtoObject methodsFor: 'system primitives'!
doesNotUnderstand: aMessage
	"The VM sends me when a message is not understood. Answer the value the failed send should answer."
	^(MessageNotUnderstood new)
		message: aMessage;
		receiver: self;
		signal
!
initialize
	"Subclasses override to initialize new instances; Behavior>>new sends me."
!
primitiveFailed
	"A primitive failed and the method has no fallback code."
	^PrimitiveFailed new
		selector: thisContext sender selector;
		signal
!
becomeForward: otherObject
	"All references to the receiver now point to otherObject."
	<primitive: 'becomeForward'>
	^PrimitiveFailed new selector: #becomeForward:; signal
! !
