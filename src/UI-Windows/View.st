Object subclass: #View
	instanceVariableNames: 'owner bounds drawing drawState'
	classVariableNames: 'StaleDrawings VerifyDrawing'
	package: 'UI-Windows'!

View comment: 'I am what a Window shows: a rectangle (bounds, in my owner''s coordinates) that draws itself on a Canvas and handles input. Widgets (UI-Widgets) subclass me; I keep no children myself (children answers none), so subclasses store them as they like.

Coordinates: drawOn: draws in local coordinates (0@0 is my top-left; the Window translates and clips); events arrive with position local to me. The content View''s owner is its Window; the Window''s content coordinates are 0@0 at the top-left of the area below the title bar.

Protocol for subclasses: drawOn:, layout (after my extent changed), children, viewAt:, handlePointer: / handleKey: / handleText: (answer true when handled; the Window bubbles unhandled events to the owner), wantsKeyboardFocus, focusGained / focusLost, cursorAt:, tooltipAt:, contextMenuAt:, clickItemAt:, preferredExtent, invalidate, and the remote-control protocol (remoteRole remoteLabel remoteState remoteName remoteChildren remoteBounds).

Retained drawing: my owner draws me with drawRetainedOn:, which replays what I drew last time (a DisplaySegment, Canvas>>replay:) unless I changed since. invalidate redraws me and everything in me anew; a change of my bounds makes my owner draw me again (moved: replayed; resized: drawn again, my children replayed if they did not change). So a view whose drawing shows other objects'' state must invalidate when that state changes; a drawing computed while drawing (a clock) calls Canvas>>noteVolatile. drawState: nil (my drawing is valid), #dirty (draw me again, replaying my children where they are valid) or #stale (draw me and my children anew).'!

!View methodsFor: 'initialization'!
initialize
	bounds := 0 @ 0 corner: 100 @ 100
! !

!View methodsFor: 'accessing'!
owner
	^owner
!
owner: aViewOrWindow
	owner := aViewOrWindow
!
bounds
	"My rectangle in my owner's coordinates."
	^bounds
!
bounds: aRectangle
	"Move and resize me; send layout when my extent changed."
	| old |
	old := bounds.
	bounds := aRectangle.
	old = aRectangle ifTrue: [^self].
	self ownerDrawingChanged.
	(old notNil and: [old extent = aRectangle extent]) ifTrue: [^self].
	self ownDrawingChanged.
	self layout
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
position: aPoint
	self bounds: (aPoint extent: bounds extent)
!
width
	^bounds width
!
height
	^bounds height
!
localBounds
	^0 @ 0 extent: bounds extent
!
window
	"The Window I am shown in (via my owner chain), or nil."
	^owner isNil ifTrue: [nil] ifFalse: [owner window]
!
world
	| w |
	w := self window.
	^w isNil ifTrue: [nil] ifFalse: [w world]
!
children
	"My subviews, back to front. I have none; containers override."
	^#()
!
preferredExtent
	"The extent I would like (menus and popups are sized by it)."
	^bounds extent
!
isVisible
	^true
! !

!View methodsFor: 'layout'!
layout
	"Called after my extent changed. Containers place their children here."
! !

!View methodsFor: 'drawing'!
drawOn: aCanvas
	"Draw me in local coordinates. By default I draw my children."
	self drawChildrenOn: aCanvas
!
drawChildrenOn: aCanvas
	"Draw each visible child translated to its position and clipped to its bounds."
	self children do: [:child |
		child isVisible ifTrue: [
			aCanvas translateBy: child position during: [
				aCanvas clip: child localBounds during: [child drawRetainedOn: aCanvas]]]]
!
drawRetainedOn: aCanvas
	"Draw me (drawOn:), replaying my last drawing if nothing in me changed since and it is valid on aCanvas (Canvas>>replay:)."
	| state segment |
	(drawState isNil and: [drawing notNil and: [aCanvas replay: drawing]]) ifTrue: [
		VerifyDrawing == true ifTrue: [self verifyReplay: drawing on: aCanvas drawing: [:c | self drawOn: c]].
		^self].
	state := drawState.
	drawState := nil.
	drawing := nil.
	segment := aCanvas record: [
		state == #stale
			ifTrue: [aCanvas drawFresh: [self drawOn: aCanvas]]
			ifFalse: [self drawOn: aCanvas]].
	"Invalidated while drawing: keep the new state for the next redraw."
	drawState isNil ifTrue: [drawing := segment]
!
invalidate
	"Draw me and everything in me anew at my window's next redraw (any Process)."
	self forgetDrawing.
	drawState := #stale.
	self ownersChanged.
	self requestRedraw
!
requestRedraw
	| w |
	w := self window.
	w isNil ifFalse: [w redrawChanged]
