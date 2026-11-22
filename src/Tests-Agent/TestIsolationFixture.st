TestCase subclass: #TestIsolationFixture
	instanceVariableNames: 'held'
	classVariableNames: 'Log Value'
	package: 'Tests-Agent'!

TestIsolationFixture comment: 'The tests TestIsolationTest runs to check TestCase''s cleanups: a test that replaces a value (class-side value) and fails, one whose cleanup fails, one that needs a throwaway image. Not run by itself (isAbstract).'!

!TestIsolationFixture methodsFor: 'running'!
tearDown
	self class log add: #tearDown
! !

!TestIsolationFixture methodsFor: 'tests'!
testReplacesAndFails
	self class log: OrderedCollection new.
	held := Object new.
	self addCleanup: [self class log add: #first].
	self replace: #value of: self class with: #test.
	self addCleanup: [self class log add: #second].
	self assert: self class value equals: #test.
	self fail: 'on purpose'
!
testCleanupFails
	self class log: OrderedCollection new.
	self replace: #value of: self class with: #test.
	self addCleanup: [1 / 0]
!
testNeedsThrowaway
	self needsThrowawayImage: 'a test of needsThrowawayImage:'
! !

!TestIsolationFixture class methodsFor: 'accessing'!
value
	^Value
!
value: anObject
	Value := anObject
!
log
	^Log ifNil: [Log := OrderedCollection new]
!
log: aCollection
	Log := aCollection
! !

!TestIsolationFixture class methodsFor: 'testing'!
isAbstract
	^true
! !
