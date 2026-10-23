TestCase subclass: #ObjectTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

ObjectTest comment: 'Tests the basic protocol of Object, UndefinedObject, Boolean, Association, Message, Point and Rectangle.'!

!ObjectTest methodsFor: 'tests'!
testIdentityAndEquality
	| o |
	o := Object new.
	self assert: o == o.
	self assert: o = o.
	self deny: o = Object new.
	self assert: o hash = o identityHash.
	self assert: (o ~= Object new).
	self assert: (3 ~~ 4)
!
testCopy
	| a b |
	a := OrderedCollection with: 1 with: 2.
	b := a copy.
	self deny: a == b.
	self assert: a = b.
	b add: 3.
	self assert: a size = 2.
	self assert: (Array with: a) deepCopy first ~~ a
!
testPrinting
	self assert: Object new printString = 'an Object'.
	self assert: (Array new: 0) printString = '#()'.
	self assert: nil printString = 'nil'.
	self assert: true printString = 'true'.
	self assert: 'abc' displayString = 'abc'.
	self assert: 'abc' printString = '''abc'''.
	self assert: #abc displayString = 'abc'.
	self assert: 42 displayString = '42'.
	self assert: (255 printString: 16) = 'FF'.
	self assert: (3 -> 4) printString = '3->4'.
	self assert: Message new printString notEmpty
!
testReflection
	self assert: 3 class == SmallInteger.
	self assert: (3 isKindOf: Integer).
	self assert: (3 isMemberOf: SmallInteger).
	self deny: (3 isMemberOf: Integer).
	self assert: (3 respondsTo: #printString).
	self deny: (3 respondsTo: #fooBarBaz).
	self assert: ((3 @ 4) instVarAt: 1) = 3.
	self assert: (3 perform: #+ with: 4) = 7.
	self assert: (3 perform: #between:and: with: 1 with: 5).
	self assert: (3 perform: #factorial) = 6.
	self assert: (Array perform: #with:with:with: withArguments: #(1 2 3)) = #(1 2 3).
	self assert: 3 yourself = 3.
	self assert: (Point new instVarNamed: 'x' put: 5; yourself) x = 5
!
testTesting
	self assert: nil isNil.
	self deny: 3 isNil.
	self assert: 3 notNil.
	self assert: 'a' isString.
	self assert: #a isSymbol.
	self deny: 'a' isSymbol.
	self assert: 3 isNumber.
	self assert: 3 isInteger.
	self assert: 3.5 isFloat.
	self assert: $a isCharacter.
	self assert: #(1) isArray.
	self assert: [] isBlock.
	self assert: Object isBehavior.
	self assert: (nil ifNil: [1] ifNotNil: [:x | 2]) = 1.
	self assert: (3 ifNil: [1] ifNotNil: [:x | x + 1]) = 4.
	self assert: (3 ifNil: [1]) = 3.
	self assert: (nil ifNotNil: [:x | 1]) isNil
!
testErrors
	self should: [self error: 'boom'] raise: Error.
	self assert: ([self error: 'boom'] on: Error do: [:e | e messageText]) = 'boom'.
	self should: [Object new halt] raise: Halt.
	self should: [Collection new do: [:x | x]] raise: SubclassResponsibility.
	self should: [Object new shouldBeImplemented] raise: NotYetImplemented.
	self should: [(Array new: 3) at: 4] raise: SubscriptOutOfBounds.
	self should: [(Array new: 3) at: 0 put: 1] raise: SubscriptOutOfBounds
!
testOutOfMemory
	| e |
	e := [Array new: 1 << 40] on: OutOfMemory do: [:ex | ex].
	self assert: e requestedClass == Array.
	self assert: e requestedSize = (1 << 40).
	self should: [Array new: 16r7FFFFFF0] raise: OutOfMemory.
	self should: [ByteArray new: 1 << 70] raise: OutOfMemory.
	self should: [String new: 1 << 40] raise: OutOfMemory.
	self should: [[Array new: -1] on: OutOfMemory do: [:ex | nil]] raise: Error.
	self assert: (Array new: 100000) size = 100000.
	self assert: (ByteArray new: 1000000) size = 1000000
!
testAssociation
	| a |
	a := #key -> 'value'.
	self assert: a key == #key.
	self assert: a value = 'value'.
	self assert: a = (#key -> 'value').
	self deny: a = (#key -> 'other').
	self assert: (1 -> 2) < (2 -> 1)
!
testMessage
	| m |
	m := Message selector: #between:and: arguments: #(1 5).
	self assert: (m sendTo: 3).
	self assert: m numArgs = 2.
	self assert: m printString = 'between: 1 and: 5'
!
testBooleans
	self assert: (true & false) not.
	self assert: (true | false).
	self assert: (true xor: false).
	self deny: (true xor: true).
	self assert: (false or: [true]).
	self deny: (false and: [true]).
	self assert: (true perform: #and: with: [true]).
	self assert: (false perform: #ifTrue:ifFalse: with: [1] with: [2]) = 2.
	self assert: (true perform: #ifTrue: with: [1]) = 1.
	self assert: (false perform: #ifTrue: with: [1]) isNil.
	self assert: true not == false
!
testNonBooleanReceiver
	| x |
	x := 3.
	self should: [x ifTrue: [1] ifFalse: [2]] raise: NonBooleanReceiver.
	self assert: ([x ifTrue: [1] ifFalse: [2]] on: NonBooleanReceiver do: [:e | e resume: false]) = 2
!
testPoint
	| p |
	p := 3 @ 4.
	self assert: p x = 3.
	self assert: p y = 4.
	self assert: p + 1 = (4 @ 5).
	self assert: p + (1 @ 2) = (4 @ 6).
	self assert: p * 2 = (6 @ 8).
	self assert: (p - (3 @ 4)) isZero.
	self assert: (p dist: 0 @ 0) = 5.0.
	self assert: p printString = '3@4'.
	self assert: (3 @ -4) printString = '3@ -4'.
	self assert: p = (3 @ 4).
	self assert: p hash = (3 @ 4) hash.
	self assert: (1 @ 1) < (2 @ 2).
	p x: 10; y: 20.
	self assert: p = (10 @ 20).
	self assert: (Point x: 1 y: 2) = (1 @ 2)
!
testRectangle
	| r |
	r := 0 @ 0 corner: 10 @ 20.
	self assert: r width = 10.
	self assert: r height = 20.
	self assert: r extent = (10 @ 20).
	self assert: (r containsPoint: 5 @ 5).
	self deny: (r containsPoint: 10 @ 5).
	self assert: (r intersects: (5 @ 5 corner: 15 @ 15)).
	self deny: (r intersects: (10 @ 0 corner: 15 @ 15)).
	self assert: (r insetBy: 2) = (2 @ 2 corner: 8 @ 18).
	self assert: (r intersect: (5 @ 5 corner: 15 @ 15)) = (5 @ 5 corner: 10 @ 15).
	self assert: (r merge: (5 @ 5 corner: 15 @ 15)) = (0 @ 0 corner: 15 @ 20).
	self assert: (1 @ 2 extent: 3 @ 4) corner = (4 @ 6).
	self assert: r center = (5 @ 10).
	self assert: (r translateBy: 1 @ 1) origin = (1 @ 1).
	self assert: (r areasOutside: (2 @ 2 corner: 4 @ 4)) size = 4
! !
