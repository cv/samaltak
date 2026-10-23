Object subclass: #Boolean
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Objects'!

Boolean comment: 'I am the abstract class of the two truth values true and false. The compiler inlines my conditionals when their arguments are literal blocks; the methods here are used otherwise (perform:, non-literal block arguments).'!

!Boolean methodsFor: 'logical operations'!
& aBoolean
	self subclassResponsibility
!
| aBoolean
	self subclassResponsibility
!
not
	self subclassResponsibility
!
==> aBlock
	"Material implication."
	^self not or: [aBlock value]
!
eqv: aBoolean
	^self == aBoolean
!
xor: aBoolean
	^(self == aBoolean value) not
! !

!Boolean methodsFor: 'controlling'!
and: aBlock
	self subclassResponsibility
!
or: aBlock
	self subclassResponsibility
!
and: block1 and: block2
	^(self and: [block1 value]) and: [block2 value]
!
or: block1 or: block2
	^(self or: [block1 value]) or: [block2 value]
!
ifTrue: aBlock
	self subclassResponsibility
!
ifFalse: aBlock
	self subclassResponsibility
!
ifTrue: trueBlock ifFalse: falseBlock
	self subclassResponsibility
!
ifFalse: falseBlock ifTrue: trueBlock
	self subclassResponsibility
! !

!Boolean methodsFor: 'testing'!
isBoolean
	^true
!
isLiteral
	^true
! !

!Boolean methodsFor: 'copying'!
shallowCopy
	^self
!
deepCopy
	^self
! !

!Boolean methodsFor: 'printing'!
storeOn: aStream
	self printOn: aStream
! !

!Boolean class methodsFor: 'instance creation'!
new
	^self error: 'There are only true and false'
!
basicNew
	^self error: 'There are only true and false'
! !
