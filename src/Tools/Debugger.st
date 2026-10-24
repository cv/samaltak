Column subclass: #Debugger
	instanceVariableNames: 'session header link bar buttons stackHeader stack sourceHeader source status receiverInspector contextInspector selected hiddenCount mutedFrames fullStack shownMethod note done headerException timer listener'
	classVariableNames: ''
	package: 'Tools'!

Debugger comment: 'I am the Debugger window''s content (docs/design.md, "Debugging and profiling"; look and behavior: prototypes/1-classic/debugger.js). I show one DebugSession: the reason (DebuggerHeader, with the debugged Process and its state as a link to the Process Browser), the buttons, the stack, the source of the selected frame with the pc highlight (TextEditor pcMark:, gliding as you step), and two inspectors: the receiver (evaluator with self bound) and the context (thisContext, arguments and temporaries with live values; its evaluator runs in the frame, so a + b ⌘P prints the sum of two temporaries).

I run in my window''s own Process, which breakpoints ignore; the debugged Process stays suspended, every other window stays live. Stepping and the pc highlight are the session''s: Over steps the selected frame by statements (DebugSession>>stepOverStatement:); Into, Through and Run to here stop at the next send, store or return and highlight exactly that. ⌘S in the source recompiles the method and restarts the frame (edit and continue). Proceed resumes the Process and closes me; closing me abandons it.

	Debugger openOn: aDebugSession

Remote names: buttons proceed restart into over through run-to-here where full-stack create unwatch remove-breakpoint breakpoints, link process, list stack, editor source, status status, inspectors receiver and context (fields value evaluator).'!

!Debugger methodsFor: 'initialization'!
setSession: aSession
	session := aSession.
	buttons := Dictionary new.
	fullStack := false.
	done := false.
	hiddenCount := 0.
	mutedFrames := IdentitySet new.
	self buildHeader.
	self buildBar.
	self buildStack.
	self buildSource.
	self buildInspectors.
	self addAll: {
		header.
		DebuggerRule new.
		bar.
		DebuggerRule new.
		(Column with: {stackHeader. stack}) fixed: 148; yourself.
		Splitter new.
		(Column with: {sourceHeader. source. status}).
		DebuggerRule new.
		(Row with: {receiverInspector. contextInspector}) separators: true; fixed: 212; yourself}.
	listener := [:event :s | self sessionEvent: event].
	session when: listener
!
buildHeader
	link := DebuggerLink new.
	link name: 'process'; tooltip: 'Show the debugged Process in the Process Browser'.
	link text: [self processText].
	link action: [self showProcess].
	header := DebuggerHeader new.
	header fixed: 58; link: link
!
buildBar
	| spacer |
	spacer := DebuggerSpacer new.
	bar := Row with: {
		(self button: 'Proceed' named: 'proceed' tip: 'Resume the Process (this Debugger closes)' action: [self proceed]) beDefault; fixed: 70; yourself.
		self button: 'Restart' named: 'restart' tip: 'Restart the selected frame at its first statement' action: [self restart].
		self button: 'Into' named: 'into' tip: 'Step into the next message send' action: [self stepInto].
		self button: 'Over' named: 'over' tip: 'Run the current statement of the selected frame' action: [self stepOver].
		self button: 'Through' named: 'through' tip: 'Like Over, but stop inside blocks of the selected frame' action: [self stepThrough].
		self button: 'Run to here' named: 'run-to-here' tip: 'Run until the selected frame reaches the caret' action: [self runToHere].
		DebuggerSeparator new.
		self button: 'Where' named: 'where' tip: 'Select the active frame and show its current statement' action: [self where].
		self button: 'Full stack' named: 'full-stack' tip: 'Show every frame down to the Process root' action: [self toggleFullStack].
		spacer.
		self button: 'Create' named: 'create' tip: 'Define the missing method in a class you choose and continue in it' action: [self openCreateMenu].
		self button: 'Unwatch' named: 'unwatch' tip: 'Remove the watchpoint that stopped this Process' action: [self removeBreakpoint].
		self button: 'Remove breakpoint' named: 'remove-breakpoint' tip: 'Remove the breakpoint that stopped this Process' action: [self removeBreakpoint].
		self button: 'Breakpoints' named: 'breakpoints' tip: 'All breakpoints and watchpoints' action: [BreakpointsBrowser open]}.
	bar spacing: 4; padding: (8 @ 5 corner: 8 @ 5); background: #paper; fixed: 30
