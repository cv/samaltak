Object subclass: #RemoteControl
	instanceVariableNames: ''
	classVariableNames: 'Bindings Commands GenericCommands IdleConditions LastCommand LastRequestTime PointResolver RefTable Root SnapshotLock StateProviders WaitConditions'
	package: 'System-Remote'!

RemoteControl comment: 'I am the command registry and the extension API of remote control (docs/design.md, "Remote control"); ControlServer feeds me requests. Everything is on my class side.

Built-in commands: ping, commands, eval, wait, state, quit. The UI layer adds the rest:

	RemoteControl registerCommand: ''screenshot'' handler: [:request | ... a Dictionary of response fields].

A handler receives a RemoteRequest and answers a Dictionary (merged into the response; "ok" defaults to true), nil, or any other object (answered as "result"). It fails by signaling RemoteError (code 1 error, 2 not found / timeout) or any Error (code 3). Handlers run in the client''s process (priority 50), not in a window''s process.

Snapshot contract. The UI registers the object at the top of its widget tree:

	RemoteControl root: World current.     "or a block answering it"

which also registers generic snapshot, find, bounds, click, type, key, drag, select, scroll and resize commands (RemoteUICommands) unless they are already registered; register your own under the same names to replace them. Every object in the tree answers
	remoteRole        Symbol: #window #list #item #editor #button #tab #menu #canvas #status ...
	remoteLabel       String or nil (title, item text, button caption)
	remoteState       Array of words (#selected #focused #dirty) or key=value Strings (''caret=5'', ''process=#1495 waiting'')
	remoteName        stable String the ref is built from (e.g. ''w6'' for a window, ''packages'' for a list), or nil to use the label
	remoteChildren    the child objects; a String child is printed as a raw line
and optionally
	remoteBounds      Rectangle in screen points (printed for windows, or with --bounds; needed for input)
	remoteClickPoint  Point where a click lands, or nil when not visible (default: remoteBounds center)
	remoteText        full text searched by wait text (editors)
	remoteSelect: spec   for select and type --end/--start/--replace: spec is ''all'', ''end'', ''start'', a String to find, or a Dictionary with from/to or line
The root itself answers the same protocol; its role, label and state form the first line (e.g. screen "1440x900" theme=blue-book). Refs are paths of slugs (@w6.packages.kernel-numbers); siblings with equal slugs get ~2, ~3; a widget keeps its ref across snapshots while it stays under the same parent. RemoteSnapshot renders the tree.

Other hooks: addIdleCondition: (e.g. [inputQueue isEmpty]), addStateProvider: (adds e.g. theme and focus to state), registerWaitCondition:with: (e.g. frames), pointResolver: (hit-testing: [:node | aPoint or nil]). Virtual input goes through RemoteInputDevice default.'!

!RemoteControl class methodsFor: 'class initialization'!
initialize
	Commands := Dictionary new.
	GenericCommands := Set new.
	IdleConditions := OrderedCollection new.
	StateProviders := OrderedCollection new.
	WaitConditions := Dictionary new.
	Bindings := Dictionary new.
	RefTable := RemoteRefTable new.
	SnapshotLock := Semaphore forMutualExclusion.
	self registerBuiltins
!
registerBuiltins
	self registerCommand: 'ping' handler: [:r | self ping: r].
	self registerCommand: 'commands' handler: [:r | Dictionary new at: 'commands' put: self commandNames; yourself].
	self registerCommand: 'eval' handler: [:r | self eval: r].
	self registerCommand: 'wait' handler: [:r | self wait: r].
	self registerCommand: 'state' handler: [:r | self state: r].
	self registerCommand: 'quit' handler: [:r | self quit: r].
	self registerWaitCondition: 'text' with: [:text :r | (self snapshot allText includesSubstring: text asString)].
	self registerWaitCondition: 'ref' with: [:ref :r | (self snapshot resolve: ref) notNil].
	self registerWaitCondition: 'gone' with: [:ref :r | (self snapshot resolve: ref) isNil]
! !

!RemoteControl class methodsFor: 'registering commands'!
registerCommand: aString handler: aBlock
	"aBlock value: aRemoteRequest. Replaces a command of the same name."
	Commands at: aString asString put: aBlock.
	GenericCommands remove: aString asString ifAbsent: []
!
unregisterCommand: aString
	Commands removeKey: aString asString ifAbsent: [].
	GenericCommands remove: aString asString ifAbsent: []
!
registerGenericCommand: aString handler: aBlock
	"Register aBlock unless the UI already registered its own command aString."
	(Commands includesKey: aString) ifTrue: [^self].
	Commands at: aString put: aBlock.
	GenericCommands add: aString
!
commandNames
	^Commands keys asSortedCollection asArray
!
handlerFor: aString
	^Commands at: aString ifAbsent: [nil]
!
uiCommandNames
	"Commands a UI provides; without one the image answers a clear error for them."
	^#('snapshot' 'find' 'click' 'type' 'key' 'drag' 'select' 'scroll' 'resize' 'bounds' 'screenshot' 'record')
! !

!RemoteControl class methodsFor: 'snapshot root'!
root: anObjectOrBlock
	"Set the top of the widget tree (an object answering the remote protocol, or a block answering one; nil removes it) and register the generic UI commands."
	Root := anObjectOrBlock.
	RefTable := RemoteRefTable new.
	Root isNil
		ifTrue: [GenericCommands copy do: [:name | self unregisterCommand: name]]
		ifFalse: [RemoteUICommands registerIn: self]
!
root
	^Root isBlock ifTrue: [Root value] ifFalse: [Root]
!
rootSetting
	"The object or block given to root:."
	^Root
!
registryState
	"Answer the registered commands and root, for restoring with registryState: (tests)."
	^Array with: Commands copy with: GenericCommands copy with: Root with: RefTable
!
registryState: anArray
	Commands := anArray first.
	GenericCommands := anArray at: 2.
	Root := anArray at: 3.
	RefTable := anArray at: 4
!
hasRoot
	^Root notNil
!
snapshot
	"Answer a RemoteSnapshot of the current widget tree (refs assigned). Signal RemoteError if no UI registered a root."
	| root |
	root := self root.
	root isNil ifTrue: [^RemoteError signal: 'no UI in this image: nothing registered a snapshot root (RemoteControl root:)'].
	^SnapshotLock critical: [RemoteSnapshot root: root refTable: RefTable]
!
pointResolver
	^PointResolver
!
pointResolver: aBlock
	"aBlock value: aRemoteNode answers the screen Point where input aimed at the node should land, or nil if it cannot be hit (covered, collapsed, off-screen). The UI may raise the window first."
	PointResolver := aBlock
! !

!RemoteControl class methodsFor: 'idle, state and wait hooks'!
addIdleCondition: aBlock
	"aBlock answers true when its part of the system is idle (e.g. no input events queued, the compositor presented the last change)."
	IdleConditions add: aBlock
!
removeIdleCondition: aBlock
	IdleConditions remove: aBlock ifAbsent: []
!
addStateProvider: aBlock
	"aBlock value: aDictionary adds fields to the state command's answer."
	StateProviders add: aBlock
!
removeStateProvider: aBlock
	StateProviders remove: aBlock ifAbsent: []
!
registerWaitCondition: aString with: aBlock
	"wait {aString: value} holds when aBlock value: value value: aRemoteRequest answers true. Polled every 20 ms in the waiting client's process."
	WaitConditions at: aString put: aBlock
!
unregisterWaitCondition: aString
	WaitConditions removeKey: aString ifAbsent: []
! !

!RemoteControl class methodsFor: 'dispatching'!
lastRequestTime
	"millisecondClockValue of the last command that acts on the image (not a query such as snapshot or state), or nil: the UI shows a remote session from it."
	^LastRequestTime
!
lastCommand
	^LastCommand
!
dispatch: aRequest
	"Run aRequest's command; answer the response Dictionary (always with ok, and with id when the request had one). An input command's job is run to the end in the calling Process."
	| r wait |
	r := self begin: aRequest.
	[r isDictionary] whileFalse: [
		wait := self step: r request: aRequest.
		wait isDictionary
			ifTrue: [r := wait]
			ifFalse: [(Delay forMilliseconds: (wait max: 1)) wait]].
	^r
!
begin: aRequest
	"Start aRequest's command: answer the response Dictionary, or a RemoteInputJob still to be stepped (step:request:) when it is an input command."
	| handler answer response |
	(aRequest command isNil or: [#('ping' 'commands' 'state' 'wait' 'snapshot' 'find' 'bounds') includes: aRequest command]) ifFalse: [
		LastRequestTime := Time millisecondClockValue.
		LastCommand := aRequest command].
	handler := aRequest command isNil ifFalse: [self handlerFor: aRequest command].
	handler isNil ifTrue: [^self finish: (self errorResponse: (self unknownCommandMessage: aRequest command) code: 1) request: aRequest].
	answer := self catchErrorsDuring: [handler value: aRequest].
	(answer isKindOf: RemoteInputJob) ifTrue: [^answer].
	^self finish: (self responseFrom: answer) request: aRequest
!
step: aJob request: aRequest
	"Step aJob (never waits): answer the ms until it must be stepped again, or the response Dictionary once it is done."
	| wait |
	wait := self catchErrorsDuring: [aJob step].
	wait isDictionary ifTrue: [^self finish: wait request: aRequest].
	wait isNil ifTrue: [^self finish: (self responseFrom: aJob answer) request: aRequest].
	^wait
!
catchErrorsDuring: aBlock
	^aBlock
		on: RemoteError do: [:e | e return: (self errorResponse: e messageText code: e code)]
		on: Error do: [:e | e return: (self errorResponse: (self describeError: e) code: 3)]
!
finish: aResponse request: aRequest
	aRequest id isNil ifFalse: [aResponse at: 'id' put: aRequest id].
	^aResponse
!
responseFrom: anAnswer
	| response |
	anAnswer isDictionary ifFalse: [
		response := Dictionary new at: 'ok' put: true; yourself.
		anAnswer isNil ifFalse: [response at: 'result' put: anAnswer].
		^response].
	response := anAnswer copy.
	(response includesKey: 'ok') ifFalse: [response at: 'ok' put: true].
	^response
!
errorResponse: aString code: anInteger
	^Dictionary new
		at: 'ok' put: false;
		at: 'error' put: aString;
		at: 'code' put: anInteger;
		yourself
!
unknownCommandMessage: aString
	aString isNil ifTrue: [^'request has no "cmd"'].
	(self uiCommandNames includes: aString) ifTrue: [
		^aString, ': not available, no UI in this image registered it (available: ', (self commandNames inject: '' into: [:a :b | a isEmpty ifTrue: [b] ifFalse: [a, ', ', b]]), ')'].
	^'unknown command "', aString, '" (available: ', (self commandNames inject: '' into: [:a :b | a isEmpty ifTrue: [b] ifFalse: [a, ', ', b]]), ')'
!
describeError: anException
	^[anException printString] on: Error do: [:e | e return: anException class name asString]
! !

!RemoteControl class methodsFor: 'built-in commands'!
ping: aRequest
	^Dictionary new
		at: 'pong' put: true;
		at: 'image' put: Smalltalk vm imagePath;
		at: 'port' put: (ControlServer current ifNotNil: [:s | s port]);
		yourself
!
quit: aRequest
	| code |
	code := aRequest numberAt: 'code' ifAbsent: [0].
	aRequest afterResponseDo: [Smalltalk quit: code].
	^Dictionary new at: 'quitting' put: true; yourself
!
eval: aRequest
	"Evaluate source in its own process (priority 40, so long evaluations do not block other clients) with the persistent remote workspace bindings; answer printString and className, or an error with code 3."
	^self evaluate: (aRequest stringAt: 'source') timeout: (aRequest timeoutMilliseconds: nil)
!
evaluate: aString timeout: milliseconds
	| done result process |
	done := Semaphore new.
	process := [[result := self evaluateCatchingErrors: aString] ensure: [done signal]] newProcess.
	process priority: Processor userSchedulingPriority; name: 'remote eval'.
	process resume.
	milliseconds isNil
		ifTrue: [done wait]
		ifFalse: [
			(done waitTimeoutMSecs: milliseconds) ifTrue: [
				process terminate.
				^RemoteError timeout: 'eval timed out after ', milliseconds printString, ' ms']].
	result isNil ifTrue: [^self errorResponse: 'the evaluation was terminated' code: 3].
	^result
!
evaluateCatchingErrors: aString
	| value |
	^[value := Compiler evaluate: aString for: nil bindings: Bindings.
	  Dictionary new
		at: 'printString' put: (self printStringOf: value);
		at: 'className' put: value class name asString;
		yourself]
			on: Error, Halt do: [:e | e return: (self evalErrorResponse: e)]
!
evalErrorResponse: anException
	| response stack ctx |
	response := self errorResponse: (self describeError: anException) code: 3.
	response at: 'errorClass' put: anException class name asString.
	stack := OrderedCollection new.
	ctx := anException signalerContext.
	[ctx notNil and: [stack size < 20 and: [(ctx method == (Compiler class >> #execute:for:)) not]]] whileTrue: [
		stack add: ([ctx printString] on: Error do: [:e | e return: '?']).
		ctx := ctx sender].
	response at: 'stack' put: stack asArray.
	^response
!
printStringOf: anObject
	^[anObject printString] on: Error do: [:e | e return: 'a ', anObject class name, ' (printString failed: ', (self describeError: e), ')']
!
bindings
	"The remote workspace's variables (Symbol -> Association), shared by all clients."
	^Bindings
! !

!RemoteControl class methodsFor: 'wait'!
wait: aRequest
	"Wait until every condition of aRequest holds: idle, text, ref, gone, and registered ones; ms sleeps first. Fail with code 2 after timeout ms (default 10000)."
	| start timeout checks sleep |
	start := Time millisecondClockValue.
	timeout := aRequest timeoutMilliseconds: 10000.
	checks := self waitChecksFor: aRequest.
	sleep := aRequest numberAt: 'ms' ifAbsent: [0].
	sleep > 0 ifTrue: [(Delay forMilliseconds: sleep) wait].
	(self poll: checks timeout: timeout) ifFalse: [
		^RemoteError timeout: 'wait timed out after ', timeout printString, ' ms: ', (self describeWait: aRequest)].
	^Dictionary new at: 'ms' put: Time millisecondClockValue - start; yourself
!
waitChecksFor: aRequest
	| checks |
	checks := OrderedCollection new.
	aRequest arguments keysDo: [:key |
		(#('cmd' 'id' 'timeout' 'ms') includes: key) ifFalse: [
			key = 'idle'
				ifTrue: [(aRequest booleanAt: 'idle') ifTrue: [checks add: self idleCheck]]
				ifFalse: [checks add: (self checkFor: key value: (aRequest at: key) request: aRequest)]]].
	^checks
!
checkFor: key value: value request: aRequest
	| condition |
	condition := WaitConditions at: key ifAbsent: [
		^RemoteError signal: 'wait: unknown condition "', key, '" (known: idle, ms, ', (WaitConditions keys asSortedCollection inject: '' into: [:a :b | a isEmpty ifTrue: [b] ifFalse: [a, ', ', b]]), ')'].
	^[condition value: value value: aRequest]
!
idleCheck
	"Answer a check that holds once the system was idle on two consecutive polls."
	| streak |
	streak := 0.
	^[self isIdle ifTrue: [streak := streak + 1] ifFalse: [streak := 0].
	  streak >= 2]
!
poll: checks timeout: milliseconds
	"Poll checks every 20 ms until all hold (answer true) or milliseconds have passed (answer false)."
	| start |
	start := Time millisecondClockValue.
	[checks allSatisfy: [:check | check value]] whileFalse: [
		Time millisecondClockValue - start >= milliseconds ifTrue: [^false].
		(Delay forMilliseconds: 20) wait].
	^true
!
waitUntilIdleFor: milliseconds
	"Answer whether the system became idle within milliseconds."
	^self poll: (Array with: self idleCheck) timeout: milliseconds
!
describeWait: aRequest
	| d |
	d := aRequest arguments copy.
	d removeKey: 'cmd' ifAbsent: [].
	d removeKey: 'id' ifAbsent: [].
	^JSON render: d
! !

!RemoteControl class methodsFor: 'idle'!
isIdle
	"Answer whether no user process is runnable (system and control processes do not count) and every registered idle condition holds."
	(Processor readyProcesses anySatisfy: [:p | (self isSystemProcess: p) not]) ifTrue: [^false].
	^IdleConditions allSatisfy: [:condition | condition value == true]
!
isSystemProcess: aProcess
	| name |
	aProcess == Processor activeProcess ifTrue: [^true].
	aProcess == Processor idleProcess ifTrue: [^true].
	aProcess == Processor timeSlicer ifTrue: [^true].
	aProcess == Delay timerProcess ifTrue: [^true].
	name := aProcess name.
	^name notNil and: [(name beginsWith: 'remote ') and: [name ~= 'remote eval']]
! !

!RemoteControl class methodsFor: 'state'!
state: aRequest
	| state |
	state := Dictionary new.
	state at: 'image' put: Smalltalk vm imagePath.
	state at: 'micros' put: Time microsecondClockValue.
	state at: 'idle' put: self isIdle.
	state at: 'processes' put: self processStates.
	state at: 'windows' put: (self hasRoot ifTrue: [self snapshot windowStates] ifFalse: [#()]).
	state at: 'theme' put: nil.
	StateProviders do: [:provider | provider value: state].
	^state
!
processStates
	| processes |
	processes := Processor allProcesses asOrderedCollection.
	(processes includes: Processor activeProcess) ifFalse: [processes add: Processor activeProcess].
	processes := processes asSortedCollection: [:a :b |
		a priority > b priority or: [a priority = b priority and: [a identityHash <= b identityHash]]].
	^processes asArray collect: [:p | self stateOfProcess: p]
!
stateOfProcess: aProcess
	^Dictionary new
		at: 'pid' put: aProcess identityHash;
		at: 'name' put: (aProcess name ifNil: ['']) asString;
		at: 'priority' put: aProcess priority;
		at: 'state' put: (self processStateName: aProcess);
		at: 'cpuMs' put: (aProcess cpuTime ifNil: [0]) // 1000;
		at: 'system' put: (aProcess == Processor activeProcess
			ifTrue: [true]
			ifFalse: [self isSystemProcess: aProcess]);
		yourself
!
processStateName: aProcess
	aProcess isActiveProcess ifTrue: [^'running'].
	aProcess isTerminated ifTrue: [^'terminated'].
	aProcess isRunnable ifTrue: [^'runnable'].
	aProcess isWaiting ifTrue: [^'waiting'].
	^'suspended'
! !
