TestCase subclass: #MessageNotUnderstoodTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

MessageNotUnderstoodTest comment: 'Tests doesNotUnderstand:, MessageNotUnderstood and proxies.'!

!MessageNotUnderstoodTest methodsFor: 'tests'!
testMessageNotUnderstood
	| e |
	e := [3 foo: 4 bar: 5] on: MessageNotUnderstood do: [:ex | ex].
	self assert: e receiver = 3.
	self assert: e message selector == #foo:bar:.
	self assert: e message arguments = #(4 5).
	self assert: e class == MessageNotUnderstood
!
testResumeAnswersTheSend
	self assert: ([nil foo + 1] on: MessageNotUnderstood do: [:e | e resume: 41]) = 42.
	self assert: ([nil foo] on: MessageNotUnderstood do: [:e | e return: 7]) = 7
!
testProxy
	| proxy |
	proxy := KernelTestProxy on: (OrderedCollection new).
	proxy add: 3; add: 4.
	self assert: proxy size = 2.
	self assert: (proxy inject: 0 into: [:a :b | a + b]) = 7.
	self assert: proxy proxyLog asArray = #(#add: #add: #size #inject:into:).
	self assert: (proxy == proxy).
	self assert: proxy isNil not
!
testRespondsTo
	self assert: (3 respondsTo: #+).
	self deny: (3 respondsTo: #foo).
	self assert: (OrderedCollection canUnderstand: #add:).
	self assert: (OrderedCollection lookupSelector: #do:) methodClass == OrderedCollection.
	self assert: (OrderedCollection lookupSelector: #inject:into:) methodClass == Collection
! !
