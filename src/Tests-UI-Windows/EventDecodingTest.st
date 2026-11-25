TestCase subclass: #EventDecodingTest
	instanceVariableNames: 'dispatched'
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

EventDecodingTest comment: 'Tests decoding the platform''s 8-slot event Arrays into PointerEvents, KeyEvents, TextEvents and host window events, their dispatch (I stand in for the InputDispatcher and record the handler each event sends), and Modifiers.'!

!EventDecodingTest methodsFor: 'tests'!
testPointerEvents
	| e |
	e := UIEvent fromPlatform: #(2 100 10.5 20.0 1 0 2 1).
	self assert: e isPointer.
	self assert: e type equals: #down.
	self assert: e position equals: 10.5 @ 20.0.
	self assert: e button equals: 1.
	self assert: e clickCount equals: 2.
	self assert: e timeStamp equals: 100.
	self assert: (UIEvent fromPlatform: #(2 0 0 0 3 0 1 1)) button equals: 2.
	self assert: (UIEvent fromPlatform: #(2 0 0 0 2 0 1 1)) button equals: 3.
	self assert: (UIEvent fromPlatform: #(2 0 0 0 1 2 1 1)) button equals: 2.
	e := UIEvent fromPlatform: {4. 0. 5. 5. 0. 0. 0 @ -2. 1}.
	self assert: e isWheel.
	self assert: e delta equals: 0 @ -2.
	e := UIEvent fromPlatform: #(1 0 3 4 1 0 nil 1).
	self assert: e isMove.
	self assert: e isDragging
!
testKeyAndTextEvents
	| e |
	e := UIEvent fromPlatform: #(5 0 0 0 97 9 false 1).
	self assert: e isKey.
	self assert: e isDown.
	self assert: e key equals: $a.
	self assert: e modifiers shift.
	self assert: e modifiers command.
	self assert: e modifiers commandKey.
	self deny: e modifiers control.
	self assert: (e isCommand: $a).
	self assert: (UIEvent fromPlatform: {5. 0. 0. 0. 16r40000050. 0. true. 1}) key equals: #left.
	self assert: (UIEvent fromPlatform: {5. 0. 0. 0. 16r40000050. 0. true. 1}) isRepeat.
	self assert: (UIEvent fromPlatform: #(6 0 0 0 13 0 false 1)) key equals: #return.
	self assert: (UIEvent fromPlatform: #(5 0 0 0 32 0 false 1)) key equals: #space.
	self assert: (UIEvent keyCodeFor: #escape) equals: 27.
	e := UIEvent fromPlatform: #(7 0 0 0 0 0 'é!!' 1).
	self assert: e isText.
	self assert: e string equals: 'é!!'
!
testHostEvents
	| e |
	e := UIEvent fromPlatform: {UIEvent evWindowResized. 5. 800. 600. 0. 0. nil. 1}.
	self assert: (e isKindOf: HostResizeEvent).
	self assert: e extent equals: 800 @ 600.
	self assert: e timeStamp equals: 5.
	e := UIEvent fromPlatform: {UIEvent evDisplayScaleChanged. 0. 2.0. 0. 0. 0. nil. 1}.
	self assert: (e isKindOf: ScaleChangedEvent).
	self assert: e scale equals: 2.0.
	self assert: (UIEvent fromPlatform: {UIEvent evFocusGained. 0. 0. 0. 0. 0. nil. 1}) isNil.
	self assert: (UIEvent fromPlatform: #(99 0 0 0 0 0 nil 1)) isNil
!
testEachPlatformEventReachesItsHandler
	{UIEvent evMouseMove -> #handlePointer:. UIEvent evMouseDown -> #handlePointer:. UIEvent evMouseUp -> #handlePointer:.
	 UIEvent evWheel -> #handlePointer:. UIEvent evKeyDown -> #handleKey:. UIEvent evKeyUp -> #handleKey:.
	 UIEvent evTextInput -> #handleText:. UIEvent evWindowResized -> #hostResized:.
	 UIEvent evWindowCloseRequest -> #quitRequested. UIEvent evQuit -> #processQuitRequested. UIEvent evFocusLost -> #focusLost.
	 UIEvent evDisplayScaleChanged -> #displayScaleChanged:. UIEvent evMouseLeave -> #pointerLeft.
	 UIEvent evWindowExposed -> #exposed. UIEvent evWindowMoved -> #hostMoved:} do: [:each |
		dispatched := nil.
		(UIEvent fromPlatform: {each key. 0. 800. 600. 1. 0. nil. 1}) dispatchTo: self.
		self assert: dispatched first equals: each value].
	(UIEvent fromPlatform: {UIEvent evWindowResized. 0. 800. 600. 0. 0. nil. 1}) dispatchTo: self.
	self assert: dispatched last equals: 800 @ 600.
	(UIEvent fromPlatform: {UIEvent evDisplayScaleChanged. 0. 2.0. 0. 0. 0. nil. 1}) dispatchTo: self.
	self assert: dispatched last equals: 2.0.
	(UIEvent fromPlatform: {UIEvent evWindowMoved. 0. 10.0. 42.0. 0. 0. nil. 1}) dispatchTo: self.
	self assert: dispatched last equals: 10.0 @ 42.0.
	(UIEvent fromPlatform: {UIEvent evKeyDown. 0. 0. 0. 97. 0. false. 1}) dispatchTo: self.
	self assert: dispatched last key equals: $a
!
testModifiers
	self assert: (Modifiers bits: 0) isEmpty.
	self assert: (Modifiers bits: 15) shift.
	self assert: (Modifiers bits: 4) option.
	self assert: (Modifiers bits: 2) == (Modifiers bits: 2)
! !

!EventDecodingTest methodsFor: 'input dispatcher protocol'!
handlePointer: anEvent
	dispatched := {#handlePointer:. anEvent}
!
handleKey: anEvent
	dispatched := {#handleKey:. anEvent}
!
handleText: anEvent
	dispatched := {#handleText:. anEvent}
!
hostResized: aPoint
	dispatched := {#hostResized:. aPoint}
!
hostMoved: aPoint
	dispatched := {#hostMoved:. aPoint}
!
quitRequested
	dispatched := {#quitRequested}
!
processQuitRequested
	dispatched := {#processQuitRequested}
!
focusLost
	dispatched := {#focusLost}
!
displayScaleChanged: aNumber
	dispatched := {#displayScaleChanged:. aNumber}
!
pointerLeft
	dispatched := {#pointerLeft}
!
exposed
	dispatched := {#exposed}
! !
