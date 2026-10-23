ToggleGroup subclass: #Tabs
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Widgets'!

Tabs comment: 'I am a row of tabs (the profiler''s view switch): like a ToggleGroup, but each tab is as wide as its label plus padding and the row starts at the left; the selected tab is inverted and bold, with a cross-fade on change.'!

!Tabs methodsFor: 'geometry'!
segmentArea
	^self localBounds
!
segmentRects
	| area x rects pad font |
	area := self segmentArea.
	pad := self theme metric: #tabPaddingX.
	font := self theme font: #buttonBold.
	x := area left.
	rects := Array new: self options size.
	1 to: self options size do: [:i |
		| w |
		w := ((font widthOf: (self labelAt: i)) + (2 * pad)) ceiling.
		rects at: i put: (x @ area top corner: (x + w) @ (area top + (self theme metric: #tabHeight) min: area bottom)).
		x := x + w - 1].
	^rects
!
preferredExtent
	| rects |
	rects := self segmentRects.
	rects isEmpty ifTrue: [^0 @ (self theme metric: #tabHeight)].
	^rects last right @ (self theme metric: #tabHeight)
! !

!Tabs methodsFor: 'remote control'!
segmentRole
	^#tab
!
selectedStateWords
	^#(#selected)
! !
