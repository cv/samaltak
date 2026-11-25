Object subclass: #GlassPane
	instanceVariableNames: 'displayWindow rects'
	classVariableNames: ''
	package: 'UI-Windows'!

GlassPane comment: 'I am a host window of my own that shows rectangles over what is below me: transparent where nothing is drawn, and the pointer passes through me (HostWindow flag 16). The GPU does not draw a transparent window, so mine are filled into its own pixels (DisplayWindow>>fillRects:): solid rectangles, frames and pills, of any opacity. On the desktop (flag 8) I am above the wallpaper and below every window, and below the desktop windows opened after me; OmarchyDesk shows where a dragged card would land on one under the cards. I present only when told (show:).

	pane := GlassPane extent: 800 @ 600 title: ''Desktop'' desktop: true hidden: false.
	pane moveTo: 10 @ 10.
	pane show: [:p | p fillRect: (0 @ 0 extent: 100 @ 600) color: (Color ultramarine alpha: 0.06)].
	pane clear.
	pane close'!

!GlassPane methodsFor: 'initialization'!
setDisplayWindow: aDisplayWindow
	displayWindow := aDisplayWindow
! !

!GlassPane methodsFor: 'accessing'!
extent
	"In points."
	^displayWindow extent
!
scale
	"Pixels per point."
	^displayWindow scale
!
isOpen
	^displayWindow notNil
!
shown
	"What the last show: drew: x y w h rgba for each rectangle, in pixels."
	^rects ifNil: [#()]
! !

!GlassPane methodsFor: 'drawing'!
fillRect: aRectangle color: aColor
	"During show:, a rectangle (points) of aColor."
	| s x0 y0 x1 y1 |
	s := self scale.
	x0 := (aRectangle left * s) rounded.
	y0 := (aRectangle top * s) rounded.
	x1 := (aRectangle right * s) rounded.
	y1 := (aRectangle bottom * s) rounded.
	(x1 > x0 and: [y1 > y0]) ifFalse: [^self].
	rects addAll: (Array with: x0 with: y0 with: x1 - x0 with: y1 - y0 with: (self class rgbaOf: aColor))
!
strokeRect: aRectangle color: aColor width: points
	"During show:, the inside border of aRectangle, points wide."
	| w |
	w := points min: (aRectangle width min: aRectangle height) / 2.
	self fillRect: (aRectangle topLeft extent: aRectangle width @ w) color: aColor.
	self fillRect: (aRectangle left @ (aRectangle bottom - w) extent: aRectangle width @ w) color: aColor.
	self fillRect: (aRectangle left @ (aRectangle top + w) extent: w @ (aRectangle height - (2 * w))) color: aColor.
	self fillRect: ((aRectangle right - w) @ (aRectangle top + w) extent: w @ (aRectangle height - (2 * w))) color: aColor
!
fillPill: aRectangle color: aColor
	"During show:, aRectangle with fully rounded ends, row by row of pixels (opaque colors look right; overlapping rows would double a translucent one, so there are none)."
	| s x0 y0 w h r rgba |
	s := self scale.
	x0 := (aRectangle left * s) rounded.
	y0 := (aRectangle top * s) rounded.
	w := (aRectangle right * s) rounded - x0.
	h := (aRectangle bottom * s) rounded - y0.
	(w > 0 and: [h > 0]) ifFalse: [^self].
	r := (w min: h) / 2.0.
	rgba := self class rgbaOf: aColor.
	0 to: h - 1 do: [:row |
		| dy inset |
		dy := (row + 0.5 - (h / 2.0)) abs.
		inset := w >= h
			ifTrue: [(r - ((r * r) - (dy * dy) max: 0) sqrt) rounded]
			ifFalse: [0].
		w - (2 * inset) > 0 ifTrue: [
			rects addAll: (Array with: x0 + inset with: y0 + row with: w - (2 * inset) with: 1 with: rgba)]]
! !

!GlassPane methodsFor: 'showing'!
show: aBlock
	"Show what aBlock draws with fillRect:color:, strokeRect:color:width: and fillPill:color: (sent to me) over a transparent background. Answer whether it was presented (not when hidden)."
	displayWindow isNil ifTrue: [^false].
	rects := OrderedCollection new.
	aBlock value: self.
	rects := rects asArray.
	^displayWindow fillRects: rects
!
clear
	"Show nothing."
	^self show: [:pane | ]
!
moveTo: aPoint
	"On the desktop from the top left of the area the bar leaves free, else on the screen (HostWindow>>moveTo:). Answer whether the host did."
	displayWindow isNil ifTrue: [^false].
	^displayWindow hostWindow moveTo: aPoint
!
close
	displayWindow isNil ifFalse: [displayWindow close. displayWindow := nil]
! !

!GlassPane class methodsFor: 'instance creation'!
extent: aPoint title: aString desktop: desktopBoolean hidden: hiddenBoolean
	"A glass pane of aPoint points (high density), on the desktop or not, hidden (offscreen) or shown; it opens with its first show:."
	^self new setDisplayWindow: (DisplayWindow glassWidth: aPoint x ceiling height: aPoint y ceiling title: aString
		flags: ((4 bitOr: (desktopBoolean ifTrue: [8] ifFalse: [0])) bitOr: (hiddenBoolean ifTrue: [1] ifFalse: [0])))
! !

!GlassPane class methodsFor: 'colors'!
rgbaOf: aColor
	"16rRRGGBBAA, premultiplied by its alpha."
	| a |
	a := aColor alpha.
	^((((aColor red * a * 255) rounded bitShift: 24) bitOr: ((aColor green * a * 255) rounded bitShift: 16))
		bitOr: ((aColor blue * a * 255) rounded bitShift: 8)) bitOr: (a * 255) rounded
! !
