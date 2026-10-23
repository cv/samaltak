Widget subclass: #ScrollPane
	instanceVariableNames: 'content offset scrollBar contentHeight'
	classVariableNames: ''
	package: 'UI-Widgets'!

ScrollPane comment: 'I show a part of a taller content widget and scroll it vertically (wheel, scroll bar, scrollToShow:). The content is as wide as my viewport and as high as its preferredExtent y (or contentHeight: points). It should draw only what intersects the canvas clip, so scrolling stays cheap. ListView and TextEditor scroll themselves; use me for everything else.'!

!ScrollPane methodsFor: 'initialization'!
initialize
	super initialize.
	offset := 0.
	scrollBar := ScrollBar new client: self; yourself.
	self addChild: scrollBar
! !

!ScrollPane methodsFor: 'accessing'!
content
	^content
!
content: aWidget
	content isNil ifFalse: [self removeChild: content].
	content := aWidget.
	children addFirst: aWidget.
	aWidget owner: self.
	offset := 0.
	self layout.
	self invalidate
!
contentHeight: points
	contentHeight := points.
	self layout
!
scrollBar
	^scrollBar
! !

!ScrollPane methodsFor: 'scrolling'!
scrollTotal
	content isNil ifTrue: [^0].
	^contentHeight ifNil: [content preferredExtent y]
!
scrollVisible
	^self height
!
scrollOffset
	^offset
!
scrollOffset: points
	| new |
	new := (points min: self scrollTotal - self scrollVisible) max: 0.
	new = offset ifTrue: [^self].
	offset := new.
	self layout.
	scrollBar invalidate
!
scrollToShow: aRectangle
	"Scroll so that aRectangle (content coordinates) is visible."
	aRectangle top < offset ifTrue: [^self scrollOffset: aRectangle top].
	aRectangle bottom > (offset + self scrollVisible) ifTrue: [self scrollOffset: aRectangle bottom - self scrollVisible]
! !

!ScrollPane methodsFor: 'layout'!
layout
	| bar w |
	bar := self theme metric: #scrollBarWidth.
	content isNil ifTrue: [^self].
	offset := (offset min: self scrollTotal - self scrollVisible) max: 0.
	scrollBar setVisible: scrollBar isNeeded.
	w := scrollBar isVisible ifTrue: [self width - bar] ifFalse: [self width].
	scrollBar bounds: (w @ 0 corner: self width @ self height).
	content bounds: (0 @ offset negated extent: w @ (self scrollTotal max: self height))
! !

!ScrollPane methodsFor: 'events'!
wheel: anEvent
	self scrollOffset: offset - (anEvent delta y * 40).
	^true
! !

!ScrollPane methodsFor: 'remote control'!
remoteRole
	^#scroll
!
remoteIsTransparent
	^true
! !
