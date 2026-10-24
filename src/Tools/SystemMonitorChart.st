Widget subclass: #SystemMonitorChart
	instanceVariableNames: 'monitor form scale q right painted key tops colors yMax scanned'
	classVariableNames: ''
	package: 'Tools'!

SystemMonitorChart comment: 'I am a chart of the System Monitor: the samples of its span, newest at the right, painted into a bitmap one column per device pixel, so that a refresh only paints what is new. Time is cut into columns of q µs at fixed positions (column k covers k*q .. (k+1)*q of the microsecond clock); column k lives at x = k \\ width of the bitmap, a ring: as time passes no pixel moves, the oldest columns are painted over, and I draw the bitmap in two parts, oldest first. Everything is painted again only when my size, the span, my scale or my colors change. My subclasses paint a column (paintColumn:index:from:to:) and label the axes; I draw the hover line where the monitor''s pointer is.'!

!SystemMonitorChart methodsFor: 'accessing'!
monitor: aSystemMonitor
	monitor := aSystemMonitor
!
data
	^monitor data
!
form
	^form
!
yMax
	^yMax
! !

!SystemMonitorChart methodsFor: 'geometry'!
padLeft
	^52
!
padRight
	^10
!
padTop
	^6
!
padBottom
	^1
!
plotRect
	^self padLeft @ self padTop corner: (self width - self padRight max: self padLeft + 1) @ (self height - self padBottom max: self padTop + 1)
!
columnMicros
	^q
!
timeAtX: x
	"The µs clock time at local x (nil before the first paint)."
	| r |
	(form isNil or: [right isNil]) ifTrue: [^nil].
	r := self plotRect.
	^((right + 1 - (((r right - x) * scale) max: 0)) * q) rounded
!
xOfTime: t
	| r |
	r := self plotRect.
	^r right - (((right + 1) * q - t) / q / scale)
!
plotRows
	"The bitmap rows my scale spans, from the top."
	^form height
!
rowOf: aValue
	"The bitmap row (0 = top) of aValue on my scale."
	| h |
	h := self plotRows.
	^h - ((aValue / yMax * h) rounded min: h)
! !

!SystemMonitorChart methodsFor: 'painting'!
bringUpToDate: deviceScale
	"Paint the columns that are new since the last time (all of them when the geometry or the scale changed)."
	| r w h data newKey first |
	data := self data.
	(data isNil or: [data isEmpty]) ifTrue: [^false].
	r := self plotRect.
	scale := deviceScale.
	w := (r width * scale) rounded max: 1.
	h := (r height * scale) rounded max: 1.
	(form isNil or: [form width ~= w or: [form height ~= h]]) ifTrue: [
		form := ProfilerStripForm width: w height: h.
		tops := Array new: w.
		painted := nil].
	q := monitor span / w.
	(self rescale: painted isNil) ifTrue: [painted := nil].
	newKey := Array with: q with: scale with: self paintKey with: self colors.
	key = newKey ifFalse: [key := newKey. painted := nil. colors := newKey last].
	right := (data last time / q) floor.
	first := painted isNil ifTrue: [right - w + 1] ifFalse: [painted max: right - w + 1].
	first to: right do: [:k | self paintColumn: k \\ w index: k from: k * q to: k + 1 * q].
	painted := right.
	form changed.
	^true
!
rescale: always
	"Choose yMax for what the span shows; answer whether it changed. I look at every sample every 5 s (always: now), else at the newest."
	| need nice data |
	data := self data.
	(always or: [scanned isNil or: [data serial - scanned >= 50]])
		ifTrue: [
			scanned := data serial.
			need := 0.
			(data serialAtOrAfter: data last time - monitor span) to: data serial do: [:i | need := need max: (self scaleNeedOf: (data sampleAt: i))].
			nice := self niceAbove: need * 1.15.
			(yMax notNil and: [nice <= yMax and: [nice * 2 > yMax]]) ifTrue: [^false]]
		ifFalse: [
			need := self scaleNeedOf: data last.
			(yMax notNil and: [need <= yMax]) ifTrue: [^false].
			nice := self niceAbove: need * 1.25].
	nice = yMax ifTrue: [^false].
	yMax := nice.
	^true
!
niceAbove: aNumber
	"The smallest 1, 1.5, 2, 2.5, 3, 4, 5, 6 or 8 times a power of ten at or above aNumber (at least my minimum)."
	| v p |
	v := aNumber max: self minimumScale.
	p := 1.
	[p * 10 <= v] whileTrue: [p := p * 10].
	#(1 1.5 2 2.5 3 4 5 6 8 10) do: [:m | m * p >= v ifTrue: [^m * p = (m * p) rounded ifTrue: [(m * p) rounded] ifFalse: [m * p]]].
	^10 * p
!
gridStep
	"Value between grid lines: the largest 1, 2, 2.5 or 5 times a power of ten that cuts yMax in three or more."
	| p |
	p := 1.
	[p * 10 <= yMax] whileTrue: [p := p * 10].
	#(5 2.5 2 1 0.5 0.25 0.2) do: [:m | yMax / (m * p) >= 3 ifTrue: [^m * p]].
	^p / 10
!
gridRows
	| rows step v |
	rows := OrderedCollection new.
	step := self gridStep.
	v := step.
	[v < (yMax - (step / 4))] whileTrue: [rows add: (self rowOf: v). v := v + step].
	^rows
!
fill: x from: r0 to: r1 pixel: v
	"Rows r0 <= r < r1 of column x (row 0 is the top)."
	| bits w i |
	bits := form bits.
	w := form width.
	i := (r0 max: 0) * w + x + 1.
	(r0 max: 0) to: (r1 min: form height) - 1 do: [:r | bits at: i put: v. i := i + w]