!
ownDrawingChanged
	"What I draw myself changed (e.g. my extent): draw me again at the next redraw, replaying my children where they did not change."
	self forgetDrawing.
	drawState isNil ifTrue: [drawState := #dirty].
	self ownersChanged
!
ownerDrawingChanged
	"My owner draws me elsewhere (or may draw around me differently)."
	(owner notNil and: [owner isView]) ifTrue: [owner ownDrawingChanged]
!
ownersChanged
	"Something in me changed: my owners must draw me again (replaying what did not change)."
	| v |
	v := owner.
	[v notNil and: [v isView]] whileTrue: [
		v childDrawingChanged.
		v := v owner]
!
childDrawingChanged
	drawState isNil ifTrue: [drawState := #dirty]
!
forgetDrawing
	"Drop what I recorded of my drawing."
	drawing := nil
!
drawState
	"nil: my last drawing is valid; #dirty: draw me again (replaying my children where valid); #stale: draw me and my children anew."
	^drawState
!
verifyReplay: aSegment on: aCanvas drawing: aBlock
	"Compare aSegment as replayed on aCanvas with aBlock drawing anew in the same state; note me if they differ (View verifyDrawing: true)."
	| replayed drawn difference |
	replayed := aCanvas emptyCopy.
	replayed replay: aSegment.
	drawn := aCanvas emptyCopy.
	drawn drawFresh: [aBlock value: drawn].
	difference := replayed displayList firstDifferenceFrom: drawn displayList.
	difference isNil ifFalse: [self class noteStaleDrawingOf: self difference: difference]
! !

!View class methodsFor: 'retained drawing'!
verifyDrawing: aBoolean
	"With aBoolean, every replayed drawing is compared with drawing anew; views that replayed something else are collected in staleDrawings (and shown in the Transcript)."
	VerifyDrawing := aBoolean.
	StaleDrawings := OrderedCollection new
!
isVerifyingDrawing
	^VerifyDrawing == true
!
staleDrawings
	"{view. {quad index. replayed quad. drawn quad}} for each replay that differed from drawing anew."
	^StaleDrawings ifNil: [#()]
!
noteStaleDrawingOf: aView difference: anArray
	StaleDrawings isNil ifTrue: [StaleDrawings := OrderedCollection new].
	StaleDrawings size < 1000 ifTrue: [StaleDrawings add: (Array with: aView with: anArray)].
	Transcript show: 'stale drawing: ', aView printString, ' in ', (aView window ifNil: ['no window'] ifNotNil: [:w | w title]) printString, ' quad ', anArray first printString; cr
! !

!View methodsFor: 'hit testing'!
containsPoint: aPoint
	"aPoint is in my owner's coordinates."
	^bounds containsPoint: aPoint
!
viewAt: aPoint
	"Answer the deepest visible view at aPoint (local coordinates): a child containing it, else me."
	self children reverseDo: [:child |
		(child isVisible and: [child containsPoint: aPoint]) ifTrue: [^child viewAt: aPoint - child position]].
	^self
! !

!View methodsFor: 'coordinates'!
positionInWindow
	"My top-left in my window's content coordinates."
	| p v |
	p := 0 @ 0.
	v := self.
	[v notNil and: [v isView]] whileTrue: [
		p := p + v position.
		v := v owner].
	^p
!
boundsInWindow
	^self positionInWindow extent: bounds extent
!
localPointFrom: aContentPoint
	"Convert a point in my window's content coordinates to mine."
	^aContentPoint - self positionInWindow
!
pointInWindow: aLocalPoint
	^aLocalPoint + self positionInWindow
!
screenPointFrom: aLocalPoint
	| w |
	w := self window.
	w isNil ifTrue: [^nil].
	^w contentOrigin + (self pointInWindow: aLocalPoint)
!
screenBounds
	"My rectangle in screen points, or nil when I am not shown."
	| w |
	w := self window.
	(w isNil or: [w isCollapsed]) ifTrue: [^nil].
	^self boundsInWindow translateBy: w contentOrigin
! !

!View methodsFor: 'events'!
handlePointer: aPointerEvent
	"Answer true when handled; false lets the Window offer the event to my owner."
	^false
!
handleKey: aKeyEvent
	^false
!
handleText: aTextEvent
	^false
!
wantsKeyboardFocus
	^false
!
focusGained
!
focusLost
!
isFocused
	"Answer whether I have the keyboard focus of the active window."
	| w |
	w := self window.
	^w notNil and: [w keyboardFocus == self and: [w isFocused]]
!
cursorAt: aPoint
	"#arrow #ibeam #hand #resizeEW #resizeNS #resizeNWSE #move #crosshair #wait"
	^#arrow
!
tooltipAt: aPoint
	"A String shown when the pointer rests at aPoint, or nil."
	^nil
!
contextMenuAt: aPoint
	"A menu (a View, or a model answering asMenuView) for a right-click at aPoint, or nil."
	^nil
!
clickItemAt: aPoint
	"What a press at aPoint hits: presses make a multi-click only on an equal one (Window>>countClick:on:). Views of several items answer which (a ListView its row)."
	^self
! !

!View methodsFor: 'testing'!
isView
	^true
! !

!View methodsFor: 'remote control'!
remoteRole
	"#window #list #item #editor #button #tab #menu #canvas #status ...; default from my class name."
	| name |
	name := self class name asString.
	(name endsWith: 'View') ifTrue: [name := name allButLast: 4].
	(name endsWith: 'Widget') ifTrue: [name := name allButLast: 6].
	name isEmpty ifTrue: [^#view].
	^name asLowercase asSymbol
!
remoteLabel
	^nil
!
remoteState
	^self isFocused ifTrue: [#('focused')] ifFalse: [#()]
!
remoteName
	^nil
!
remoteIsTransparent
	"Answer true to have my remote children shown in place of me (layout containers)."
	^false
!
remoteChildren
	^self class remoteFlatten: self children
!
remoteBounds
	^self screenBounds
! !

!View class methodsFor: 'remote control'!
remoteFlatten: views
	"Answer views with transparent ones replaced by their remote children."
	| result |
	result := OrderedCollection new.
	views do: [:each |
		(each isView and: [each remoteIsTransparent])
			ifTrue: [result addAll: each remoteChildren]
			ifFalse: [result add: each]].
	^result asArray
! !

!View class methodsFor: 'instance creation'!
bounds: aRectangle
	^self new bounds: aRectangle; yourself
!
extent: aPoint
	^self bounds: (0 @ 0 extent: aPoint)
! !
