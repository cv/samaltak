Widget subclass: #WorldClockFace
	instanceVariableNames: 'city zone nameFont'
	classVariableNames: ''
	package: 'WorldClock'!

WorldClockFace comment: 'I am one city of a world clock: an analog dial, light by day and dark by night, over the city''s name, its digital time, date and UTC offset. WorldClockFace open shows my cities in a row.'!

!WorldClockFace methodsFor: 'accessing'!
city: aString zone: aTimeZone
	city := aString.
	zone := aTimeZone
! !

!WorldClockFace methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| u s h m sec night r cx cy face ink accent hand second date o y w inset |
	aCanvas noteVolatile.
	u := Time utcMicroseconds // 1000000.
	s := (zone localSecondsAt: u) \\ 86400.
	h := s // 3600. m := s \\ 3600 // 60. sec := s \\ 60.
	night := h < 6 or: [h >= 18].
	ink := self theme ink. accent := self theme ultramarine.
	face := night ifTrue: [ink] ifFalse: [self theme paper].
	hand := night ifTrue: [self theme paper] ifFalse: [ink].
	"Ultramarine is too dark against a night dial; a light blue keeps the second hand visible."
	second := night ifTrue: [Color hex: 16r8CB8E8] ifFalse: [accent].
	w := self width.
	inset := 5.
	r := ((w - (2 * inset) min: self height - 68) / 2 - 2) max: 8.
	cx := w / 2. cy := r + 5.
	r negated to: r - 1 do: [:dy | | half |
		half := (r * r - ((dy + 0.5) squared)) max: 0.
		half := half sqrt.
		aCanvas fillRect: ((cx - half) @ (cy + dy) corner: (cx + half) @ (cy + dy + 1)) color: face].
	0 to: 71 do: [:i | | a b |
		a := i * 5 degreesToRadians. b := (i + 1) * 5 degreesToRadians.
		self stroke: aCanvas from: (cx + (r * a sin)) @ (cy - (r * a cos)) to: (cx + (r * b sin)) @ (cy - (r * b cos)) width: 2 color: ink].
	0 to: 11 do: [:i | | a inner |
		a := i * 30 degreesToRadians.
		inner := i \\ 3 = 0 ifTrue: [0.74] ifFalse: [0.84].
		self stroke: aCanvas from: (cx + (r * inner * a sin)) @ (cy - (r * inner * a cos)) to: (cx + (r * 0.93 * a sin)) @ (cy - (r * 0.93 * a cos)) width: (i \\ 3 = 0 ifTrue: [2] ifFalse: [1]) color: hand].
	{(h \\ 12 * 30 + (m / 2)) -> (0.5 @ 3). (m * 6 + (sec / 10)) -> (0.76 @ 2). (sec * 6) -> (0.86 @ 1)} doWithIndex: [:spec :i | | a len |
		a := spec key degreesToRadians. len := r * spec value x.
		self stroke: aCanvas from: (cx - (r * 0.12 * a sin)) @ (cy + (r * 0.12 * a cos)) to: (cx + (len * a sin)) @ (cy - (len * a cos)) width: spec value y color: (i = 3 ifTrue: [second] ifFalse: [hand])].
	aCanvas fillRect: ((cx - 2) @ (cy - 2) extent: 4 @ 4) color: second.
	date := zone dateAt: u.
	o := (zone offsetAt: u) // 3600.
	y := cy + r + 8.
	aCanvas drawString: city asUppercase in: (inset @ y extent: (w - (2 * inset)) @ 16) font: (self nameFontFitting: w - (2 * inset)) color: ink align: #center.
	aCanvas drawString: (self two: h), ':', (self two: m) in: (inset @ (y + 18) extent: (w - (2 * inset)) @ 22) font: (self theme font: #readout) color: (night ifTrue: [ink] ifFalse: [accent]) align: #center.
	aCanvas drawString: (date dayOfWeekName copyFrom: 1 to: 3), ' UTC', (o >= 0 ifTrue: ['+'] ifFalse: ['-']), o abs printString in: (inset @ (y + 42) extent: (w - (2 * inset)) @ 14) font: (self theme font: #small) color: ink align: #center
!
nameFontFitting: aWidth
	"The header font, shrunk in whole pixels until the city name fits aWidth; cached per width."
	| base name size |
	(nameFont notNil and: [nameFont key = aWidth]) ifTrue: [^nameFont value].
	base := self theme font: #header.
	name := city asUppercase.
	size := base size.
	[size > 8 and: [((base widthOf: name) * size / base size) > aWidth]] whileTrue: [size := size - 1].
	nameFont := aWidth -> (size = base size ifTrue: [base] ifFalse: [Font face: base face size: size]).
	^nameFont value
! !

!WorldClockFace methodsFor: 'private'!
stroke: aCanvas from: p to: q width: w color: aColor
	"Nudged off the axes so Canvas draws every hand and tick as an antialiased quad centered on the line."
	aCanvas line: p to: q + (0.01 @ 0.01) color: aColor width: w
!
two: n
	^n < 10 ifTrue: ['0', n printString] ifFalse: [n printString]
! !

!WorldClockFace class methodsFor: 'opening'!
cities
	"City names and their POSIX TZ rules."
	^#(#('Vancouver' 'MST7') #('San Francisco' 'PST8PDT,M3.2.0,M11.1.0') #('Philadelphia' 'EST5EDT,M3.2.0,M11.1.0') #('Barcelona' 'CET-1CEST,M3.5.0,M10.5.0/3') #('Beijing' 'CST-8') #('Ho Chi Minh' 'ICT-7'))
!
open
	"Open a World Clock window with a face for each of my cities."
	| row window |
	row := Row withAll: (self cities collect: [:each | self new city: each first zone: (TimeZone fromRule: each last)]).
	row background: #paper.
	window := Desktop newWindow title: 'World Clock'; content: row; bounds: (40 @ 40 extent: 544 @ 168); yourself.
	window minExtent: 160 @ 60.
	window open.
	^window
! !
