TestCase subclass: #SystemChangesTest
	instanceVariableNames: 'seen'
	classVariableNames: ''
	package: 'Tests-Kernel'!

SystemChangesTest comment: 'Tests the SystemChanges announcements of Behavior and ClassBuilder.'!

!SystemChangesTest methodsFor: 'running'!
setUp
	seen := OrderedCollection new.
	SystemChanges subscribe: #SystemChangesTest do: [:change |
		(change affects: SystemChangesTestSubject) ifTrue: [seen add: change]]
!
tearDown
	SystemChanges unsubscribe: #SystemChangesTest.
	SystemChanges unsubscribe: #SystemChangesTestFailing.
	SystemChangesTestSubject selectors do: [:each | SystemChangesTestSubject removeSelector: each].
	SystemChangesTestSubject class selectors do: [:each | SystemChangesTestSubject class removeSelector: each]
! !

!SystemChangesTest methodsFor: 'tests'!
testCompileChangeRemove
	| first second |
	SystemChangesTestSubject compile: 'answer ^1'.
	first := SystemChangesTestSubject compiledMethodAt: #answer.
	SystemChangesTestSubject compile: 'answer ^2'.
	second := SystemChangesTestSubject compiledMethodAt: #answer.
	SystemChangesTestSubject removeSelector: #answer.
	self assert: (seen collect: [:each | each kind]) asArray equals: #(#methodAdded #methodChanged #methodRemoved).
	self assert: (seen allSatisfy: [:each | each behavior == SystemChangesTestSubject and: [each selector == #answer]]).
	self assert: seen first oldMethod isNil.
	self assert: seen first newMethod == first.
	self assert: (seen at: 2) oldMethod == first.
	self assert: (seen at: 2) newMethod == second.
	self assert: seen last oldMethod == second.
	self assert: seen last newMethod isNil
!
testClassSideChangesAffectTheClass
	SystemChangesTestSubject class compile: 'answer ^3'.
	self assert: seen size equals: 1.
	self assert: seen first behavior == SystemChangesTestSubject class.
	self assert: seen first theClass == SystemChangesTestSubject.
	self assert: (seen first affects: SystemChangesTestSubject)
!
testAffectsSubclassesNotSuperclasses
	| change |
	change := SystemChange kind: #methodChanged behavior: Integer selector: #gcd: old: nil new: nil.
	self assert: (change affects: Integer).
	self assert: (change affects: Number).
	self deny: (change affects: SmallInteger).
	self deny: (change affects: String).
	self assert: (change isInPackageNamed: 'Kernel-Numbers')
!
testClassDefinitionIsAnnounced
	Object subclass: #SystemChangesTestSubject instanceVariableNames: '' classVariableNames: '' package: 'Tests-Kernel'.
	self assert: (seen collect: [:each | each kind]) asArray equals: #(#classDefined)
!
testSilentlyDuring
	SystemChanges silentlyDuring: [SystemChangesTestSubject compile: 'quiet ^1'].
	self assert: seen isEmpty.
	SystemChangesTestSubject compile: 'loud ^1'.
	self assert: seen size equals: 1
!
testSubscribersRunInOrderAndErrorsDoNotStopOthers
	| order |
	order := OrderedCollection new.
	SystemChanges subscribe: #SystemChangesTestFailing do: [:change |
		(change affects: SystemChangesTestSubject) ifTrue: [order add: #failing. 1 / 0]].
	SystemChanges subscribe: #SystemChangesTest do: [:change |
		(change affects: SystemChangesTestSubject) ifTrue: [order add: #first]].
	SystemChangesTestSubject compile: 'answer ^1'.
	self assert: order asArray equals: #(#first #failing).
	self assert: (SystemChangesTestSubject new perform: #answer) equals: 1
! !