!
button: aString named: slug tip: tipString action: aBlock
	| b |
	b := Button label: aString action: [self run: aBlock].
	b name: slug; tooltip: tipString.
	b fixed: ((b font widthOf: aString) + 16) ceiling.
	buttons at: slug put: b.
	^b
!
buildStack
	stackHeader := PaneHeader title: 'Stack' right: ''.
	stack := DebuggerStackList new.
	stack name: 'stack'; title: 'Stack'.
	stack labelBlock: [:ctx | self labelOfFrame: ctx].
	stack styleBlock: [:ctx | (mutedFrames includes: ctx) ifTrue: [#muted] ifFalse: [nil]].
	stack cellBlock: [:canvas :rect :ctx :inverted | self drawMarkOf: ctx in: rect on: canvas inverted: inverted].
	stack onSelect: [:item | item == #more ifTrue: [self toggleFullStack] ifFalse: [self selectFrame: item]]
!
buildSource
	sourceHeader := DebuggerPaneHeader new.
	sourceHeader titleFont: #code12Bold; name: 'header-source'.
	source := TextEditor new.
	source name: 'source'; title: 'Source'; methodMode: true.
	source onAccept: [:text | self accept: text].
	source onChange: [:editor | self updateStatus].
	status := StatusBar new.
	status name: 'status'
!
buildInspectors
	receiverInspector := DebuggerInspector new.
	receiverInspector setTitle: 'Receiver' placeholder: 'evaluate with self bound · ⌘D ⌘P ⌘I'.
	receiverInspector name: 'receiver'.
	receiverInspector evaluateBlock: [:text | self evaluateForReceiver: text].
	receiverInspector afterEvaluation: [self refreshAfterEvaluation].
	contextInspector := DebuggerInspector new.
	contextInspector setTitle: 'Context' placeholder: 'evaluate in this frame · temps are live'.
	contextInspector name: 'context'; defaultIndex: 2.
	contextInspector evaluateBlock: [:text | self evaluateInFrame: text].
	contextInspector afterEvaluation: [self refreshAfterEvaluation]
! !

!Debugger methodsFor: 'accessing'!
session
	^session
!
selectedContext
	^selected
!
stackList
	^stack
!
sourceEditor
	^source
!
receiverInspector
	^receiverInspector
!
contextInspector
	^contextInspector
!
buttonNamed: aString
	^buttons at: aString ifAbsent: [nil]
!
headerTitle
	^header title
!
windowTitle
	^'Debugger — ', header title
!
isDone
	^done
!
pcInterval
	"The interval highlighted in the source, or nil."
	^source pcMark isNil ifTrue: [nil] ifFalse: [source pcMark interval]
!
note
	^note
! !

!Debugger methodsFor: 'opening'!
start
	"Show the session (before my window opens, so the first frame is complete)."
	Breakpoint ignoreDuring: [
		self updateHeader.
		selected := self defaultFrame.
		self update]
!
opened
	"In my window's Process, once it runs."
	DebuggerTools ignore: self window.
	source scrollOffset: 0.
	self updatePcMark.
	stack focus.
	self scheduleTick
!
windowClosed
	"My window closed: abandon the Process unless it was proceeded."
	timer isNil ifFalse: [timer cancel. timer := nil].
	session removeListener: listener.
	done ifTrue: [^self].
	done := true.
	self abandonSession
!
abandonSession
	session isSuspended ifFalse: [^self].
	[session abandon] on: Error do: [:e | e return: nil].
	DebuggerTools restartWindowOf: session process
!
scheduleTick
	| w |
	w := self window.
	(done or: [w isNil or: [w isOpen not]]) ifTrue: [^self].
	timer := w after: 700 do: [self tick]
!
tick
	done ifTrue: [^self].
	header invalidate.
	(session process isTerminated and: [session state ~~ #terminated]) ifTrue: [self updateButtons].
	self scheduleTick
!
sessionEvent: anEvent
	"Changes made by others (another tool proceeding or abandoning the session)."
	| w |
	done ifTrue: [^self].
	(anEvent == #proceeded or: [anEvent == #terminated]) ifFalse: [^self].
	w := self window.
	(w isNil or: [w process == Processor activeProcess]) ifTrue: [^self].
	done := true.
	w close
! !

!Debugger methodsFor: 'actions'!
run: aBlock
	"Run a button's action: breakpoints ignored, the window busy meanwhile; errors become toasts."
	| w |
	done ifTrue: [^self].
	w := self window.
	(w notNil and: [w process notNil]) ifTrue: [Breakpoint ignoreProcess: w process].
	w isNil ifFalse: [w busy: true].
	[[aBlock value]
		on: Error
		do: [:e |
			Transcript show: 'Debugger: ', e messageText asString; cr.
			self toast: e messageText asString.
			e return: nil]]
		ensure: [w isNil ifFalse: [w busy: false]]
!
proceed
	done := true.
	[session proceed] on: Error do: [:e | self toast: e messageText asString. e return: nil].
	self closeWindow
!
abandon
	done := true.
	self abandonSession.
	self closeWindow
!
closeWindow
	| w |
	w := self window.
	w isNil ifFalse: [w close]
!
stepInto
	self stepWith: [:ctx | session stepInto: ctx]
!
stepThrough
	self stepWith: [:ctx | session stepThrough: ctx]
!
stepWith: aBlock
	"aBlock steps the selected frame and answers the frame to show."
	| ctx |
	self checkLive ifFalse: [^self].
	ctx := self liveSelection.
	note := nil.
	selected := aBlock value: ctx.
	self update
!
stepOver
	self stepWith: [:ctx | session stepOverStatement: ctx]
!
restart
	| ctx |
	self checkLive ifFalse: [^self].
	ctx := self liveSelection.
	selected := session restart: ctx.
	note := 'restarted'.
	self update
!
runToHere
	| ctx position |
	self checkLive ifFalse: [^self].
	ctx := self liveSelection.
	ctx == selected ifFalse: [^self toast: 'Select a frame of the stack first'].
	position := source selectionStart + 1.
	note := nil.
	selected := session runToSourcePosition: position inFrame: ctx.
	self update
!
where
	| ctx interval |
	ctx := self defaultFrame.
	ctx isNil ifTrue: [^self].
	selected := ctx.
	self update.
	stack focus.
	interval := session pcIntervalOf: ctx.
	interval isNil ifTrue: [^self].
	source pcMark: interval style: #search.
	self afterAnimationTime: 260 do: [
		(done not and: [selected == ctx]) ifTrue: [self updatePcMark]]
!
toggleFullStack
	fullStack := fullStack not.
	(buttons at: 'full-stack') on: fullStack.
	self update
!
removeBreakpoint
	| watch |
	watch := session watchpoint notNil.
	session removeBreakpoint.
	self toast: (watch
		ifTrue: ['Watchpoint removed — the object is writable again']
		ifFalse: ['Breakpoint removed — the original method is back']).
	self update
!
showProcess
	Tools openProcessBrowserSelecting: session process
!
openCreateMenu
	| b |
	session kind == #dnu ifFalse: [^self].
	b := buttons at: 'create'.
	b openMenu: (self class createMenuFor: session action: [:cls | self createIn: cls]) at: 0 @ (b height + 2)
!
openCreateMenuAt: aScreenPoint
	"The Create menu at aScreenPoint (where the Notifier's Create button was); its actions run in my window's Process."
	session kind == #dnu ifFalse: [^self].
	self worldDo: [:world |
		(world openMenu: (self class createMenuFor: session action: [:cls | self createIn: cls]) asMenuView at: aScreenPoint)
			invoker: self window]
!
createIn: aClass
	"Define the missing method in aClass (a stub), resend the message and stop at the start of the new method, with the stub's statement selected for replacing."
	| selector |
	self checkLive ifFalse: [^self].
	selector := session exception message selector.
	session createMissingMethodIn: aClass.
	Transcript show: aClass name, '>>', selector, ' created in the Debugger'; cr.
	note := aClass name, '>>', selector, ' created'.
	selected := session interruptedContext.
	self update.
	self selectInSource: 'self shouldBeImplemented'.
	source focus
!
selectInSource: aString
	| i |
	i := source text indexOfSubCollection: aString startingAt: 1.
	i = 0 ifFalse: [source selectFrom: i to: i + aString size - 1]
!
accept: aString
	"⌘S: edit and continue."
	| ctx oldSelector newMethod |
	(self isEditable: selected) ifFalse: [self toast: 'This frame is read-only'. ^false].
	ctx := selected.
	oldSelector := ctx home method selector.
	newMethod := [[ctx method selector == #DoIt
			ifTrue: [session recompileDoIt: aString inFrame: ctx]
			ifFalse: [session recompile: aString inFrame: ctx]]
		on: SyntaxError
		do: [:e | self showSyntaxError: e. ^false]]
			on: Error do: [:e | self toast: e messageText. ^false].
	Transcript show: (newMethod selector == #DoIt ifTrue: ['do it'] ifFalse: [newMethod methodClass name, '>>', newMethod selector]), ' recompiled in the Debugger'; cr.
	newMethod selector == oldSelector
		ifTrue: [
			note := 'accepted · frame restarted'.
			selected := session interruptedContext]
		ifFalse: [note := 'accepted as #', newMethod selector, ' (a new method)'].
	shownMethod := nil.
	self update.
	^true
!
showSyntaxError: aSyntaxError
	| pos interval |
	pos := (aSyntaxError position ifNil: [source text size + 1]) min: source text size + 1.
	source selectFrom: pos to: pos - 1.
	interval := source insertAfterSelection: ' ‹', aSyntaxError messageText asString, ' →›' select: true.
	source addMark: interval style: #error
!
checkLive
	session isSuspended ifTrue: [^true].
	self toast: 'The Process is ', (DebuggerTools processStateOf: session process), ' — nothing to step'.
	self updateButtons.
	^false
!
liveSelection
	"The selected frame if it is still on the stack, else the top one."
	(selected notNil and: [selected ~~ #more and: [selected isDead not and: [session fullStack includes: selected]]])
		ifTrue: [^selected].
	^session interruptedContext
! !

!Debugger methodsFor: 'evaluating'!
evaluateForReceiver: aString
	| rcvr |
	rcvr := selected isNil ifTrue: [nil] ifFalse: [selected receiver].
	^Breakpoint ignoreDuring: [Compiler evaluate: aString for: rcvr bindings: nil]
!
evaluateInFrame: aString
	^session evaluate: aString inFrame: self liveSelection
!
refreshAfterEvaluation
	done ifTrue: [^self].
	self updateInspectors.
	stack invalidate
! !

!Debugger methodsFor: 'updating'!
update
	"Bring every pane up to date with the session, in place."
	done ifTrue: [^self].
	(session process isTerminated or: [session interruptedContext isNil]) ifTrue: [
		done := true.
		self toast: 'Process ', session process name printString, ' finished'.
		^self closeWindow].
	self noteStopReason.
	self updateHeader.
	self updateStack.
	self showFrame: selected.
	self updateButtons
!
updateHeader
	| title |
	"A new reason only with a new exception (an error hit while stepping); a resend after Create keeps the old one."
	(headerException notNil and: [session exception == headerException]) ifTrue: [^self].
	headerException := session exception.
	title := DebuggerTools titleFor: session.
	header iconKind: (DebuggerTools iconKindFor: session) title: title message: (DebuggerTools messageFor: session).
	self window isNil ifFalse: [self window title: self windowTitle]
!
updateStack
	| full ic icIndex start rest cut base items |
	full := session fullStack.
	ic := session interruptedContext.
	icIndex := full indexOf: ic.
	mutedFrames := IdentitySet new.
	1 to: icIndex - 1 do: [:i | mutedFrames add: (full at: i)].
	full do: [:each | each selector == #doesNotUnderstand: ifTrue: [mutedFrames add: each]].
	base := 0.
	(icIndex max: 1) to: full size do: [:i | (base = 0 and: [(full at: i) selector == #DoIt]) ifTrue: [base := i]].
	base > 0 ifTrue: [base + 1 to: full size do: [:i | mutedFrames add: (full at: i)]].
	fullStack
		ifTrue: [
			items := full asOrderedCollection.
			hiddenCount := 0]
		ifFalse: [
			"A watchpoint shows the refused store above the writing frame."
			start := (icIndex > 1 and: [session kind == #watchpoint]) ifTrue: [icIndex - 1] ifFalse: [icIndex max: 1].
			rest := full copyFrom: start to: full size.
			cut := base = 0 ifTrue: [rest size min: 8] ifFalse: [(base - start + 2 min: rest size) min: 8].
			items := (rest copyFrom: 1 to: cut) asOrderedCollection.
			hiddenCount := rest size - cut].
	hiddenCount > 0 ifTrue: [
		stack moreText: '… ', hiddenCount printString, ' more frame', (hiddenCount = 1 ifTrue: [''] ifFalse: ['s']), ' — Full stack'.
		items add: #more].
	(selected isNil or: [(items includes: selected) not]) ifTrue: [
		selected := self defaultFrame.
		(items includes: selected) ifFalse: [selected := items isEmpty ifTrue: [nil] ifFalse: [items first]]].
	stack items: items asArray.
	stack selection: selected.
	stackHeader rightText: full size printString, (full size = 1 ifTrue: [' frame'] ifFalse: [' frames'])
!
noteStopReason
	"Why the last step ended early, unless it was an error (the header shows that)."
	| reason |
	reason := session stopReason.
	reason == #blocked ifTrue: [note := 'the Process would wait here — Proceed instead'].
	reason == #unsimulatable ifTrue: [note := 'cannot step this primitive — Proceed instead'].
	reason == #limit ifTrue: [note := 'step limit reached']
!
selectFrame: aContext
	selected := aContext.
	self showFrame: aContext.
	self updateButtons
!
showFrame: ctx
	| editable method |
	(ctx isNil or: [ctx == #more]) ifTrue: [^self].
	method := ctx method.
	method == shownMethod ifFalse: [
		source text: ((session sourceOf: ctx) ifNil: ['']).
		source methodMode: method selector ~~ #DoIt.
		shownMethod := method].
	editable := self isEditable: ctx.
	source readOnly: editable not.
	self updatePcMark.
	sourceHeader title: (self labelOfFrame: ctx).
	sourceHeader rightText: (editable
		ifTrue: ['edit · ⌘S recompiles and restarts this frame']
		ifFalse: [method selector == #DoIt ifTrue: ['do it · read-only'] ifFalse: ['read-only']]).
	self updateStatus.
	self updateInspectors
!
updatePcMark
	| interval style |
	(selected isNil or: [selected == #more]) ifTrue: [^source pcMark: nil].
	interval := session pcIntervalOf: selected.
	(interval isNil or: [interval isEmpty or: [interval last > source text size]]) ifTrue: [^source pcMark: nil].
	style := (self isReturning: selected) ifTrue: [#pcReturn] ifFalse: [#pc].
	source pcMark: interval style: style
!
updateStatus
	| interval left right |
	status clear.
	(selected isNil or: [selected == #more]) ifTrue: [^self].
	interval := session pcIntervalOf: selected.
	left := interval isNil ifTrue: [''] ifFalse: ['line ', (self lineOf: interval first) printString].
	left := left, (left isEmpty ifTrue: [''] ifFalse: [' · ']), (self methodNameOf: selected).
	status add: left style: #mono.
	source isDirty ifTrue: [^status addRight: 'unaccepted · ⌘S recompiles & restarts' style: #pillDirty].
	(self isReturning: selected) ifTrue: [
		right := '↩ returning ', (DebuggerTools short: selected top).
		^status addRight: right style: #pillOk].
	note isNil ifFalse: [status addRight: note style: #pillOk]
!
updateInspectors
	| ctx rcvr rfields cfields own nargs |
	ctx := selected.
	(ctx isNil or: [ctx == #more]) ifTrue: [^self].
	rcvr := ctx receiver.
	rfields := OrderedCollection new.
	rfields add: (DebuggerField name: 'self' value: rcvr kind: #self).
	rfields add: (DebuggerField name: 'class' value: rcvr class kind: #field).
	rcvr isInteger ifTrue: [
		rfields add: (DebuggerField name: 'hex' value: (rcvr printStringRadix: 16) kind: #derived).
		rfields add: (DebuggerField name: 'digits' value: rcvr abs printString size printString kind: #derived)].
	(session receiverFieldsOf: ctx) do: [:assoc |
		rfields add: (DebuggerField name: assoc key asString value: assoc value
			kind: ((self isWatched: rcvr field: assoc key asString) ifTrue: [#watched] ifFalse: [#field]))].
	receiverInspector fieldItems: rfields.
	receiverInspector subtitle: (DebuggerTools short: rcvr).
	cfields := OrderedCollection new.
	cfields add: ((DebuggerField name: 'thisContext' value: ctx kind: #context) detail: (self describeContext: ctx); yourself).
	own := ctx tempNames size min: ctx stackp.
	nargs := ctx numArgs.
	(session tempsOf: ctx) doWithIndex: [:assoc :i |
		"Hidden temporaries of inlined loops, like (limit), are the compiler's."
		(assoc key asString beginsWith: '(') ifFalse: [
			cfields add: (DebuggerField name: assoc key asString value: assoc value
				kind: (i <= nargs ifTrue: [#arg] ifFalse: [i <= own ifTrue: [#temp] ifFalse: [#outer]]))]].
	(self isReturning: ctx) ifTrue: [
		cfields add: (DebuggerField name: '↩' value: ctx top kind: #return)].
	contextInspector fieldItems: cfields.
	contextInspector subtitle: (self labelOfFrame: ctx)
!
updateButtons
	| live dnu bp wp frame |
	live := done not and: [session isSuspended].
	frame := selected notNil and: [selected ~~ #more].
	#('proceed' 'into' 'over' 'through') do: [:each | (buttons at: each) enabled: live].
	(buttons at: 'restart') enabled: (live and: [frame]).
	(buttons at: 'run-to-here') enabled: (live and: [frame]).
	dnu := session kind == #dnu.
	bp := session breakpoint.
	wp := session watchpoint.
	(buttons at: 'create') visible: dnu.
	(buttons at: 'unwatch') visible: (wp notNil and: [(Watchpoint forObject: wp object) includes: wp]).
	(buttons at: 'remove-breakpoint') visible: (bp notNil and: [bp isInstalled]).
	(buttons at: 'full-stack') on: fullStack.
	header invalidate
! !

!Debugger methodsFor: 'describing'!
labelOfFrame: aContext
	^self class labelOfFrame: aContext
!
methodNameOf: aContext
	| cls |
	cls := aContext methodClass.
	^(cls isNil ifTrue: ['nil'] ifFalse: [cls name]), '>>', (aContext selector ifNil: ['?'])
!
describeContext: aContext
	| lf interval |
	lf := String with: Character lf.
	interval := session intervalOf: aContext.
	^'a Context', lf,
		'method: ', (self methodNameOf: aContext), lf,
		'receiver: ', (DebuggerTools short: aContext receiver), lf,
		'pc: ', (interval isNil ifTrue: ['-'] ifFalse: ['line ', (self lineOf: interval first in: aContext) printString, ', ', (DebuggerTools statementTextOf: aContext in: session)]), lf,
		'sender: ', (aContext sender isNil ifTrue: ['nil'] ifFalse: [aContext sender printString]),
		(aContext isBlockContext ifTrue: [lf, 'home: ', aContext home printString] ifFalse: [''])
!
lineOf: aPosition
	^self lineOf: aPosition inText: source text
!
lineOf: aPosition in: aContext
	^self lineOf: aPosition inText: ((session sourceOf: aContext) ifNil: [''])
!
lineOf: aPosition inText: aString
	| n |
	n := 1.
	1 to: ((aPosition - 1) min: aString size) do: [:i | (aString at: i) == Character lf ifTrue: [n := n + 1]].
	^n
!
processText
	| p |
	p := session process.
	^'Process ', p name printString, ' · ', (DebuggerTools processStateOf: p)
!
isEditable: aContext
	(aContext isNil or: [aContext == #more]) ifTrue: [^false].
	done ifTrue: [^false].
	session isSuspended ifFalse: [^false].
	aContext method selector == #DoIt ifTrue: [^true].
	^session isInstalled: aContext home method
!
isReturning: aContext
	^aContext notNil and: [aContext ~~ #more and: [aContext == session interruptedContext and: [aContext isDead not and: [aContext willReturn]]]]
!
isWatched: anObject field: aString
	^(Watchpoint forObject: anObject) anySatisfy: [:each | each fieldName isNil or: [each fieldName = aString]]
!
drawMarkOf: aContext in: aRectangle on: aCanvas inverted: inverted
	| bp |
	aContext == #more ifTrue: [^self].
	bp := Breakpoint forMethod: aContext method.
	bp isNil ifTrue: [bp := Breakpoint forObject: aContext receiver].
	bp isNil ifTrue: [^self].
	DebuggerGlyphs drawMark: (DebuggerGlyphs markKindOf: bp) enabled: bp isEnabled
		at: (aRectangle left + 4.5) @ aRectangle center y inverted: inverted on: aCanvas
!
defaultFrame
	"The frame of interest: for a doesNotUnderstand: its sender, for a watchpoint the first frame below the refused store's signal not running in the watched object, else the interrupted context."
	| ic ctx obj |
	ic := session interruptedContext.
	ic isNil ifTrue: [^nil].
	(session kind == #dnu and: [ic selector == #doesNotUnderstand: and: [ic sender notNil]]) ifTrue: [^ic sender].
	session kind == #watchpoint ifTrue: [
		obj := session exception modification object.
		ctx := ic.
		[ctx notNil and: [ctx receiver == obj or: [ctx receiver == session exception modification]]] whileTrue: [ctx := ctx sender].
		ctx notNil ifTrue: [^ctx]].
	^ic
! !

!Debugger methodsFor: 'remote control'!
remoteRole
	^#debugger
!
remoteLabel
	^header title
! !

!Debugger class methodsFor: 'describing'!
labelOfFrame: aContext
	"SmallInteger(Integer)>>gcd:, and the missing selector for doesNotUnderstand: frames."
	| text |
	aContext == #more ifTrue: [^'more'].
	text := aContext printString.
	(aContext selector == #doesNotUnderstand: and: [aContext isDead not]) ifTrue: [
		text := text, ' #', ([(aContext tempAt: 1) selector] on: Error do: [:e | e return: '?'])].
	^text
! !

!Debugger class methodsFor: 'opening'!
openOn: aSession
	^self openOn: aSession bounds: (DebuggerTools boundsFor: self defaultExtent)
!
openOn: aSession bounds: aRectangle
	| debugger window |
	debugger := self new setSession: aSession.
	window := Desktop newWindow.
	window content: debugger; bounds: (DebuggerTools clamp: aRectangle); minExtent: 600 @ 480.
	debugger start.
	window title: debugger windowTitle.
	window whenClosed: [debugger windowClosed].
	window open.
	DebuggerTools ignore: window.
	window do: [debugger opened].
	^window
!
defaultExtent
	^820 @ 700
!
createMenuFor: aSession action: aBlock
	"The Create menu of a doesNotUnderstand: session: the receiver's class and its superclasses."
	| receiverClass classes cls menu |
	receiverClass := aSession exception receiver class.
	menu := Menu title: 'Define #', aSession exception message selector, ' in…'.
	classes := OrderedCollection new.
	cls := receiverClass.
	[cls notNil and: [cls ~~ ProtoObject]] whileTrue: [
		classes add: cls.
		cls := cls superclass].
	classes do: [:c |
		menu add: c name asString
			description: (c == receiverClass ifTrue: ['the receiver''s class'] ifFalse: ['superclass'])
			action: [aBlock value: c]].
	^menu
! !
