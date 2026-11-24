nil subclass: #ProtoObject
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

ProtoObject subclass: #Object
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Object subclass: #UndefinedObject
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Object subclass: #Boolean
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Boolean subclass: #True
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Boolean subclass: #False
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Object subclass: #Association
	instanceVariableNames: 'key value'
	classVariableNames: ''
	package: 'Mini-Kernel'!

Object subclass: #Message
	instanceVariableNames: 'selector arguments'
	classVariableNames: ''
	package: 'Mini-Kernel'!

Object subclass: #Point
	instanceVariableNames: 'x y'
	classVariableNames: ''
	package: 'Mini-Kernel'!

ProtoObject comment: 'The root.'!

!ProtoObject methodsFor: 'identity'!
== anObject
	<primitive: 'identical'>
	^false
! !

!Object methodsFor: 'basics'!
class
	<primitive: 'class'>
!
identityHash
	<primitive: 'identityHash'>
!
hash
	^self identityHash
!
= anObject
	^self == anObject
!
~= anObject
	^(self = anObject) not
!
~~ anObject
	^(self == anObject) not
!
yourself
	^self
!
isNil
	^false
!
notNil
	^true
!
isString
	^false
!
isSymbol
	^false
!
isInteger
	^false
!
isFloat
	^false
!
isNumber
	^false
!
-> anObject
	^Association new key: self value: anObject
!
basicAt: i
	<primitive: 'at'>
	^self error: 'basicAt: failed'
!
basicAt: i put: v
	<primitive: 'atPut'>
	^self error: 'basicAt:put: failed'
!
at: i
	<primitive: 'at'>
	^self error: 'at: failed'
!
at: i put: v
	<primitive: 'atPut'>
	^self error: 'at:put: failed'
!
basicSize
	<primitive: 'basicSize'>
!
size
	<primitive: 'basicSize'>
!
instVarAt: i
	<primitive: 'instVarAt'>
	^self error: 'instVarAt: failed'
!
instVarAt: i put: v
	<primitive: 'instVarAtPut'>
	^self error: 'instVarAt:put: failed'
!
shallowCopy
	<primitive: 'shallowCopy' error: ec>
	^self error: 'shallowCopy failed ' , ec printString
!
copy
	^self shallowCopy
!
isImmutable
	<primitive: 'isImmutable'>
!
setImmutable: aBoolean
	<primitive: 'setImmutable:'>
!
beImmutable
	self setImmutable: true
!
beMutable
	self setImmutable: false
!
changeClassTo: aClass
	<primitive: 'changeClassTo:'>
	^self error: 'changeClassTo: failed'
!
becomeForward: other
	<primitive: 'becomeForward'>
	^self error: 'becomeForward: failed'
!
perform: aSymbol
	<primitive: 'perform'>
	^self error: 'perform: failed'
!
perform: aSymbol with: a
	<primitive: 'perform'>
	^self error: 'perform:with: failed'
!
perform: aSymbol with: a with: b
	<primitive: 'perform'>
	^self error: 'perform:with:with: failed'
!
perform: aSymbol withArguments: anArray
	<primitive: 'performWithArguments'>
	^self error: 'perform:withArguments: failed'
! !

!Object methodsFor: 'printing'!
printString
	| n |
	n := self class name.
	^((n at: 1) isVowel ifTrue: ['an '] ifFalse: ['a ']) , n
!
displayString
	^self printString
!
printNl
	self printString displayNl
!
displayNl
	self displayString displayNl
!
stdout: aString
	<ffiSite>
	(self ffiSite: #(call 'vm:core' 'core_stdout_text' (countedText) void)) tryInvoke1: aString
!
stderr: aString
	<ffiSite>
	(self ffiSite: #(call 'vm:core' 'core_stderr_text' (countedText) void)) tryInvoke1: aString
! !

!Object methodsFor: 'errors'!
error: aString
	('Error: ' , aString) displayNl.
	^nil
!
doesNotUnderstand: aMessage
	('DNU ' , self class name , '>>' , aMessage selector , ' args ' , aMessage arguments size printString) displayNl.
	^nil
!
mustBeBoolean
	('mustBeBoolean ' , self printString) displayNl.
	^true
!
attemptToAssign: value withIndex: index
	('attemptToAssign: ' , value printString , ' withIndex: ' , index printString , ' on ' , self printString) displayNl.
	^value
! !

!UndefinedObject methodsFor: 'testing'!
isNil
	^true
!
notNil
	^false
!
printString
	^'nil'
!
ifNil: aBlock
	^aBlock value
!
ifNotNil: aBlock
	^nil
! !

!Boolean methodsFor: 'logic'!
& aBoolean
	^self and: [aBoolean]
!
| aBoolean
	^self or: [aBoolean]
! !

!True methodsFor: 'logic'!
not
	^false
!
printString
	^'true'
!
ifTrue: aBlock
	^aBlock value
!
ifFalse: aBlock
	^nil
!
ifTrue: t ifFalse: f
	^t value
!
and: aBlock
	^aBlock value
!
or: aBlock
	^true
! !

!False methodsFor: 'logic'!
not
	^true
!
printString
	^'false'
!
ifTrue: aBlock
	^nil
!
ifFalse: aBlock
	^aBlock value
!
ifTrue: t ifFalse: f
	^f value
!
and: aBlock
	^false
!
or: aBlock
	^aBlock value
! !

!Association methodsFor: 'accessing'!
key: k value: v
	key := k.
	value := v
!
key
	^key
!
value
	^value
!
value: v
	value := v
!
printString
	^key printString , '->' , value printString
! !

!Message methodsFor: 'accessing'!
selector
	^selector
!
arguments
	^arguments
! !

!Point methodsFor: 'accessing'!
x
	^x
!
y
	^y
!
setX: ax setY: ay
	x := ax.
	y := ay
!
setX: ax
	x := ax
!
+ aPoint
	^(x + aPoint x) @ (y + aPoint y)
!
= aPoint
	^(aPoint isKindOf: Point) and: [x = aPoint x and: [y = aPoint y]]
!
printString
	^x printString , '@' , y printString
! !

!Object methodsFor: 'class membership'!
isKindOf: aClass
	| c |
	c := self class.
	[c == nil] whileFalse: [c == aClass ifTrue: [^true]. c := c superclass].
	^false
! !
