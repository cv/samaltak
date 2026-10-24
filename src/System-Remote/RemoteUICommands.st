Object subclass: #RemoteUICommands
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Remote'!

RemoteUICommands comment: 'I am the generic implementation of the UI commands, written against the remote protocol (see RemoteControl): snapshot, find and bounds read a RemoteSnapshot; click, hover, type, key, drag, select, scroll and resize answer a RemoteInputJob that resolves the target to a screen point, plays a RemoteInputPlan through RemoteInputDevice default and waits for the image to settle, all without blocking (the input dispatcher runs them when it hosts remote control). RemoteControl root: registers me; a UI replaces any command by registering its own.

Targets are refs (@w1.ok, @w1.list#3) or points ({"x":…,"y":…}). Input commands wait until the image settles (RemoteInputDevice settle, at most 2 s); a request''s "settle" (ms, 0: do not wait) overrides that, e.g. for typing into a system whose user Processes are busy and never settle. A widget is hit at RemoteControl pointResolver''s point, else its remoteClickPoint, else the center of its remoteBounds; hover''s "at" spec asks the widget instead (remotePointAt:, e.g. a pixel ''4,7'' of a PixelView).'!

!RemoteUICommands class methodsFor: 'registering'!
registerIn: aRemoteControl
	#(#snapshot #find #bounds #click #hover #type #key #drag #select #scroll #resize) do: [:name |
		aRemoteControl
			registerGenericCommand: name asString
			handler: [:request | self perform: (name, ':') asSymbol with: request]]
! !

!RemoteUICommands class methodsFor: 'reading'!
snapshot: aRequest
	| snapshot depth showBounds maxItems ref |
	snapshot := RemoteControl snapshot.
	depth := aRequest numberAt: 'depth' ifAbsent: [9].
	showBounds := aRequest booleanAt: 'bounds'.
	maxItems := aRequest numberAt: 'maxItems' ifAbsent: [60].
	ref := aRequest at: 'ref'.
	^Dictionary new
		at: 'text' put: (ref isNil
			ifTrue: [snapshot renderDepth: depth bounds: showBounds maxItems: maxItems]
			ifFalse: [snapshot renderRef: ref depth: depth bounds: showBounds maxItems: maxItems]);
		yourself
!
find: aRequest
	^Dictionary new
		at: 'matches' put: ((RemoteControl snapshot find: (aRequest stringAt: 'text')) collect: [:node | node summary]);
		yourself
!
bounds: aRequest
	| node |
	node := RemoteControl snapshot resolveOrFail: (aRequest stringAt: 'target').
	node bounds isNil ifTrue: [^RemoteError signal: node atRef, ' has no bounds'].
	^node boundsDictionary
! !

!RemoteUICommands class methodsFor: 'input'!
click: aRequest
	| target point button count plan |
	target := aRequest target ifNil: [^RemoteError signal: 'click: missing target'].
	point := self pointFor: target.
	button := self buttonFrom: (aRequest at: 'button').
	count := aRequest numberAt: 'count' ifAbsent: [1].
	plan := self device planner
		click: point button: button count: count
		modifiers: (RemoteInputPlanner modifiersFrom: (aRequest at: 'mods')).
	^self job: aRequest play: plan answer: (Dictionary new at: 'at' put: (self pair: point); yourself)
!
hover: aRequest
	"Move the pointer to the target (no button), or to the point its widget answers for the request's at (remotePointAt:)."
	| target spec point |
	target := aRequest target ifNil: [^RemoteError signal: 'hover: missing target'].
	spec := aRequest at: 'at'.
	point := spec isNil
		ifTrue: [self pointFor: target]
		ifFalse: [self pointFor: target at: spec].
	^self job: aRequest play: (self device planner moveTo: point) answer: (Dictionary new at: 'at' put: (self pair: point); yourself)
!
type: aRequest
	"Focus the target, position the caret (at: end/start, replace), then type the text: one textInput event per character, delay ms apart (default the planner's)."
	| text target at job delay |
	text := aRequest stringAt: 'text'.
	target := aRequest target.
	delay := aRequest numberAt: 'delay' ifAbsent: [nil].
	job := self newJob.
	job answer at: 'typed' put: text size.
	target isNil ifFalse: [self focus: target in: job request: aRequest].
	at := aRequest at: 'at'.
	(aRequest booleanAt: 'replace')
		ifTrue: [self position: target spec: 'all' orKey: 'Meta+a' in: job]
		ifFalse: [
			at = 'end' ifTrue: [self position: target spec: 'end' orKey: 'Meta+Down' in: job].
			at = 'start' ifTrue: [self position: target spec: 'start' orKey: 'Meta+Up' in: job]].
	job do: [:j | j play: (delay isNil
		ifTrue: [self device planner typeText: text]
		ifFalse: [self device planner typeText: text delay: delay])].
	job settle: (self settleFor: aRequest).
	^job