!
paintBackground: x to: r1 index: k
	"Paper with the grid lines, rows 0 .. r1 of column x."
	| paper hair bits w |
	paper := colors at: #paper.
	hair := colors at: #hair.
	self fill: x from: 0 to: r1 pixel: paper.
	bits := form bits.
	w := form width.
	(colors at: #grid) do: [:r | r < r1 ifTrue: [bits at: r * w + x + 1 put: hair]]
!
paintLine: x top: row pixel: v
	"A 1-point line at row in column x, joined to the line of the column before by a riser."
	| prev s0 w |
	w := form width.
	s0 := scale rounded max: 1.
	self fill: x from: row to: row + s0 pixel: v.
	prev := tops at: x - 1 \\ w + 1.
	(prev notNil and: [prev ~= row]) ifTrue: [
		self fill: x from: (prev min: row) to: (prev max: row) + s0 pixel: v.
		self fill: x - 1 \\ w from: (prev min: row) to: (prev max: row) + s0 pixel: v].
	tops at: x + 1 put: row
!
colors
	"Pixel values by name; my subclasses add theirs."
	| d rows |
	d := IdentityDictionary new.
	d at: #paper put: self theme paper premultipliedRGBA8.
	d at: #hair put: (self theme color: #hair) premultipliedRGBA8.
	d at: #ink put: self theme ink premultipliedRGBA8.
	rows := self gridRows.
	d at: #grid put: rows asArray.
	^d
!
pixel: aSymbol
	^(self theme color: aSymbol) premultipliedRGBA8
! !

!SystemMonitorChart methodsFor: 'subclass responsibility'!
paintColumn: x index: k from: t0 to: t1
	self subclassResponsibility
!
paintKey
	"What else my pixels depend on."
	^nil
!
scaleNeedOf: aSample
	^0
!
minimumScale
	^1
!
drawLabelsOn: aCanvas
	"The y axis."
!
tipLinesFor: aSample
	^#()
! !

!SystemMonitorChart methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| r w x0 wl s |
	aCanvas fillRect: self localBounds color: self theme paper.
	r := self plotRect.
	(monitor notNil and: [self bringUpToDate: aCanvas scale]) ifTrue: [
		w := form width.
		s := scale.
		x0 := right + 1 \\ w.
		wl := w - x0.
		aCanvas image: form from: (x0 @ 0 corner: w @ form height) in: (r left @ r top extent: (wl / s) @ (form height / s)).
		x0 > 0 ifTrue: [
			aCanvas image: form from: (0 @ 0 corner: x0 @ form height) in: ((r left + (wl / s)) @ r top extent: (x0 / s) @ (form height / s))].
		self drawLabelsOn: aCanvas].
	aCanvas fillRect: (r left @ r bottom extent: r width @ 1) color: self theme ink
!
drawOverlayOn: aCanvas
	"The hover line, at the monitor's pointer."
	| x r |
	(monitor isNil or: [(x := monitor hoverX) isNil]) ifTrue: [^self].
	r := self plotRect.
	(x between: r left and: r right) ifFalse: [^self].
	aCanvas fillRect: (x rounded @ r top extent: 1 @ (r height + 1)) color: self theme ultramarine
!
labelY: aString at: y on: aCanvas
	aCanvas drawString: aString in: (0 @ (y - 8) corner: (self padLeft - 6) @ (y + 8))
		font: (self theme font: #smallItalic) color: self theme muted align: #right
!
drawGridLabelsOn: aCanvas format: aBlock
	"Label the grid lines and the top of the scale."
	| r step v |
	r := self plotRect.
	step := self gridStep.
	v := step.
	[v <= (yMax + (step / 4))] whileTrue: [
		self labelY: (aBlock value: v) at: r top + ((self rowOf: v) / scale) on: aCanvas.
		v := v + step]
! !

!SystemMonitorChart methodsFor: 'events'!
mouseMove: anEvent
	monitor isNil ifFalse: [monitor hover: (self localEventPosition: anEvent) in: self].
	^true
!
mouseLeave: anEvent
	monitor isNil ifFalse: [monitor hover: nil in: self].
	^false
!
cursorAt: aPoint
	^#crosshair
! !

!SystemMonitorChart methodsFor: 'remote control'!
remoteRole
	^#chart
!
remoteState
	"Where time is on the screen (so a client can hover at a time) and the values at the newest sample."
	| s r last |
	s := OrderedCollection new.
	(monitor isNil or: [self data isEmpty or: [right isNil]]) ifTrue: [^#()].
	r := self plotRect.
	s add: 'plot=', (self screenPointFrom: r origin) x rounded printString, '-', (self screenPointFrom: r corner) x rounded printString.
	s add: 'time=', (self timeAtX: r left) printString, '-', (self timeAtX: r right) printString.
	s add: 'max=', (self remoteValue: yMax).
	last := self data last.
	s addAll: (self remoteStateFor: last).
	^s asArray
!
remoteStateFor: aSample
	^#()
!
remoteValue: aNumber
	^aNumber printString
!
remotePointAt: aString
	"The screen point of the plot's middle at aString seconds ago (e.g. '10' or '10s')."
	| secs r |
	(monitor isNil or: [right isNil]) ifTrue: [^nil].
	secs := Number readFrom: (aString reject: [:c | c isLetter]) ifFail: [^nil].
	r := self plotRect.
	^self screenPointFrom: ((self xOfTime: self data last time - (secs abs * 1000000)) max: r left) @ r center y
! !
