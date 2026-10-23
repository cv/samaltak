TestCase subclass: #RemoteControlTest
	instanceVariableNames: 'savedRegistry savedDevice events'
	classVariableNames: ''
	package: 'Tests-Remote'!

RemoteControlTest comment: 'Tests RemoteControl dispatching, the built-in commands (eval, wait, state, quit, ping) and the generic UI commands against a fake widget tree with a recording input device.'!

!RemoteControlTest methodsFor: 'running'!
setUp
	savedRegistry := RemoteControl registryState.
	savedDevice := RemoteInputDevice default.
	events := OrderedCollection new.
	RemoteInputDevice default: (RemoteInputDevice new injector: [:e | events add: e]; settleMilliseconds: 0; yourself)
!
tearDown
	RemoteControl registryState: savedRegistry.
	RemoteInputDevice default: savedDevice.
	RemoteControl unregisterWaitCondition: 'test-never'
!
send: aDictionary
	^RemoteControl dispatch: (RemoteRequest on: aDictionary)
!
cmd: aString
	^Dictionary new at: 'cmd' put: aString; yourself
!
cmd: aString with: key with: value
	^(self cmd: aString) at: key put: value; yourself
!
installFakeUI
	| root window list |
	root := RemoteFakeWidget role: #screen label: 'test'.
	window := root add: (RemoteFakeWidget role: #window label: 'Browser' name: 'w1').
	window bounds: (0 @ 0 extent: 400 @ 300); state: #(#focused).
	list := window add: ((RemoteFakeWidget role: #list label: 'Packages' name: 'packages') bounds: (0 @ 20 extent: 100 @ 200); yourself).
	list add: ((RemoteFakeWidget role: #item label: 'Kernel-Numbers') bounds: (0 @ 20 extent: 100 @ 20); yourself).
	list add: ((RemoteFakeWidget role: #item label: 'Kernel-Objects') bounds: (0 @ 40 extent: 100 @ 20); yourself).
	window add: ((RemoteFakeEditor role: #editor label: 'text') bounds: (100 @ 20 extent: 300 @ 200); text: 'hello world'; yourself).
	window add: ((RemoteFakeWidget role: #button label: 'Off') bounds: (300 @ 250 extent: 40 @ 20); state: #(#disabled); yourself).
	window add: ((RemoteFakeWidget role: #handle label: 'resize') bounds: (390 @ 290 extent: 10 @ 10); yourself).
	RemoteControl uiCommandNames do: [:name | RemoteControl unregisterCommand: name].
	RemoteControl root: root.
	^root
! !

!RemoteControlTest methodsFor: 'tests - dispatch'!
testPingAndId
	| r |
	r := self send: ((self cmd: 'ping') at: 'id' put: 42; yourself).
	self assert: (r at: 'ok').
	self assert: (r at: 'pong').
	self assert: (r at: 'id') equals: 42
!
testUnknownCommand
	| r |
	r := self send: (self cmd: 'frobnicate').
	self deny: (r at: 'ok').
	self assert: (r at: 'code') equals: 1.
	self assert: ((r at: 'error') includesSubstring: 'unknown command "frobnicate"').
	self assert: ((r at: 'error') includesSubstring: 'eval').
	r := self send: Dictionary new.
	self deny: (r at: 'ok')
!
testUICommandWithoutUI
	| r |
	RemoteControl uiCommandNames do: [:name | RemoteControl unregisterCommand: name].
	RemoteControl root: nil.
	r := self send: (self cmd: 'snapshot').
	self deny: (r at: 'ok').
	self assert: ((r at: 'error') includesSubstring: 'no UI').
	r := self send: ((self cmd: 'wait') at: 'text' put: 'x'; yourself).
	self deny: (r at: 'ok').
	self assert: (r at: 'code') equals: 1
!
testRegisteredCommand
	| r |
	RemoteControl registerCommand: 'test-echo' handler: [:req |
		(req at: 'fail') = 'remote' ifTrue: [RemoteError notFound: 'nothing here'].
		(req at: 'fail') = 'smalltalk' ifTrue: [nil foo].
		(req at: 'plain') == true ifTrue: [req at: 'value'] ifFalse: [Dictionary new at: 'echo' put: (req at: 'value'); yourself]].
	r := self send: ((self cmd: 'test-echo') at: 'value' put: #(1 2); yourself).
	self assert: (r at: 'ok').
	self assert: (r at: 'echo') equals: #(1 2).
	r := self send: ((self cmd: 'test-echo') at: 'value' put: 5; at: 'plain' put: true; yourself).
	self assert: (r at: 'result') equals: 5.
	r := self send: (self cmd: 'test-echo' with: 'fail' with: 'remote').
	self assert: (r at: 'code') equals: 2.
	self assert: (r at: 'error') equals: 'nothing here'.
	r := self send: (self cmd: 'test-echo' with: 'fail' with: 'smalltalk').
	self assert: (r at: 'code') equals: 3.
	self assert: ((r at: 'error') includesSubstring: 'MessageNotUnderstood').
	self assert: (RemoteControl commandNames includes: 'test-echo')
! !

!RemoteControlTest methodsFor: 'tests - eval'!
testEval
	| r |
	r := self send: (self cmd: 'eval' with: 'source' with: '3 + 4').
	self assert: (r at: 'ok').
	self assert: (r at: 'printString') equals: '7'.
	self assert: (r at: 'className') equals: 'SmallInteger'.
	r := self send: (self cmd: 'eval' with: 'source' with: '''abc'' reversed').
	self assert: (r at: 'printString') equals: '''cba'''
!
testEvalErrors
	| r |
	r := self send: (self cmd: 'eval' with: 'source' with: '1/0').
	self deny: (r at: 'ok').
	self assert: (r at: 'code') equals: 3.
	self assert: (r at: 'errorClass') equals: 'ZeroDivide'.
	self assert: ((r at: 'error') includesSubstring: 'ZeroDivide').
	self assert: (r at: 'stack') notEmpty.
	r := self send: (self cmd: 'eval' with: 'source' with: '3 +').
	self assert: (r at: 'code') equals: 3.
	self assert: (r at: 'errorClass') equals: 'SyntaxError'.
	r := self send: (self cmd: 'eval' with: 'source' with: 'self halt').
	self assert: (r at: 'errorClass') equals: 'Halt'.
	r := self send: (self cmd: 'eval').
	self assert: (r at: 'code') equals: 1
!
testEvalBindingsPersist
	| r |
	self send: (self cmd: 'eval' with: 'source' with: 'remoteTestVariable := 41').
	r := self send: (self cmd: 'eval' with: 'source' with: 'remoteTestVariable + 1').
	self assert: (r at: 'printString') equals: '42'.
	RemoteControl bindings removeKey: #remoteTestVariable ifAbsent: []
!
testEvalRunsInItsOwnProcess
	| r |
	r := self send: (self cmd: 'eval' with: 'source' with: 'Processor activeProcess name').
	self assert: (r at: 'printString') equals: '''remote eval'''
!
testEvalTimeout
	| r start |
	start := Time millisecondClockValue.
	r := self send: ((self cmd: 'eval' with: 'source' with: '[true] whileTrue') at: 'timeout' put: 200; yourself).
	self assert: (r at: 'code') equals: 2.
	self assert: Time millisecondClockValue - start < 2000.
	self assert: ((Processor allProcesses select: [:p | p name = 'remote eval']) isEmpty)
! !

!RemoteControlTest methodsFor: 'tests - wait and state'!
testWaitMilliseconds
	| r |
	r := self send: (self cmd: 'wait' with: 'ms' with: 60).
	self assert: (r at: 'ok').
	self assert: (r at: 'ms') >= 60
!
testWaitIdle
	| r busy start |
	start := Time millisecondClockValue.
	busy := self fork: [[Time millisecondClockValue - start < 300] whileTrue] at: Processor userSchedulingPriority.
	r := self send: ((self cmd: 'wait' with: 'idle' with: true) at: 'timeout' put: 5000; yourself).
	self assert: (r at: 'ok').
	self assert: busy isTerminated.
	self assert: Time millisecondClockValue - start >= 300
!
testWaitTimeoutAndUnknownCondition
	| r |
	RemoteControl registerWaitCondition: 'test-never' with: [:v :req | false].
	r := self send: ((self cmd: 'wait' with: 'test-never' with: true) at: 'timeout' put: 100; yourself).
	self deny: (r at: 'ok').
	self assert: (r at: 'code') equals: 2.
	self assert: ((r at: 'error') includesSubstring: 'wait timed out after 100 ms').
	r := self send: (self cmd: 'wait' with: 'bogus' with: 1).
	self assert: (r at: 'code') equals: 1
!
testState
	| r processes |
	r := self send: (self cmd: 'state').
	self assert: (r at: 'ok').
	processes := r at: 'processes'.
	self assert: processes notEmpty.
	self assert: (processes anySatisfy: [:p | (p at: 'state') = 'running']).
	self assert: (processes anySatisfy: [:p | (p at: 'name') = 'idle' and: [p at: 'system']]).
	self assert: (r includesKey: 'theme').
	self assert: (JSON parse: (JSON render: r)) isDictionary
!
testQuitIsDeferred
	| request r |
	request := RemoteRequest on: (self cmd: 'quit').
	r := RemoteControl dispatch: request.
	self assert: (r at: 'ok').
	self assert: request afterResponse notNil
! !

!RemoteControlTest methodsFor: 'tests - ui'!
testSnapshotFindBoundsAndWait
	| r |
	self installFakeUI.
	r := self send: (self cmd: 'snapshot').
	self assert: ((r at: 'text') includesSubstring: 'item @w1.packages.kernel-objects "Kernel-Objects"').
	r := self send: ((self cmd: 'snapshot' with: 'ref' with: '@w1.packages') at: 'depth' put: 0; yourself).
	self assert: (r at: 'text') equals: 'list @w1.packages "Packages"', (String with: Character lf).
	r := self send: (self cmd: 'find' with: 'text' with: 'objects').
	self assert: ((r at: 'matches') collect: [:m | m at: 'ref']) equals: #('@w1.packages.kernel-objects').
	r := self send: (self cmd: 'bounds' with: 'target' with: '@w1.packages').
	self assert: (r at: 'h') equals: 200.
	r := self send: (self cmd: 'bounds' with: 'target' with: '@w1.nothing').
	self assert: (r at: 'code') equals: 2.
	r := self send: ((self cmd: 'wait' with: 'text' with: 'hello world') at: 'ref' put: '@w1.text'; yourself).
	self assert: (r at: 'ok').
	r := self send: ((self cmd: 'wait' with: 'gone' with: '@w1.text') at: 'timeout' put: 50; yourself).
	self assert: (r at: 'code') equals: 2.
	r := self send: (self cmd: 'state').
	self assert: ((r at: 'windows') first at: 'ref') equals: '@w1'
!
testClickAndSelect
	| r |
	self installFakeUI.
	r := self send: ((self cmd: 'click' with: 'target' with: '@w1.packages.kernel-objects') at: 'count' put: 2; yourself).
	self assert: (r at: 'ok').
	self assert: (r at: 'at') equals: #(50 50).
	self assert: (events collect: [:e | e first]) asArray equals: #(1 2 3 2 3).
	events removeAll.
	r := self send: ((self cmd: 'click' with: 'target' with: '12,34') at: 'button' put: 'right'; yourself).
	self assert: (events last at: 5) equals: 3.
	self assert: (events last at: 3) equals: 12.0.
	r := self send: (self cmd: 'click' with: 'target' with: '@w1.off').
	self assert: ((r at: 'error') includesSubstring: 'disabled').
	events removeAll.
	r := self send: ((self cmd: 'select' with: 'target' with: '@w1.packages') at: 'spec' put: 'kernel-numbers'; yourself).
	self assert: (r at: 'ref') equals: '@w1.packages.kernel-numbers'.
	self assert: (events last at: 4) equals: 30.0.
	r := self send: ((self cmd: 'select' with: 'target' with: '@w1.text') at: 'spec' put: 'all'; yourself).
	self assert: (r at: 'selected') equals: 'all'.
	r := self send: ((self cmd: 'select' with: 'target' with: '@w1.packages') at: 'spec' put: 'Nope'; yourself).
	self assert: (r at: 'code') equals: 2
!
testTypeKeyDragScrollResize
	| r editor |
	self installFakeUI.
	editor := (RemoteControl snapshot resolve: '@w1.text') widget.
	r := self send: ((self cmd: 'type' with: 'target' with: '@w1.text') at: 'text' put: 'hi'; at: 'at' put: 'end'; yourself).
	self assert: (r at: 'typed') equals: 2.
	self assert: editor selectSpecs asArray equals: #('end').
	self assert: ((events select: [:e | e first = 7]) collect: [:e | e at: 7]) asArray equals: #('h' 'i').
	events removeAll.
	r := self send: (self cmd: 'key' with: 'combo' with: 'Meta+s').
	self assert: (events collect: [:e | e first]) asArray equals: #(5 5 6 6).
	events removeAll.
	r := self send: ((self cmd: 'drag' with: 'target' with: '@w1.packages.kernel-numbers') at: 'dx' put: 10; at: 'dy' put: 0; yourself).
	self assert: (r at: 'to') equals: #(60 30).
	self assert: (events last first) equals: 3.
	events removeAll.
	r := self send: (self cmd: 'scroll' with: 'target' with: '@w1.text').
	self assert: (events last at: 7) equals: 0.0 @ -3.0.
	events removeAll.
	r := self send: ((self cmd: 'resize' with: 'target' with: '@w1') at: 'w' put: 500; at: 'h' put: 300; yourself).
	self assert: (r at: 'ok').
	self assert: (events last at: 3) equals: 495.0.
	self assert: (events last at: 4) equals: 295.0
!
testUIOverride
	| r |
	self installFakeUI.
	RemoteControl registerCommand: 'snapshot' handler: [:req | Dictionary new at: 'text' put: 'mine'; yourself].
	r := self send: (self cmd: 'snapshot').
	self assert: (r at: 'text') equals: 'mine'.
	RemoteControl root: nil.
	self assert: (RemoteControl handlerFor: 'snapshot') notNil.
	self assert: (RemoteControl handlerFor: 'click') isNil
! !
