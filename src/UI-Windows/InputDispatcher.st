Object subclass: #InputDispatcher
	instanceVariableNames: 'world displayWindow process running semaphore semaphoreIndex buffer pointer modifiers gesture pressed captureWindow hoverWindow cursor idle lastMove tooltipAsked services'
	classVariableNames: ''
	package: 'UI-Windows'!

InputDispatcher comment: 'I am the input dispatcher: a Process at priority 60 that drains the platform''s events (real ones and those injected by remote control arrive the same way), tracks the pointer and modifiers, and routes each event: pointer events to the window under the pointer (or the one that has the pointer since a press), keys and text to the topmost overlay or the active window. I do the window manager''s work myself — raise and activate on press, drag by the title bar, resize from the edges and the corner (with resize cursors), close and collapse boxes, double-click to collapse, clicks on the desk — so it stays live while a window''s Process is busy. ⌘. is reserved: it calls World>>userInterrupt. Other input sources share my Process (addService:): remote control''s sockets signal my Semaphore and I service them after the platform''s events.'!

!InputDispatcher methodsFor: 'initialization'!
setWorld: aWorld
	world := aWorld.
	displayWindow := aWorld displayWindow.
	running := false.
	idle := true.
	buffer := Array new: 8.
	pointer := 0 @ 0.
	modifiers := Modifiers none.
	cursor := #arrow.
	lastMove := 0.
	tooltipAsked := true.
	services := #()
! !

!InputDispatcher methodsFor: 'accessing'!
pointer
	^pointer
!
modifiers
	^modifiers
!
process
	^process
!
isIdle
	^idle
!
gesture
	"nil, or the WindowGesture in progress (a DragGesture or a ResizeGesture)."
	^gesture
! !

!InputDispatcher methodsFor: 'services'!
addService: anObject
	"Serve anObject, another input source (remote control): it signals my Semaphore when it has input (hostOn:index:by:) and I send it service after each wakeup, in my Process."
	services := services copyWith: anObject.
	running ifTrue: [anObject hostOn: semaphore index: semaphoreIndex by: self]
!
removeService: anObject
	(services includes: anObject) ifFalse: [^self].
	services := services copyWithout: anObject.
	anObject unhost
!
services
	^services
! !

!InputDispatcher methodsFor: 'starting and stopping'!
start
	running ifTrue: [^self].
	running := true.
	semaphore := Semaphore new.
	semaphoreIndex := Smalltalk vm registerExternalSemaphore: semaphore.
	DisplayWindow inputSemaphoreIndex: semaphoreIndex.
	process := [self run] newProcess.
	process priority: self class priority; name: 'input dispatcher'.
	process resume.
	services do: [:each | each hostOn: semaphore index: semaphoreIndex by: self]
!
stop
	running := false.
	services do: [:each | each unhost].
	DisplayWindow inputSemaphoreIndex: 0.
	Smalltalk vm unregisterExternalSemaphore: semaphoreIndex.
	semaphoreIndex := nil.
	(process notNil and: [process ~~ Processor activeProcess]) ifTrue: [process terminate].
	process := nil
!
abandon
	running := false.
	services := #().
	Smalltalk vm unregisterExternalSemaphore: semaphoreIndex.
	process isNil ifFalse: [process terminate].
	process := nil
! !

!InputDispatcher methodsFor: 'running'!
run
	[running] whileTrue: [
		idle := false.
		[(DisplayWindow nextEventInto: buffer) notNil] whileTrue: [
			[self handle: buffer] on: Error do: [:e |
				Transcript show: 'InputDispatcher error: ', (Smalltalk errorReportFor: e); cr.
				e return: nil]].
		"The platform's events are delivered: input services (remote control) may wait for the image to settle."
		idle := true.
		services do: [:each |
			[each service] on: Error do: [:e |
				Transcript show: 'InputDispatcher service error: ', (Smalltalk errorReportFor: e); cr.
				e return: nil]].
		idle := true.
		semaphore wait]