!
key: aRequest
	| combos target job |
	combos := aRequest at: 'combo'.
	combos isNil ifTrue: [^RemoteError signal: 'key: missing combo'].
	combos isString ifTrue: [combos := Array with: combos].
	target := aRequest target.
	job := self newJob.
	target isNil ifFalse: [self focus: target in: job request: aRequest].
	job do: [:j | j play: (self device planner keyCombos: combos)].
	job settle: (self settleFor: aRequest).
	^job
!
drag: aRequest
	| from to target |
	target := aRequest target ifNil: [^RemoteError signal: 'drag: missing target'].
	from := self pointFor: target.
	to := ((aRequest includesKey: 'dx') or: [aRequest includesKey: 'dy'])
		ifTrue: [from + ((aRequest numberAt: 'dx' ifAbsent: [0]) @ (aRequest numberAt: 'dy' ifAbsent: [0]))]
		ifFalse: [self pointFor: ((aRequest targetAt: 'to') ifNil: [^RemoteError signal: 'drag: missing to, or dx and dy'])].
	^self job: aRequest
		play: (self device planner drag: from to: to modifiers: (RemoteInputPlanner modifiersFrom: (aRequest at: 'mods')))
		answer: (Dictionary new at: 'from' put: (self pair: from); at: 'to' put: (self pair: to); yourself)
!
resize: aRequest
	"Drag the window's resize handle (its child named resize) so the window gets the requested w and h."
	| snapshot window handle from delta job ref |
	snapshot := RemoteControl snapshot.
	window := snapshot resolveOrFail: (aRequest stringAt: 'target').
	[window isNil or: [window isWindow]] whileFalse: [window := window parent].
	window isNil ifTrue: [^RemoteError signal: (aRequest stringAt: 'target'), ' is not in a window'].
	handle := (snapshot at: window ref, '.resize') ifNil: [
		^RemoteError notFound: window atRef, ' has no resize handle (', window atRef, '.resize)'].
	window bounds isNil ifTrue: [^RemoteError signal: window atRef, ' has no bounds'].
	from := self pointForNode: handle.
	delta := ((aRequest numberAt: 'w' ifAbsent: [window bounds width]) - window bounds width)
		@ ((aRequest numberAt: 'h' ifAbsent: [window bounds height]) - window bounds height).
	ref := window ref.
	job := self job: aRequest play: (self device planner drag: from to: from + delta modifiers: 0) answer: Dictionary new.
	job do: [:j |
		j answer: ((RemoteControl snapshot resolve: ref)
			ifNil: [Dictionary new]
			ifNotNil: [:node | Dictionary new at: 'bounds' put: node boundsDictionary; yourself])].
	^job
!
scroll: aRequest
	"dy > 0 scrolls the content down (towards its end), like a DOM wheel deltaY; 40 points per wheel unit."
	| point dx dy |
	point := self pointFor: (aRequest target ifNil: [^RemoteError signal: 'scroll: missing target']).
	dy := aRequest numberAt: 'dy' ifAbsent: [120].
	dx := aRequest numberAt: 'dx' ifAbsent: [0].
	^self job: aRequest
		play: (self device planner scroll: point delta: (dx / -40.0) @ (dy / -40.0) modifiers: 0)
		answer: Dictionary new
