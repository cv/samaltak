Object subclass: #UIIcons
	instanceVariableNames: ''
	classVariableNames: 'Cache'
	package: 'UI-Windows'!

UIIcons comment: 'I rasterize the few vector shapes the window layer needs (the Blue Book arrow pointer) into Forms at the display scale, antialiased by 4×4 supersampling, and cache them per scale.'!

!UIIcons class methodsFor: 'icons'!
arrowPointerScale: aNumber
	"The remote pointer: a black arrow with a white outline, 13×19 points; its tip is at 1@1."
	^self cached: #arrow scale: aNumber ifAbsent: [
		| poly |
		poly := {1 @ 1. 1 @ 15. 4.6 @ 11.6. 7.2 @ 17.2. 9.5 @ 16.1. 6.9 @ 10.7. 12 @ 10.7}.
		self form: 13 @ 19 scale: aNumber sampler: [:p |
			| inside d |
			inside := self polygon: poly contains: p.
			d := self distanceFrom: p toPolygon: poly.
			d <= 0.6
				ifTrue: [Color white]
				ifFalse: [inside ifTrue: [Color black] ifFalse: [nil]]]]
! !

!UIIcons class methodsFor: 'rasterizing'!
cached: aSymbol scale: aNumber ifAbsent: aBlock
	"Kept per scale and per the theme colors icons are drawn in (the accent, the greys): a theme switch draws them anew."
	| key |
	Cache isNil ifTrue: [Cache := Dictionary new].
	key := Array with: aSymbol with: aNumber with: Color ultramarine hex with: (Color named: #ink3) hex.
	^Cache at: key ifAbsent: [Cache at: key put: aBlock value]
!
form: pointExtent scale: aNumber sampler: aBlock
	"A Form of pointExtent × aNumber pixels; aBlock maps a Point (points) to a Color or nil, sampled 4×4 per pixel."
	| w h form n |
	w := (pointExtent x * aNumber) ceiling.
	h := (pointExtent y * aNumber) ceiling.
	form := Form width: w height: h.
	n := 4.
	0 to: h - 1 do: [:py |
		0 to: w - 1 do: [:px |
			| r g b a |
			r := 0. g := 0. b := 0. a := 0.
			0 to: n - 1 do: [:sy |
				0 to: n - 1 do: [:sx |
					| c |
					c := aBlock value: (px + ((sx + 0.5) / n)) / aNumber @ ((py + ((sy + 0.5) / n)) / aNumber).
					c isNil ifFalse: [
						r := r + (c red * c alpha).
						g := g + (c green * c alpha).
						b := b + (c blue * c alpha).
						a := a + c alpha]]].
			a > 0 ifTrue: [
				form pixelValueAt: px @ py put:
					(self byte: r / (n * n))
					+ ((self byte: g / (n * n)) bitShift: 8)
					+ ((self byte: b / (n * n)) bitShift: 16)
					+ ((self byte: a / (n * n)) bitShift: 24)]]].
	^form
!
byte: aFloat
	^((aFloat * 255) rounded max: 0) min: 255
!
polygon: points contains: p
	"Even-odd rule."
	| inside j |
	inside := false.
	j := points size.
	1 to: points size do: [:i |
		| a b |
		a := points at: i.
		b := points at: j.
		((a y > p y) ~= (b y > p y) and: [p x < ((b x - a x) * (p y - a y) / (b y - a y) + a x)])
			ifTrue: [inside := inside not].
		j := i].
	^inside
!
distanceFrom: p toPolygon: points
	| best j |
	best := 1.0e10.
	j := points size.
	1 to: points size do: [:i |
		best := best min: (self distanceFrom: p toSegment: (points at: j) to: (points at: i)).
		j := i].
	^best
!
distanceFrom: p toSegment: a to: b
	| d t q |
	d := b - a.
	t := (d x * d x + (d y * d y)) = 0
		ifTrue: [0]
		ifFalse: [(((p - a) x * d x + ((p - a) y * d y)) / (d x * d x + (d y * d y)) max: 0) min: 1].
	q := a + (d * t).
	^((p x - q x) squared + (p y - q y) squared) sqrt
! !