!
handle: anArray
	"Decode a platform event Array of my host window and dispatch the event (UIEvent>>dispatchTo:)."
	| id event |
	id := anArray at: 8.
	(id notNil and: [displayWindow windowId notNil and: [id ~= displayWindow windowId]]) ifTrue: [^self].
	event := UIEvent fromPlatform: anArray.
	event isNil ifFalse: [event dispatchTo: self]
! !

!InputDispatcher methodsFor: 'host window'!
hostResized: aPoint
	world hostResized: aPoint
!
quitRequested
	world quitRequested
!
displayScaleChanged: aNumber
	world displayScaleChanged: aNumber
!
exposed
	world changed
! !

!InputDispatcher methodsFor: 'pointer'!
handlePointer: anEvent
	modifiers := anEvent modifiers.
	pointer := anEvent globalPosition.
	anEvent isMove ifTrue: [^self pointerMoved: anEvent].
	anEvent isDown ifTrue: [^self pointerDown: anEvent].
	anEvent isUp ifTrue: [^self pointerUp: anEvent].
	anEvent isWheel ifTrue: [^self wheel: anEvent]
!
pointerDown: anEvent
	| p overlay w zone |
	p := anEvent globalPosition.
	self noteRemoteClick: p.
	world hideTooltip.
	tooltipAsked := true.
	overlay := world overlayAt: p.
	overlay isNil ifFalse: [
		captureWindow := overlay.
		^self send: anEvent to: overlay].
	world overlays isEmpty ifFalse: [world closeMenus].
	w := world windowAt: p.
	w isNil ifTrue: [^world desktopClickedAt: p button: anEvent button].
	world activate: w.
	zone := w zoneAt: p.
	(zone == #close or: [zone == #collapse]) ifTrue: [^pressed := Array with: w with: zone].
	zone == #title ifTrue: [
		anEvent clickCount = 2 ifTrue: [^w toggleCollapse].
		^gesture := DragGesture window: w grabOffset: p - w bounds origin].
	(zone notNil and: [zone beginsWith: 'resize']) ifTrue: [
		^gesture := ResizeGesture window: w zone: zone start: p bounds: w bounds].
	zone == #content ifTrue: [
		captureWindow := w.
		^self send: anEvent to: w]
