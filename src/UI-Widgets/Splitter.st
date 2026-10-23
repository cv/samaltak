Widget subclass: #Splitter
	instanceVariableNames: 'dragStart startLength minLength'
	classVariableNames: ''
	package: 'UI-Widgets'!

Splitter comment: 'I sit between two siblings in a Row or Column and resize the one before me when dragged (it becomes fixed size; the one after me takes up the rest if it is flexible). In a Column I am a 4-point bar with rules above and below (Blue Book .vsplit), in a Row a 1-point rule (.hsplit) with a point of paper on each side to grab. minLength: limits both neighbours (default 40).'!

!Splitter methodsFor: 'initialization'!
initialize
	super initialize.
	minLength := 40
! !

!Splitter methodsFor: 'accessing'!
minLength: points
	minLength := points
!
isVertical
	"A splitter in a Column (it moves up and down)."
	^owner notNil and: [(owner respondsTo: #isHorizontal) and: [owner isHorizontal not]]
!
owner: aView
	super owner: aView.
	(aView notNil and: [aView respondsTo: #isHorizontal]) ifTrue: [
		self fixed: (aView isHorizontal ifTrue: [3] ifFalse: [self theme metric: #splitterThickness])]
!
before
	| kids i |
	kids := owner visibleChildren.
	i := kids indexOf: self.
	^i > 1 ifTrue: [kids at: i - 1] ifFalse: [nil]
!
after
	| kids i |
	kids := owner visibleChildren.
	i := kids indexOf: self.
	^i < kids size ifTrue: [kids at: i + 1] ifFalse: [nil]
!
along: aPoint
	^self isVertical ifTrue: [aPoint y] ifFalse: [aPoint x]
! !

!Splitter methodsFor: 'events'!
cursorAt: aPoint
	^self isVertical ifTrue: [#resizeNS] ifFalse: [#resizeEW]
!
mouseDown: anEvent
	| b |
	anEvent button = 1 ifFalse: [^false].
	b := self before.
	b isNil ifTrue: [^false].
	dragStart := self along: anEvent globalPosition.
	startLength := self along: b bounds extent.
	^true
!
mouseMove: anEvent
	dragStart isNil ifTrue: [^false].
	self dragBy: (self along: anEvent globalPosition) - dragStart.
	^true
!
mouseUp: anEvent
	dragStart := nil.
	^true
!
dragBy: delta
	"Make the widget before me startLength + delta long, keeping both neighbours at least minLength."
	| b a max len |
	b := self before.
	a := self after.
	max := (self along: b bounds extent) + (a isNil ifTrue: [0] ifFalse: [(self along: a bounds extent) - minLength]).
	len := ((startLength ifNil: [self along: b bounds extent]) + delta max: minLength) min: (max max: minLength).
	b fixed: len rounded.
	owner layout.
	owner invalidate
! !

!Splitter methodsFor: 'drawing'!
drawSelfOn: aCanvas
	self isVertical
		ifTrue: [
			aCanvas fillRect: self localBounds color: self theme paper.
			aCanvas fillRect: (0 @ 0 corner: self width @ 1) color: self theme rule.
			aCanvas fillRect: (0 @ (self height - 1) corner: self width @ self height) color: self theme rule]
		ifFalse: [
			aCanvas fillRect: self localBounds color: self theme paper.
			aCanvas fillRect: (1 @ 0 corner: 2 @ self height) color: self theme rule]
! !

!Splitter methodsFor: 'remote control'!
remoteRole
	^#splitter
!
remoteLabel
	^'split'
! !
