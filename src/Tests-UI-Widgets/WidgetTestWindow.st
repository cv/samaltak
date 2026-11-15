Object subclass: #WidgetTestWindow
	instanceVariableNames: 'content world keyboardFocus focused invalidations animations frameAnimations timers capture hover origin extent'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

WidgetTestWindow comment: 'I stand in for a UI-Windows Window in widget tests, synchronously: I own a content widget, deliver pointer events the way the Window contract says (hit testing with viewAt:, keyboard focus on down, capture between down and up, bubbling with re-localized positions, context menus for unhandled right-button downs), deliver keys to the keyboard focus, count invalidations, and run animations to their end at once (or keep them for stepping when keepAnimations is set).'!

!WidgetTestWindow methodsFor: 'initialization'!
initialize
	world := WidgetTestWorld new.
	world windows add: self.
	focused := true.
	invalidations := 0.
	animations := nil.
	timers := OrderedCollection new.
	origin := 100 @ 50
! !

!WidgetTestWindow methodsFor: 'window protocol'!
window
	^self
!
world
	^world
!
process
	^nil
!
content
	^content
!
content: aView extent: aPoint
	content := aView.
	extent := aPoint.
	aView owner: self.
	aView bounds: (0 @ 0 extent: aPoint)
!
invalidate
	invalidations := invalidations + 1
!
redrawChanged
	invalidations := invalidations + 1
!
keyboardFocus
	^keyboardFocus
!
keyboardFocus: aView
	| old |
	old := keyboardFocus.
	old == aView ifTrue: [^self].
	keyboardFocus := aView.
	old isNil ifFalse: [old focusLost].
	aView isNil ifFalse: [aView focusGained]
!
isFocused
	^focused
!
focused: aBoolean
	focused := aBoolean
!
animate: anAnimation
	animations isNil
		ifTrue: [anAnimation finish]
		ifFalse: [animations add: anAnimation].
	^anAnimation
!
requestAnimationFrames: aBlock
	| anim |
	anim := Animation everyFrame: aBlock.
	frameAnimations isNil ifTrue: [frameAnimations := OrderedCollection new].
	frameAnimations add: anim.
	^anim
!
frame: ms
	"Step the frame animations to the compositor time ms."
	frameAnimations isNil ifTrue: [^self].
	frameAnimations := frameAnimations reject: [:each | (each stepAt: ms) not]
!
after: ms do: aBlock
	^timers add: (WidgetTestTimer after: ms do: aBlock)
!
do: aBlock
	^aBlock value
!
clipboard
	^world clipboard
!
clipboard: aString
	world clipboard: aString
!
textInputArea: aRectangle cursor: x
	world textInputArea: aRectangle cursor: x
!
contentOrigin
	^origin
!
isCollapsed
	^false
!
isWindow
	^true
! !

!WidgetTestWindow methodsFor: 'remote control'!
remoteRole
	^#window
!
remoteLabel
	^'Test'
!
remoteName
	^'w1'
!
remoteState
	^#()
!
remoteBounds
	^origin extent: extent
!
remoteChildren
	content isNil ifTrue: [^#()].
	^View remoteFlatten: (Array with: content)
! !

!WidgetTestWindow methodsFor: 'testing support'!
invalidations
	^invalidations
!
resetInvalidations
	invalidations := 0
!
keepAnimations
	"Keep animations for step: instead of finishing them at once."
	animations := OrderedCollection new
!
finishAnimations
	animations isNil ifTrue: [^self].
	[animations isEmpty] whileFalse: [animations removeFirst finish]
!
runAnimationsAt: fraction
	"Step every kept animation to fraction (0..1) of its duration."
	animations isNil ifTrue: [^self].
	animations do: [:each |
		each startTime isNil ifTrue: [each startAt: 0].
		each stepAt: each startTime + (fraction * each duration)]
!
animations
	^animations
!
finishImmediately
	animations := nil
!
timers
	^timers
!
fireTimers
	| due |
	due := timers reject: [:each | each isCancelled].
	timers := OrderedCollection new.
	due do: [:each | each fire]
!
pendingTimers
	^timers reject: [:each | each isCancelled]
! !

!WidgetTestWindow methodsFor: 'delivering events'!
chainFrom: aView
	| chain v |
	chain := OrderedCollection new.
	v := aView.
	[v notNil and: [v ~~ self]] whileTrue: [chain add: v. v := v owner].
	^chain
!
localPoint: aContentPoint in: aView
	^aView localPointFrom: aContentPoint
!
deliverPointer: anEvent at: aContentPoint to: aView
	"Bubble from aView up; answer the view that handled it or nil."
	(self chainFrom: aView) do: [:v |
		anEvent position: (self localPoint: aContentPoint in: v).
		(v handlePointer: anEvent) ifTrue: [^v]].
	^nil
!
pointer: anEvent
	"Deliver anEvent (position in content coordinates)."
	| p target chain handler menu |
	p := anEvent position.
	anEvent globalPosition: p + origin.
	anEvent type == #down ifTrue: [
		target := content viewAt: p.
		chain := self chainFrom: target.
		(chain detect: [:v | v wantsKeyboardFocus] ifNone: [nil]) ifNotNil: [:v | self keyboardFocus: v].
		handler := self deliverPointer: anEvent at: p to: target.
		(handler isNil and: [anEvent button = 2]) ifTrue: [
			chain do: [:v |
				menu := v contextMenuAt: (self localPoint: p in: v).
				menu isNil ifFalse: [^world openMenu: menu at: p + origin]]].
		capture := handler.
		^handler].
	(anEvent type == #move or: [anEvent type == #up]) ifTrue: [
		capture isNil ifFalse: [
			handler := capture.
			anEvent type == #up ifTrue: [capture := nil].
			anEvent position: (self localPoint: p in: handler).
			handler handlePointer: anEvent.
			^handler].
		target := content viewAt: p.
		target == hover ifFalse: [
			hover isNil ifFalse: [hover handlePointer: ((anEvent withType: #leave) at: (self localPoint: p in: hover))].
			hover := target.
			target handlePointer: ((anEvent withType: #enter) at: (self localPoint: p in: target))].
		^self deliverPointer: anEvent at: p to: target].
	^self deliverPointer: anEvent at: p to: (content viewAt: p)
!
key: anEvent
	| v |
	v := keyboardFocus ifNil: [content].
	[v notNil and: [v ~~ self]] whileTrue: [
		(v handleKey: anEvent) ifTrue: [^v].
		v := v owner].
	^nil
!
text: anEvent
	| v |
	v := keyboardFocus ifNil: [content].
	[v notNil and: [v ~~ self]] whileTrue: [
		(v handleText: anEvent) ifTrue: [^v].
		v := v owner].
	^nil
!
textEditing: anEvent
	| v |
	v := keyboardFocus ifNil: [content].
	[v notNil and: [v ~~ self]] whileTrue: [
		(v handleTextEditing: anEvent) ifTrue: [^v].
		v := v owner].
	^nil
! !