!
pointerMoved: anEvent
	| p w zone |
	p := anEvent globalPosition.
	lastMove := Time millisecondClockValue.
	tooltipAsked := false.
	world tooltip isNil ifFalse: [world hideTooltip].
	gesture isNil ifFalse: [^self continueGesture: p].
	captureWindow notNil ifTrue: [
		captureWindow isOpen ifFalse: [captureWindow := nil. ^self].
		self send: anEvent to: captureWindow.
		^self setCursor: captureWindow contentCursor].
	w := world overlayAt: p.
	w isNil ifTrue: [w := world windowAt: p].
	zone := w isNil ifFalse: [w zoneAt: p].
	self hover: (zone == #content ifTrue: [w]) event: anEvent.
	w isNil ifTrue: [^self setCursor: #arrow].
	zone == #content ifTrue: [
		self send: anEvent to: w.
		^self setCursor: w contentCursor].
	self setCursor: (self cursorForZone: zone)
!
pointerUp: anEvent
	| p w |
	p := anEvent globalPosition.
	gesture isNil ifFalse: [^self endGesture: p].
	pressed isNil ifFalse: [
		w := pressed first.
		((w zoneAt: p) == pressed last and: [w isOpen]) ifTrue: [
			pressed last == #close ifTrue: [w close].
			pressed last == #collapse ifTrue: [w toggleCollapse]].
		pressed := nil.
		^self].
	captureWindow isNil ifFalse: [
		w := captureWindow.
		captureWindow := nil.
		w isOpen ifTrue: [self send: anEvent to: w]]
!
wheel: anEvent
	| w |
	w := world overlayAt: anEvent globalPosition.
	w isNil ifTrue: [w := world windowAt: anEvent globalPosition].
	(w notNil and: [(w zoneAt: anEvent globalPosition) == #content]) ifTrue: [self send: anEvent to: w]
!
continueGesture: p
	"The window may have closed meanwhile: that ends the gesture."
	gesture window isOpen
		ifTrue: [gesture pointerMoved: p]
		ifFalse: [gesture := nil]
!
endGesture: p
	gesture window isOpen ifTrue: [gesture pointerReleased: p].
	gesture := nil
!
hover: aWindowOrNil event: anEvent
	| old |
	old := hoverWindow.
	old == aWindowOrNil ifTrue: [^self].
	hoverWindow := aWindowOrNil.
	(old notNil and: [old isOpen]) ifTrue: [self send: (anEvent withType: #leave) to: old]
!
pointerLeft
	hoverWindow isNil ifFalse: [
		hoverWindow isOpen ifTrue: [
			self send: (PointerEvent type: #leave at: pointer) to: hoverWindow].
		hoverWindow := nil].
	self setCursor: #arrow
!
focusLost
	gesture := nil.
	pressed := nil.
	captureWindow isNil ifFalse: [
		captureWindow isOpen ifTrue: [
			self send: ((PointerEvent type: #up at: pointer) globalPosition: pointer; yourself) to: captureWindow].
		captureWindow := nil]
!
send: aPointerEvent to: aWindow
	"Hand a copy of aPointerEvent, localized to aWindow's content, to aWindow's queue."
	| e |
	e := aPointerEvent at: aPointerEvent globalPosition - aWindow contentOrigin.
	e globalPosition: aPointerEvent globalPosition.
	aWindow enqueueEvent: e
!
cursorForZone: aSymbol
	(aSymbol == #resizeL or: [aSymbol == #resizeR]) ifTrue: [^#resizeEW].
	aSymbol == #resizeB ifTrue: [^#resizeNS].
	aSymbol == #resizeBR ifTrue: [^#resizeNWSE].
	^#arrow
!
setCursor: aSymbol
	| s |
	s := aSymbol ifNil: [#arrow].
	s == cursor ifTrue: [^self].
	cursor := s.
	[world cursor: s] on: Error do: [:e | e return: nil]
!
cursor
	^cursor
!
noteRemoteClick: aPoint
	"Show a ring where remote input clicks."
	| device |
	device := RemoteInputDevice default.
	(device pointer notNil and: [device pointer = aPoint]) ifTrue: [
		world remotePointer ringAt: aPoint time: Animation now]
!
checkTooltipAt: ms
	"Called by the compositor: after the pointer rested 600 ms over a window's content, ask it for a tooltip."
	| w |
	tooltipAsked ifTrue: [^self].
	(Time millisecondClockValue - lastMove) < 600 ifTrue: [^self].
	tooltipAsked := true.
	(gesture notNil or: [captureWindow notNil]) ifTrue: [^self].
	w := world overlayAt: pointer.
	w isNil ifTrue: [w := world windowAt: pointer].
	(w notNil and: [(w zoneAt: pointer) == #content]) ifTrue: [
		w requestTooltipAt: pointer - w contentOrigin]
! !

!InputDispatcher methodsFor: 'keyboard'!
handleKey: anEvent
	| target |
	modifiers := anEvent modifiers.
	(anEvent isDown and: [anEvent key = $. and: [anEvent modifiers commandKey]]) ifTrue: [^world userInterrupt].
	target := world keyTarget.
	target isNil ifFalse: [target enqueueEvent: anEvent]
!
handleText: anEvent
	| target |
	modifiers := anEvent modifiers.
	target := world keyTarget.
	target isNil ifFalse: [target enqueueEvent: anEvent]
! !

!InputDispatcher class methodsFor: 'accessing'!
priority
	^60
! !

!InputDispatcher class methodsFor: 'instance creation'!
world: aWorld
	^self new setWorld: aWorld
! !
