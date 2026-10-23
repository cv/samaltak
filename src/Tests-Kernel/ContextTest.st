TestCase subclass: #ContextTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

ContextTest comment: 'Tests thisContext and Context reflection.'!

!ContextTest methodsFor: 'helpers'!
answerContext
	^thisContext
!
callee
	^thisContext sender
! !

!ContextTest methodsFor: 'tests'!
testThisContext
	| ctx |
	ctx := thisContext.
	self assert: ctx receiver == self.
	self assert: ctx method == (ContextTest >> #testThisContext).
	self assert: ctx selector == #testThisContext.
	self assert: ctx methodClass == ContextTest.
	self assert: self callee == ctx.
	self deny: ctx isDead.
	self assert: ctx printString = 'ContextTest>>testThisContext'.
	self assert: (ctx stack includes: ctx sender).
	self assert: ctx home == ctx
!
testDeadContext
	| ctx |
	ctx := self answerContext.
	self assert: ctx isDead.
	self assert: ctx printString = 'ContextTest>>answerContext (dead)'
!
testBlockContext
	| outer block ctx |
	outer := thisContext.
	block := [thisContext].
	ctx := block value.
	self assert: ctx isBlockContext.
	self assert: ctx home == outer.
	self assert: ctx closure == block.
	self assert: block numArgs = 0.
	self assert: [:a :b | a] numArgs = 2.
	self assert: (ctx printString beginsWith: '[] in ContextTest>>testBlockContext').
	self assert: block method == outer method.
	self assert: block receiver == self
!
testTemporaries
	| ctx x |
	x := 42.
	ctx := thisContext.
	self assert: (ctx tempAt: 2) = 42.
	ctx tempAt: 2 put: 43.
	self assert: x = 43
!
testInheritedMethodPrinting
	| text |
	text := [3 zork] on: MessageNotUnderstood do: [:e | e signalerContext printString].
	self assert: text = 'SmallInteger(ProtoObject)>>doesNotUnderstand:'
! !
