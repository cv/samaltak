Object subclass: #Window
	instanceVariableNames: 'title bounds content world layer process queue state invalid fullRedraw redrawQueued resizePending busy busyLabel collapsed expandedExtent keyboardFocus capture hover contentCursor remoteName focusAmount minExtent animations tickPending handlingSince lastInputTime closeActions drawError showsSuspended shownChip lastClick'
	classVariableNames: 'ErrorHandler'
	package: 'UI-Windows'!

Window comment: 'I am an overlapping window of the World: a Blue Book frame (title bar with stripes and the black title tab when focused, close and collapse boxes, the process chip, a resize grip) around a content View, with my own Process (priority 40, named after my title) running an event loop over a SharedQueue.

	Window new title: ''Hello''; content: aView; bounds: (100@100 extent: 400@300); open

My Process takes the next item from my queue and sends it deliverTo: self (a block runs, a WindowTimer fires, a UIEvent is dispatched to the content), delivers events to the content (hit testing with viewAt:, bubbling to owners, pointer capture between down and up, hover enter/leave, keyboard focus, multi-clicks only on the same view and item), steps my animations on compositor frames, and redraws when invalid: the content draws into a fresh Canvas (my size × the display scale) whose frozen DisplayList I publish to my Layer. Views that did not change since the last redraw replay what they drew then (View>>drawRetainedOn:); after invalidate everything is drawn anew. The Compositor and the InputDispatcher never wait for me: while I am busy I keep my last frame, stay draggable and resizable, and my queued events are kept.

Code touching my widgets runs in my Process: do: aBlock enqueues a block, sync: aBlock waits for its value. invalidate (any Process) asks for a redraw. busy: shows the busy indicator; I also show it when an event takes longer than 250 ms. Bounds are screen points of the outer frame; content coordinates start below the title bar (contentOrigin).

Unhandled errors in my Process go to Window errorHandler (a block [:exception :window | ...], set by the tools to open a debugger); without one I report the error (Transcript and a toast) and restart my event loop. Errors while drawing are shown in place of the content.'!

!Window methodsFor: 'initialization'!
initialize
	title := 'Untitled'.
	bounds := 120 @ 80 extent: 480 @ 320.
	state := #new.
	invalid := true.
	fullRedraw := true.
	redrawQueued := false.
	resizePending := false.
	busy := false.
	collapsed := false.
	focusAmount := 0.
	minExtent := 160 @ 60.
	animations := OrderedCollection new.
	tickPending := false.
	queue := SharedQueue new.
	layer := Layer new.
	contentCursor := #arrow.
	closeActions := OrderedCollection new.
	lastInputTime := 0
! !

!Window methodsFor: 'accessing'!
title
	^title
!
title: aString
	title := aString asString.
	process isNil ifFalse: [process name: title].
	self changed
!
content
	^content
!
content: aView
	content isNil ifFalse: [content owner: nil].
	content := aView.
	aView isNil ifFalse: [
		aView owner: self.
		aView bounds: (0 @ 0 extent: self contentExtent)].
	self invalidate
!
bounds
	"My outer frame in screen points."
	^bounds