!
select: aRequest
	"Select text in an editor (the widget's remoteSelect:then: or remoteSelect:) or an item of a list (a click on the child whose label matches)."
	| node spec item wanted job |
	node := RemoteControl snapshot resolveOrFail: (aRequest stringAt: 'target').
	spec := aRequest at: 'spec'.
	spec isNil ifTrue: [^RemoteError signal: 'select: missing spec'].
	(node widget respondsTo: #remoteSelect:then:) ifTrue: [
		job := self newJob.
		self select: spec in: node widget job: job then: [:answer | job answer: (answer ifNil: [Dictionary new])].
		^job].
	(node widget respondsTo: #remoteSelect:) ifTrue: [^node widget remoteSelect: spec].
	spec isString ifFalse: [^RemoteError signal: node atRef, ' does not select text'].
	wanted := spec asLowercase.
	item := node childNodes
		detect: [:child | child label asLowercase = wanted]
		ifNone: [node childNodes detect: [:child | child label asLowercase includesSubstring: wanted] ifNone: [nil]].
	item isNil ifTrue: [^RemoteError notFound: 'no item ', (JSON quote: spec), ' in ', node atRef].
	^self job: aRequest
		play: (self device planner click: (self pointForNode: item))
		answer: (Dictionary new at: 'ref' put: item atRef; at: 'label' put: item label; yourself)
! !

!RemoteUICommands class methodsFor: 'private'!
device
	^RemoteInputDevice default
!
newJob
	^RemoteInputJob new
!
settleFor: aRequest
	"The settle timeout of aRequest: its settle (ms, 0: none), else the device's."
	^aRequest numberAt: 'settle' ifAbsent: [self device settleMilliseconds]
!
job: aRequest play: aPlan answer: aDictionary
	"A job that plays aPlan and then waits for the image to settle."
	| job |
	job := self newJob.
	job answer: aDictionary.
	job play: aPlan.
	job settle: (self settleFor: aRequest).
	^job
!
focus: aTarget in: aJob request: aRequest
	"Give aTarget keyboard focus as a user would: nothing if it has it; if its window is inactive, click the window's title bar first (that keeps the caret and the selection, which a click into an editor would move) and wait (at most 1 s) for the window to be active; click aTarget itself only if it still lacks focus."
	aTarget isPoint ifTrue: [
		aJob play: (self device planner click: aTarget).
		^aJob settle: (self settleFor: aRequest)].
	aJob do: [:j | | node window |
		node := RemoteControl snapshot resolveOrFail: aTarget.
		(node hasState: 'focused') ifFalse: [
			window := node parent.
			[window isNil or: [window isWindow]] whileFalse: [window := window parent].
			(window notNil and: [(window hasState: 'focused') not])
				ifTrue: [ | ref |
					ref := window atRef.
					j play: (self device planner click: (self pointForNode: window)).
					j waitFor: [(RemoteControl snapshot resolve: ref) ifNil: [true] ifNotNil: [:w | w hasState: 'focused']]
						timeout: 1000
						then: [:ok | | again |
							again := RemoteControl snapshot resolveOrFail: aTarget.
							(again hasState: 'focused') ifFalse: [
								j play: (self device planner click: (self pointForNode: again)).
								j settle: (self settleFor: aRequest)]]]
				ifFalse: [
					j play: (self device planner click: (self pointForNode: node)).
					j settle: (self settleFor: aRequest)]]]
!
position: aTarget spec: aString orKey: aCombo in: aJob
	aJob do: [:j | | node |
		node := aTarget isString ifTrue: [RemoteControl snapshot resolve: aTarget].
		(node notNil and: [node widget respondsTo: #remoteSelect:then:])
			ifTrue: [self select: aString in: node widget job: j then: [:answer | nil]]
			ifFalse: [
				(node notNil and: [node widget respondsTo: #remoteSelect:])
					ifTrue: [node widget remoteSelect: aString]
					ifFalse: [j play: (self device planner keyCombo: aCombo)]]]
!
select: aSpec in: aWidget job: aJob then: aBlock
	"Have aWidget select aSpec in its own Process (remoteSelect:then:) and wait (at most 2 s) without blocking; then aBlock value: its answer."
	| done answer |
	done := false.
	aWidget remoteSelect: aSpec then: [:a | answer := a. done := true].
	aJob waitFor: [done] timeout: 2000 then: [:ok | aBlock value: answer]
!
pointFor: aTarget
	aTarget isPoint ifTrue: [^aTarget].
	^self pointForNode: (RemoteControl snapshot resolveOrFail: aTarget)
!
pointFor: aTarget at: aSpec
	| node point |
	aTarget isPoint ifTrue: [^RemoteError signal: 'at: needs a ref, not a point'].
	node := RemoteControl snapshot resolveOrFail: aTarget.
	(node widget respondsTo: #remotePointAt:) ifFalse: [^RemoteError signal: node atRef, ' does not answer points for at'].
	point := node widget remotePointAt: aSpec.
	point isNil ifTrue: [^RemoteError notFound: node atRef, ' has no ', (JSON quote: aSpec)].
	^point
!
pointForNode: aNode
	| point |
	(aNode hasState: 'disabled') ifTrue: [^RemoteError signal: aNode atRef, ' is disabled'].
	point := RemoteControl pointResolver isNil
		ifTrue: [
			(aNode widget respondsTo: #remoteClickPoint)
				ifTrue: [aNode widget remoteClickPoint]
				ifFalse: [aNode bounds ifNotNil: [:b | b center]]]
		ifFalse: [RemoteControl pointResolver value: aNode].
	point isNil ifTrue: [^RemoteError signal: aNode atRef, ' is not visible (covered, collapsed or off-screen)'].
	^point
!
buttonFrom: anObject
	anObject isNil ifTrue: [^1].
	anObject isInteger ifTrue: [^anObject].
	anObject = 'left' ifTrue: [^1].
	anObject = 'middle' ifTrue: [^2].
	anObject = 'right' ifTrue: [^3].
	^RemoteError signal: 'unknown button ', anObject printString
!
pair: aPoint
	^Array with: aPoint x rounded with: aPoint y rounded
! !
