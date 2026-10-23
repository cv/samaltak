ListView subclass: #MethodListView
	instanceVariableNames: 'breakpointBlock onGutterClick hoverIndex'
	classVariableNames: ''
	package: 'Tools'!

MethodListView comment: 'I am the System Browser''s method list: a ListView with a breakpoint gutter. breakpointBlock answers, for a selector, nil or the breakpoint''s mode (#break #once #log #condition); I draw a filled ultramarine square for a breakpoint (an open one for a logpoint, a half-filled one for break once and conditional) and a grey ring where the pointer hovers. A click in the gutter runs onGutterClick: [:selector | ...] instead of selecting. In remote-control snapshots every row has a child button breakpoint-toggle (refs like @w6.methods.gcd.breakpoint-toggle).'!

!MethodListView methodsFor: 'initialization'!
initialize
	super initialize.
	self cellWidth: 11.
	self cellBlock: [:canvas :rect :item :inverted | self drawGutterOn: canvas in: rect for: item inverted: inverted]
! !

!MethodListView methodsFor: 'accessing'!
breakpointBlock: aBlock
	breakpointBlock := aBlock.
	self invalidate
!
onGutterClick: aBlock
	onGutterClick := aBlock
!
breakpointModeOf: anItem
	breakpointBlock isNil ifTrue: [^nil].
	^breakpointBlock value: anItem
!
gutterRight
	"The gutter: the leading cell and some slack (local x)."
	^self paddingX + cellWidth + 3
!
isInGutter: aPoint
	^aPoint x < self gutterRight
! !

!MethodListView methodsFor: 'drawing'!
drawGutterOn: aCanvas in: aRect for: anItem inverted: inverted
	| mode r theme fg |
	theme := self theme.
	mode := self breakpointModeOf: anItem.
	r := aRect left + 1 @ (aRect top + (aRect height - 9 / 2)) extent: 9 @ 9.
	fg := inverted ifTrue: [theme paper] ifFalse: [theme ultramarine].
	mode isNil ifTrue: [
		(hoverIndex notNil and: [hoverIndex <= items size and: [(items at: hoverIndex) == anItem]]) ifTrue: [
			aCanvas strokeRect: r color: (inverted ifTrue: [theme paper] ifFalse: [theme color: #ink4]) width: 1].
		^self].
	mode == #log ifTrue: [^aCanvas strokeRect: r color: fg width: 1.5].
	(mode == #once or: [mode == #condition]) ifTrue: [
		aCanvas strokeRect: r color: fg width: 1.
		^aCanvas fillRect: (r left @ (r top + 4.5) corner: r corner) color: fg].
	aCanvas fillRect: r color: fg
! !

!MethodListView methodsFor: 'events'!
mouseDown: anEvent
	| p i |
	anEvent button = 1 ifFalse: [^super mouseDown: anEvent].
	p := self localEventPosition: anEvent.
	(self isInGutter: p) ifFalse: [^super mouseDown: anEvent].
	i := self rowIndexAt: p.
	(i = 0 or: [onGutterClick isNil]) ifTrue: [^true].
	onGutterClick value: (items at: i).
	self invalidate.
	^true
!
mouseMove: anEvent
	| p i |
	p := self localEventPosition: anEvent.
	i := (self isInGutter: p) ifTrue: [self rowIndexAt: p] ifFalse: [0].
	i = 0 ifTrue: [i := nil].
	i = hoverIndex ifFalse: [hoverIndex := i. self invalidate].
	^false
!
mouseLeave: anEvent
	hoverIndex isNil ifFalse: [hoverIndex := nil. self invalidate].
	^false
!
cursorAt: aPoint
	^(self isInGutter: aPoint) ifTrue: [#hand] ifFalse: [#arrow]
!
tooltipAt: aPoint
	| i mode |
	(self isInGutter: aPoint) ifFalse: [^nil].
	i := self rowIndexAt: aPoint.
	i = 0 ifTrue: [^nil].
	mode := self breakpointModeOf: (items at: i).
	^mode isNil ifTrue: ['click: set a breakpoint · right-click: more'] ifFalse: ['click: remove the breakpoint (', mode, ')']
! !

!MethodListView methodsFor: 'remote control'!
remotePartFor: index
	| part mode toggle |
	part := super remotePartFor: index.
	mode := self breakpointModeOf: (items at: index).
	mode isNil ifFalse: [part state: (Array with: 'breakpoint=', mode) , part remoteState].
	toggle := WidgetPart of: self role: #button label: 'breakpoint-toggle'.
	toggle name: 'breakpoint-toggle'.
	toggle state: (mode isNil ifTrue: [#()] ifFalse: [#(#on)]).
	toggle rectBlock: [:reveal |
		| r |
		r := self remoteRectOf: index reveal: reveal.
		r isNil ifTrue: [nil] ifFalse: [r left @ r top extent: self gutterRight @ r height]].
	part children: (Array with: toggle).
	^part
! !