!
bounds: aRectangle
	| r resized |
	r := self constrain: aRectangle.
	r = bounds ifTrue: [^self].
	resized := bounds isNil or: [bounds extent ~= r extent].
	bounds := r.
	(resized and: [state == #open]) ifTrue: [self queueResize].
	self changed
!
extent
	^bounds extent
!
extent: aPoint
	self bounds: (bounds origin extent: aPoint)
!
position
	^bounds origin
!
moveTo: aPoint
	self bounds: (aPoint extent: bounds extent)
!
minExtent
	^minExtent
!
minExtent: aPoint
	minExtent := aPoint
!
world
	^world
!
window
	^self
!
layer
	^layer
!
process
	^process
!
queue
	^queue
!
remoteName
	"My stable ref slug (w1, w2, ...)."
	^remoteName
!
remoteName: aString
	remoteName := aString
!
focusAmount
	"0 unfocused .. 1 focused (animated by the compositor)."
	^focusAmount
!
focusAmount: aNumber
	focusAmount := aNumber
!
contentCursor
	"The cursor my content asked for at the pointer."
	^contentCursor
!
lastInputTime
	^lastInputTime
!
keyboardFocus
	^keyboardFocus
!
keyboardFocus: aViewOrNil
	"Give aView the keyboard focus (in my Process)."
	| old |
	old := keyboardFocus.
	old == aViewOrNil ifTrue: [^self].
	keyboardFocus := aViewOrNil.
	old isNil ifFalse: [old focusLost].
	aViewOrNil isNil ifFalse: [aViewOrNil focusGained].
	self invalidate
!
clipboard
	^world clipboard
!
clipboard: aString
	world clipboard: aString
!
clipboardData: mime
	^world clipboardData: mime
!
textInputArea: aRectangle cursor: x
	"Screen points (View>>screenPointFrom:)."
	world isNil ifFalse: [world textInputArea: aRectangle cursor: x]
!
busyLabel
	^busyLabel
!
busyLabel: aStringOrNil
	"Shown in the title bar while busy (default 'busy')."
	busyLabel := aStringOrNil.
	self changed
!
whenClosed: aBlock
	closeActions add: aBlock
! !

!Window methodsFor: 'geometry'!
titleBarHeight
	^21
!
contentTop
	"Frame (1) + title bar (21) + rule (1)."
	^23
!
contentRectInWindow
	"The content area in my own coordinates (0@0 = my top-left)."
	^1 @ self contentTop corner: (bounds width - 1) @ (bounds height - 1)
!
contentOrigin
	"The screen point of my content's 0@0."
	^bounds origin + self contentRectInWindow origin
!
contentBounds
	^self contentRectInWindow translateBy: bounds origin
!
contentExtent
	^self contentRectInWindow extent max: 0 @ 0
!
collapsedHeight
	^self contentTop
!
constrain: aRectangle
	"Keep my extent at least minExtent (collapsed: title bar only)."
	| w h |
	w := aRectangle width max: minExtent x.
	h := collapsed
		ifTrue: [self collapsedHeight]
		ifFalse: [aRectangle height max: minExtent y].
	^aRectangle origin extent: w @ h
!
closeBoxRect
	"In my coordinates."
	^7 @ 6 extent: 11 @ 11
!
collapseBoxRect
	^(bounds width - 18) @ 6 extent: 11 @ 11
!
chipRect
	"The process chip (just its dot unless busy or suspended)."
	^self chipRectWidth: self chipWidth
!
chipRectWidth: w
	| right |
	right := self collapseBoxRect left - 5.
	^(right - w) @ 4 extent: w @ 15
!
chipWidth
	| label |
	label := self chipLabel.
	label isNil ifTrue: [^16].
	^5 + 9 + 5 + (Font smallItalic widthOf: label) + 6
!
chipLabel
	| p |
	p := process.
	(showsSuspended == true or: [p notNil and: [p isSuspended]]) ifTrue: [^'suspended'].
	self isBusy ifTrue: [^busyLabel ifNil: ['busy']].
	^nil
!
resizeGripRect
	^(bounds width - 11) @ (bounds height - 11) extent: 9 @ 9
!
zoneAt: aScreenPoint
	"The window-manager zone at aScreenPoint: #close #collapse #title #resizeL #resizeR #resizeB #resizeBR #content #frame, or nil when outside (resize zones reach 3 points beyond my frame)."
	| p w h |
	p := aScreenPoint - bounds origin.
	w := bounds width.
	h := bounds height.
	(p x < -3 or: [p y < 0 or: [p x >= (w + 3) or: [p y >= (h + 3)]]]) ifTrue: [^nil].
	((self closeBoxRect outsetBy: 2) containsPoint: p) ifTrue: [^#close].
	((self collapseBoxRect outsetBy: 2) containsPoint: p) ifTrue: [^#collapse].
	p y < self contentTop ifTrue: [
		(p x < 0 or: [p x >= w]) ifTrue: [^collapsed ifTrue: [nil] ifFalse: [p x < 0 ifTrue: [#resizeL] ifFalse: [#resizeR]]].
		^#title].
	collapsed ifTrue: [^nil].
	(p x >= (w - 14) and: [p y >= (h - 14)]) ifTrue: [^#resizeBR].
	p x >= (w - 4) ifTrue: [^#resizeR].
	p x < 4 ifTrue: [^#resizeL].
	p y >= (h - 4) ifTrue: [^#resizeB].
	(self contentRectInWindow containsPoint: p) ifTrue: [^#content].
	^#frame
!
containsPoint: aScreenPoint
	^(self zoneAt: aScreenPoint) notNil
! !

!Window methodsFor: 'testing'!
isWindow
	^true
!
isOverlay
	^false
!
isOpen
	^state == #open
!
isClosed
	^state == #closed or: [state == #closing]
!
isCollapsed
	^collapsed
!
isFocused
	^world notNil and: [world activeWindow == self]
!
isBusy
	"Busy: set with busy:, or handling one event for more than 250 ms."
	| since |
	busy ifTrue: [^true].
	since := handlingSince.
	^since notNil and: [Time microsecondClockValue - since > 250000]
!
hasPendingWork
	"Events or messages queued, or handling one."
	^handlingSince notNil or: [queue isEmpty not]
!
wantsFrames
	^animations notEmpty
!
isAnimatingForever
	"Answer whether a frame animation (requestAnimationFrames: aBlock) is running."
	^animations anySatisfy: [:each | each isFrameAnimation and: [each isFinished not]]
!
processState
	"waiting, running, busy, suspended or terminated."
	| p |
	p := process.
	(p isNil or: [p isTerminated]) ifTrue: [^'terminated'].
	p isSuspended ifTrue: [^'suspended'].
	self isBusy ifTrue: [^'busy'].
	(p isActiveProcess or: [p isRunnable]) ifTrue: [^'running'].
	^'waiting'
! !

!Window methodsFor: 'opening and closing'!
open
	"Open me in the current World (World>>worldForNewWindow:: an application's AppWorld gives me a host window of my own)."
	World current isNil ifTrue: [^self openIn: nil].
	^self openIn: (World current worldForNewWindow: self)
!
openIn: aWorld
	state == #new ifFalse: [^self].
	aWorld isNil ifTrue: [^self error: 'No World to open in'].
	world := aWorld.
	state := #open.
	bounds := self constrain: bounds.
	self startProcess.
	self addToWorld.
	self queueResize.
	^self
!
startProcess
	process := [self eventLoop] newProcess.
	process priority: self class processPriority; name: title; window: self.
	process errorHandler: [:ex | self handleError: ex].
	process resume
!
close
	"Close me (any Process): my layer fades out, my Process ends."
	| p |
	state == #open ifFalse: [^self].
	state := #closing.
	self removeFromWorld.
	closeActions do: [:each | [each cull: self] on: Error do: [:e | e return: nil]].
	state := #closed.
	p := process.
	(p isNil or: [p isTerminated]) ifFalse: [p terminate]
!
addToWorld
	world addWindow: self
!
removeFromWorld
	world removeWindow: self
!
focus
	"Raise and activate me."
	world isNil ifFalse: [world activate: self]
!
collapse
	collapsed ifTrue: [^self].
	expandedExtent := bounds extent.
	collapsed := true.
	bounds := bounds origin extent: bounds width @ self collapsedHeight.
	self changed
!
expand
	collapsed ifFalse: [^self].
	collapsed := false.
	self bounds: (bounds origin extent: (expandedExtent ifNil: [bounds width @ 200])).
	self queueResize
!
toggleCollapse
	collapsed ifTrue: [self expand] ifFalse: [self collapse]
!
resumed
	"My World resumed after an image restart (World>>resumeHidden:): my layer is rendered again; animations started on the old clock jump to their end."
	layer finishAnimations; markNeedsRender.
	handlingSince isNil ifFalse: [handlingSince := Time microsecondClockValue].
	self do: [
		animations do: [:each | each isFrameAnimation ifFalse: [each finish]].
		self invalidate]
! !

!Window methodsFor: 'scheduling'!
do: aBlock
	"Run aBlock in my Process (after the events already queued)."
	queue nextPut: aBlock
!
sync: aBlock
	"Run aBlock in my Process and answer its value (at most 10 s). An Error in aBlock is signaled again here, with its stack in my Process (Exception>>freeze)."
	| done result error |
	Processor activeProcess == process ifTrue: [^aBlock value].
	done := Semaphore new.
	self do: [[result := aBlock on: Error do: [:e | error := e freeze. e return: nil]] ensure: [done signal]].
	(done waitTimeoutMSecs: 10000) ifTrue: [^self error: 'Window ', title printString, ' did not answer within 10 s'].
	error isNil ifFalse: [^error resignal].
	^result
!
invalidate
	"Ask for a redraw of everything (any Process)."
	fullRedraw := true.
	invalid := true.
	Processor activeProcess == process ifTrue: [^self].
	redrawQueued ifFalse: [self queueRedraw]
!
restyle
	"Drawing code or the look changed: draw my content anew (no replays of retained drawing) and my chrome (any Process)."
	layer isNil ifFalse: [layer chromeKey: nil; markNeedsRender].
	self invalidate
!
redrawChanged
	"A view of mine invalidated itself: redraw, replaying the views that did not change. From another Process redraw everything (mine may be recording that view right now)."
	Processor activeProcess == process ifFalse: [^self invalidate].
	invalid := true
!
queueRedraw
	redrawQueued := true.
	queue nextPut: [redrawQueued := false. invalid := true]
!
queueResize
	resizePending ifTrue: [^self].
	resizePending := true.
	queue nextPut: [self layoutContent]
!
enqueueEvent: anEvent
	"Called by the InputDispatcher."
	lastInputTime := Animation now.
	queue nextPut: anEvent
!
busy: aBoolean
	busy := aBoolean == true.
	self changed
!
showsSuspended
	^showsSuspended == true
!
showSuspended: aBoolean
	"Show the suspended chip in my title bar although my Process runs: e.g. a Workspace whose do-it is stopped in a debugger."
	showsSuspended := aBoolean == true.
	self changed
!
animate: anAnimation
	"Step anAnimation in my Process on every compositor frame (I redraw after each step what its block invalidated); answer it."
	Processor activeProcess == process
		ifTrue: [animations add: anAnimation]
		ifFalse: [self do: [animations add: anAnimation]].
	self changed.
	^anAnimation
!
requestAnimationFrames: aBlockOrAnimation
	"Redraw every compositor frame while it runs: an Animation, or a block [:ms | ... true to continue]. Answer the Animation (stop it to end)."
	^self animate: (aBlockOrAnimation isBlock
		ifTrue: [Animation everyFrame: aBlockOrAnimation]
		ifFalse: [aBlockOrAnimation])
!
after: milliseconds do: aBlock
	"Run aBlock in my Process after milliseconds; answer a WindowTimer (cancel it to prevent that)."
	^WindowTimer after: milliseconds do: aBlock in: self
!
every: milliseconds do: aBlock
	"Run aBlock in my Process every milliseconds while I am open; answer the WindowTimer (cancel stops it)."
	^WindowTimer every: milliseconds do: aBlock in: self
!
enqueue: anItem
	"Post anItem into my event queue: anything that understands deliverTo: (a block, a WindowTimer, a UIEvent)."
	queue nextPut: anItem
!
postFrameTick: ms
	"Called by the Compositor once per frame while I have animations (at most one tick queued)."
	tickPending ifTrue: [^self].
	tickPending := true.
	queue nextPut: [tickPending := false. self stepAnimationsAt: ms]
!
requestTooltipAt: aContentPoint
	"Called by the InputDispatcher when the pointer rested at aContentPoint."
	self do: [self showTooltipAt: aContentPoint]
!
changed
	world isNil ifFalse: [world changed]
! !

!Window methodsFor: 'event loop'!
eventLoop
	| item count |
	[state == #open] whileTrue: [
		item := queue next.
		handlingSince := Time microsecondClockValue.
		self handle: item.
		count := 0.
		[count < 100 and: [(item := queue nextOrNil) notNil]] whileTrue: [
			self handle: item.
			count := count + 1].
		invalid ifTrue: [self redraw].
		handlingSince := nil]
!
handle: anItem
	anItem deliverTo: self
!
layoutContent
	resizePending := false.
	(collapsed or: [content isNil]) ifFalse: [
		content bounds: (0 @ 0 extent: self contentExtent)].
	invalid := true
!
stepAnimationsAt: ms
	| running |
	animations isEmpty ifTrue: [^self].
	running := animations select: [:each | each stepAt: ms].
	animations := running.
	invalid := true
!
redraw
	"Draw my content into a fresh Canvas and publish its DisplayList."
	| full |
	invalid := false.
	world isNil ifTrue: [^self].
	full := fullRedraw.
	fullRedraw := false.
	layer contentList: (self contentDisplayListFresh: full).
	self changed
!
contentDisplayListFresh: aBoolean
	"Draw my content (all anew if aBoolean, else replaying the views that did not change) and answer the DisplayList. My Process."
	| canvas rect |
	canvas := Canvas extent: bounds extent scale: world displayScale
		capacity: (layer contentList isNil ifTrue: [32768] ifFalse: [layer contentList byteCount + 32768]).
	(collapsed or: [content isNil]) ifFalse: [
		rect := self contentRectInWindow.
		canvas clip: rect during: [
			canvas translateBy: rect origin + content position during: [
				[aBoolean
					ifTrue: [canvas drawFresh: [content drawRetainedOn: canvas]]
					ifFalse: [content drawRetainedOn: canvas].
				 drawError := nil]
					on: Error do: [:e |
						drawError isNil ifTrue: [Transcript show: 'Error while drawing ', title printString, ': ', e messageText; cr].
						drawError := e messageText.
						fullRedraw := true.
						e return: nil]].
			drawError isNil ifFalse: [self drawErrorOn: canvas in: rect]]].
	^canvas displayList
!
retainedDrawingMismatch
	"Draw my content as my next redraw would (replaying the views that did not change) and all anew: answer nil when both draw the same quads and pixels, else what differs. For tests (any Process)."
	^self retainedDrawingMismatchAfter: []
!
retainedDrawingMismatchAfter: aBlock
	"The same, right after evaluating aBlock in my Process (e.g. stepping an animation to its middle)."
	| lists difference pixels |
	lists := self sync: [
		aBlock value.
		Array with: (self contentDisplayListFresh: fullRedraw) with: (self contentDisplayListFresh: true)].
	difference := lists first firstDifferenceFrom: lists last.
	difference isNil ifFalse: [
		^'quad ', difference first printString, ' replayed ', (difference at: 2) printString, ', drawn anew ', (difference at: 3) printString].
	pixels := world compositor sync: [lists collect: [:each | | surface bytes string |
		surface := Surface extent: each extent scale: each scale.
		surface render: each clear: Color paper.
		bytes := surface readbackBytes.
		surface release.
		string := String new: bytes size.
		string replaceFrom: 1 to: bytes size with: bytes startingAt: 1]].
	(pixels first compareWith: pixels last) = 0 ifFalse: [^'the pixels differ'].
	^nil
!
drawErrorOn: aCanvas in: aRectangle
	| box |
	box := aRectangle origin + (8 @ 8) extent: (aRectangle width - 16 min: 420) @ 40.
	aCanvas fillRect: box color: Color ink.
	aCanvas drawString: 'Error while drawing' at: box origin + (8 @ 3) font: Font uiBold color: Color paper.
	aCanvas drawString: drawError asString at: box origin + (8 @ 20) font: Font smallItalic color: Color paper
! !

!Window methodsFor: 'event dispatch'!
dispatchPointer: anEvent
	"anEvent's position is in my content coordinates."
	| p target handler |
	content isNil ifTrue: [^self].
	p := anEvent position.
	anEvent isLeave ifTrue: [^self hover: nil event: anEvent].
	anEvent isEnter ifTrue: [^self].
	target := content viewAt: p - content position.
	anEvent isMove ifTrue: [
		self hover: target event: anEvent.
		capture isNil ifFalse: [target := capture].
		self deliver: anEvent from: target.
		contentCursor := target cursorAt: (target localPointFrom: p).
		^self].
	anEvent isDown ifTrue: [
		self countClick: anEvent on: target.
		self takeFocusFor: target.
		handler := self deliver: anEvent from: target.
		capture := handler.
		(handler isNil and: [anEvent isSecondary]) ifTrue: [self openContextMenuFrom: target event: anEvent].
		^self].
	anEvent isUp ifTrue: [
		capture isNil ifFalse: [target := capture].
		capture := nil.
		self deliver: anEvent from: target.
		^self].
	anEvent isWheel ifTrue: [^self deliver: anEvent from: target]
!
countClick: aPress on: aView
	"A further click (InputDispatcher>>countClick:on:) stays one only on the view and item (View>>clickItemAt:) of my previous press."
	| key |
	key := Array with: aView with: (aView clickItemAt: (aView localPointFrom: aPress position)).
	aPress clickCount: ((aPress clickCount > 1 and: [lastClick notNil and: [lastClick first = key]])
		ifTrue: [lastClick last + 1]
		ifFalse: [1]).
	lastClick := Array with: key with: aPress clickCount
!
deliver: anEvent from: aView
	"Offer anEvent to aView, then to its owners, each with position re-localized; answer the view that handled it, or nil."
	^self bubbleFrom: aView until: [:v | (v handlePointer: (anEvent at: (v localPointFrom: anEvent position))) == true]
!
bubbleFrom: aView until: aBlock
	"Answer the first of aView and its owner Views for which aBlock answers true, or nil."
	| v |
	v := aView.
	[v notNil and: [v isView]] whileTrue: [
		(aBlock value: v) ifTrue: [^v].
		v := v owner].
	^nil
!
hover: aViewOrNil event: anEvent
	| old |
	old := hover.
	old == aViewOrNil ifTrue: [^self].
	hover := aViewOrNil.
	(old notNil and: [old window == self]) ifTrue: [
		old handlePointer: ((anEvent withType: #leave) position: (old localPointFrom: anEvent position); yourself)].
	aViewOrNil isNil ifFalse: [
		aViewOrNil handlePointer: ((anEvent withType: #enter) position: (aViewOrNil localPointFrom: anEvent position); yourself)]
!
takeFocusFor: aView
	| v |
	v := self bubbleFrom: aView until: [:each | each wantsKeyboardFocus].
	v isNil ifFalse: [self keyboardFocus: v]
!
openContextMenuFrom: aView event: anEvent
	| menu |
	(self bubbleFrom: aView until: [:v | (menu := v contextMenuAt: (v localPointFrom: anEvent position)) notNil])
		isNil ifFalse: [world openMenu: menu at: anEvent globalPosition]
!
dispatchKey: anEvent
	^self bubbleFrom: (keyboardFocus ifNil: [content]) until: [:v | (v handleKey: anEvent) == true]
!
dispatchText: anEvent
	^self bubbleFrom: (keyboardFocus ifNil: [content]) until: [:v | (v handleText: anEvent) == true]
!
dispatchTextEditing: anEvent
	^self bubbleFrom: (keyboardFocus ifNil: [content]) until: [:v | (v handleTextEditing: anEvent) == true]
!
showTooltipAt: aContentPoint
	| text |
	content isNil ifTrue: [^self].
	(self bubbleFrom: (content viewAt: aContentPoint - content position) until: [:v | (text := v tooltipAt: (v localPointFrom: aContentPoint)) notNil])
		isNil ifFalse: [world showTooltip: text at: self contentOrigin + aContentPoint + (10 @ 18)]
! !

!Window methodsFor: 'errors'!
handleError: anException
	"The errorHandler of my Process."
	ErrorHandler isNil ifFalse: [^ErrorHandler value: anException value: self].
	self reportError: anException.
	self restartProcess
!
reportError: anException
	| text |
	text := [anException messageText asString] on: Error do: [:e | e return: anException class name].
	Transcript show: 'Error in window ', title printString, ': ', text; cr.
	world isNil ifFalse: [world toast: 'Error in ', title, ': ', text]
!
restartProcess
	"Continue my event loop in a fresh Process; terminate the active one if it was mine."
	| old |
	old := process.
	handlingSince := nil.
	capture := nil.
	tickPending := false.
	state == #open ifTrue: [self startProcess].
	invalid := true.
	self queueRedraw.
	(old notNil and: [old ~~ process]) ifTrue: [old terminate]
! !

!Window methodsFor: 'chrome'!
chromeKey
	"What my chrome depends on; the compositor re-renders my layer when it changes."
	^Array with: bounds extent with: (focusAmount * 50) rounded with: title with: collapsed
!
drawChromeOn: c
	"Frame, title bar and grip in my coordinates (the content was drawn below)."
	| w h bar |
	w := bounds width.
	h := bounds height.
	c strokeRect: (0 @ 0 extent: w @ h) color: Color ink width: 1.
	bar := 1 @ 1 extent: (w - 2) @ self titleBarHeight.
	c fillRect: bar color: Color paper.
	c fillRect: (1 @ (bar bottom) extent: (w - 2) @ 1) color: Color ink.
	self drawTitleOn: c in: bar.
	self drawBoxesOn: c.
	collapsed ifFalse: [self drawGripOn: c]
!
drawTitleOn: c in: bar
	"The title tab between the close box and the chip; when focused (f: focus amount) black, with stripes on both sides."
	| f titleFont leftEnd rightStart label tabWidth tab |
	f := focusAmount.
	titleFont := Font title.
	leftEnd := self closeBoxRect right + 5.
	rightStart := self chipRectStatic left - 5.
	label := self class truncate: title to: rightStart - leftEnd - 24 - 16 font: titleFont.
	tabWidth := (titleFont widthOf: label) + 16.
	tab := ((leftEnd + rightStart - tabWidth) / 2) rounded @ (bar top + 3) extent: tabWidth rounded @ 16.
	f > 0 ifTrue: [
		c alpha: f during: [
			c pattern: #stripes in: (leftEnd @ (bar top + 5) corner: (tab left - 5) @ (bar top + 16)).
			c pattern: #stripes in: ((tab right + 5) @ (bar top + 5) corner: rightStart @ (bar top + 16)).
			c fillRect: tab color: Color ink]].
	c drawString: label at: (tab left + 8) @ (bar top + 3) font: titleFont color: ((Color named: #ink3) mixed: f with: Color paper)
!
drawBoxesOn: c
	"The close and collapse boxes and the chip's dot, over the stripes."
	| f ink chip |
	f := focusAmount.
	ink := (Color named: #ink4) mixed: f with: Color ink.
	{self closeBoxRect. self collapseBoxRect} do: [:box |
		c fillRect: (box outsetBy: 2) color: (Color paper alpha: f).
		c fillRect: box color: Color paper.
		c strokeRect: box color: ink width: 1].
	chip := self chipRectStatic.
	c fillRect: (chip outsetBy: 2) color: (Color paper alpha: f).
	c fillRect: chip color: Color paper.
	c strokeRect: self dotRect color: ink width: 1
!
chipRectStatic
	^self chipRectWidth: 16
!
dotRect
	| chip |
	chip := self chipRectStatic.
	^(chip left + 5) @ (chip top + 5) extent: 5 @ 5
!
drawGripOn: c
	"Three diagonal hairlines in the bottom-right corner."
	| g |
	g := self resizeGripRect.
	#(0.495 0.705 0.915) do: [:f |
		| d |
		d := 18 * f - 9.
		c line: (g left + d) @ g bottom to: g right @ (g top + d) color: Color ink width: 0.9]
!
chromeDisplayListScale: aNumber
	| canvas |
	canvas := Canvas extent: bounds extent scale: aNumber.
	self drawChromeOn: canvas.
	^canvas displayList
!
drawDecorationsOn: c time: ms
	"Dynamic parts drawn by the compositor every frame over my layer (my coordinates): the busy bar and chip, the suspended chip, the input flash."
	| label |
	label := self chipLabel.
	label isNil ifTrue: [
		(ms - lastInputTime) < 160 ifTrue: [c fillRect: self dotRect color: Color ink].
		^self].
	label = 'suspended'
		ifTrue: [self drawSuspendedChip: label on: c]
		ifFalse: [self drawBusy: label on: c time: ms]
!
drawSuspendedChip: label on: c
	| chip |
	chip := self chipRect.
	c fillRect: (chip outsetBy: 2) color: Color paper.
	c fillRect: chip color: Color ink.
	c fillRect: ((chip left + 5) @ (chip top + 5) extent: 5 @ 5) color: Color paper.
	c drawString: label at: (chip left + 15) @ (chip top - 1) font: Font smallItalic color: Color paper
!
drawBusy: label on: c time: ms
	"The stripe moving under the title bar and the spinning chip."
	| chip x y angle |
	collapsed ifFalse: [
		c clip: (1 @ self contentTop extent: (bounds width - 2) @ 2) during: [
			x := (ms / 400.0 * 8) \\ 8.
			c pattern: #diagonalStripes in: ((1 - 8 + x) @ self contentTop extent: (bounds width + 8) @ 2) color: Color ultramarine]].
	chip := self chipRect.
	c fillRect: (chip outsetBy: 2) color: Color paper.
	x := chip left + 9.5.
	y := chip top + 7.5.
	angle := ms / 700.0 * 2 * Float pi.
	0 to: 8 do: [:i |
		| a0 a1 |
		a0 := angle + (i * 0.5236).
		a1 := a0 + 0.5236.
		c line: (x + (3.75 * a0 cos)) @ (y + (3.75 * a0 sin)) to: (x + (3.75 * a1 cos)) @ (y + (3.75 * a1 sin)) color: Color ultramarine width: 1.5].
	c drawString: label at: (chip left + 19) @ (chip top - 1) font: Font smallItalic color: Color ultramarine
!
needsDecorations: ms
	^self chipLabel notNil or: [(ms - lastInputTime) < 200]
!
decorationsNeedFrameAt: ms
	"Whether my decorations need a new frame: the busy chip and stripe animate, the input dot fades, and the chip appeared, changed or went away; the static suspended chip needs none."
	| chip |
	chip := self chipLabel.
	chip = shownChip ifFalse: [shownChip := chip. ^true].
	^(chip notNil and: [chip ~= 'suspended']) or: [(ms - lastInputTime) < 200]
! !

!Window methodsFor: 'remote control'!
remoteRole
	^#window
!
remoteLabel
	^title
!
remoteState
	| s |
	s := OrderedCollection new.
	(content notNil and: [content respondsTo: #remoteKind]) ifTrue: [s add: 'kind=', content remoteKind asString].
	self isFocused ifTrue: [s add: 'focused'].
	collapsed ifTrue: [s add: 'collapsed'].
	s add: 'process=#', (process isNil ifTrue: ['-'] ifFalse: [process identityHash printString]), ' ', self processState.
	^s asArray
!
remoteBounds
	^bounds
!
remoteClickPoint
	"A point on my title bar (drag handle) between the close box and the stripes."
	^bounds origin + (28 @ 11)
!
remoteChildren
	| controls |
	controls := #(#close #collapse #resize) collect: [:kind | WindowControl window: self kind: kind].
	content isNil ifTrue: [^controls].
	^controls, (View remoteFlatten: (Array with: content))
! !

!Window methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a Window('; print: title; nextPut: $)
! !

!Window class methodsFor: 'accessing'!
processPriority
	^Processor userSchedulingPriority
!
errorHandler
	^ErrorHandler
!
errorHandler: aBlockOrNil
	"[:exception :window | ...] for unhandled errors in window Processes (the debugger); nil: report and restart the event loop."
	ErrorHandler := aBlockOrNil
!
truncate: aString to: width font: aFont
	"aString, cut with an ellipsis to fit width points."
	| s |
	(aFont widthOf: aString) <= width ifTrue: [^aString].
	s := aString.
	[(s graphemeClusterStartBefore: s size) > 0 and: [(aFont widthOf: s, (String with: (Character value: 8230))) > width]] whileTrue: [s := s first: (s graphemeClusterStartBefore: s size)].
	^s, (String with: (Character value: 8230))
! !

!Window class methodsFor: 'instance creation'!
title: aString content: aView bounds: aRectangle
	^self new title: aString; content: aView; bounds: aRectangle; yourself
! !

!Window methodsFor: 'screenshots'!
screenshot
	"Capture my visible desktop bounds, including chrome and any occlusion."
	self isOpen ifFalse: [self error: 'Cannot capture a closed window'].
	^world screenshot: self bounds
!
screenshotContent
	"Capture my visible content, excluding window chrome."
	self isOpen ifFalse: [self error: 'Cannot capture a closed window'].
	^world screenshot: self contentBounds
! !
