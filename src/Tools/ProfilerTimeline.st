Widget subclass: #ProfilerTimeline
	instanceVariableNames: 'profiler detailed geometry dragStart dragX moved hoverBar lastDragUpdate strip shadeList segments ranks ranksKey shadesCache idleColor'
	classVariableNames: ''
	package: 'Tools'!

ProfilerTimeline comment: 'I draw the frames of the Profiler window''s snapshot: the FRAMES overview strip (the whole ring, painted incrementally into a bitmap by a ProfilerStrip) or, detailed, the Frames tab''s timeline (2 s, 5 s or all, with the 33 ms grid, labels, marks, a GC lane and a time axis). One bar per presented frame (ProfilerFrameBar): the interval in light grey, stacked on it the CPU the Processes used in it (the three busiest user Processes in ultramarine shades, the rest grey), the compositor''s draw and raster time, the GPU time (hatched) and GC; the dotted 16.7 ms budget; dropped frames outlined. Dragging selects a range (pinning the snapshot), a click selects a frame, hovering shows its record.'!

!ProfilerTimeline methodsFor: 'accessing'!
profiler: aProfilerView
	profiler := aProfilerView
!
detailed: aBoolean
	detailed := aBoolean
!
isDetailed
	^detailed == true
!
hoverBar
	^hoverBar
!
data
	^profiler data
! !

!ProfilerTimeline methodsFor: 'geometry'!
timeWindow
	"Answer {start. stop} (µs) of the time I show (the overview: whole columns of its strip, ending now)."
	| w |
	self isDetailed ifTrue: [^profiler detailWindow].
	w := profiler overviewWindow.
	^self strip windowFrom: w first to: w last columns: (self width - 10) rounded
!
strip
	^strip ifNil: [strip := ProfilerStrip new timeline: self; yourself]
!
computeGeometry
	"Answer {a. b. padLeft. plotWidth. base. plotTop. gcHeight. maxMs}."
	| w a b padL padR padT gcH axH base |
	w := self timeWindow.
	a := w first.
	b := w last max: a + 1.
	padL := self isDetailed ifTrue: [46] ifFalse: [4].
	padR := 6.
	padT := self isDetailed ifTrue: [16] ifFalse: [4].
	gcH := self isDetailed ifTrue: [10] ifFalse: [5].
	axH := self isDetailed ifTrue: [16] ifFalse: [0].
	base := self height - axH - gcH - 2.
	^geometry := {a. b. padL. self isDetailed ifTrue: [self width - padL - padR max: 1] ifFalse: [(self width - padL - padR) rounded max: 1]. base. padT. gcH. self isDetailed ifTrue: [40] ifFalse: [36]}
!
xOf: t
	| g |
	g := geometry.
	^(g at: 3) + ((t - (g at: 1)) asFloat * (g at: 4) / ((g at: 2) - (g at: 1)))
!
timeAtX: x
	| g |
	g := geometry ifNil: [self computeGeometry].
	^((g at: 1) + ((x - (g at: 3)) asFloat * ((g at: 2) - (g at: 1)) / (g at: 4))) rounded
!
yOfMs: ms
	| g |
	g := geometry.
	^(g at: 5) - ((ms min: (g at: 8)) / (g at: 8) * ((g at: 5) - (g at: 6)))
!
clampTime: t
	| g |
	g := geometry ifNil: [self computeGeometry].
	^(t max: (g at: 1)) min: (g at: 2)
!
barAtX: x
	| bar near |
	bar := self data barAt: (self timeAtX: x).
	bar isNil ifFalse: [^bar].
	"between bars (sparse frames are thinner than a point): the nearest within 3 points"
	near := self data barsFrom: (self timeAtX: x - 3) to: (self timeAtX: x + 3).
	near isEmpty ifTrue: [^nil].
	^near detectMin: [:b | ((self xOf: b start) + (self xOf: b end) / 2 - x) abs]
! !

!ProfilerTimeline methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| g bars a b base padT gcH plotRight ranks paper ink target budgetMs shades |
	paper := self theme paper.
	ink := self theme ink.
	aCanvas fillRect: self localBounds color: paper.
	profiler isNil ifTrue: [^self].
	self data isNil ifTrue: [^self].
	self isDetailed ifFalse: [^self drawOverviewOn: aCanvas].
	g := self computeGeometry.
	a := g at: 1.
	b := g at: 2.
	base := g at: 5.
	padT := g at: 6.
	gcH := g at: 7.
	plotRight := (g at: 3) + (g at: 4).
	bars := self data barsFrom: a to: b.
	ranks := self ranksFor: bars key: (Array with: self data with: a with: b with: self data filter).
	target := self data filter.
	shades := shadesCache ifNil: [shadesCache := self shadesFor: ranks target: target].
	budgetMs := FrameRecord budgetMicros / 1000.0.
	self isDetailed ifTrue: [
		aCanvas fillRect: ((g at: 3) @ (self yOfMs: 33.3) rounded extent: (g at: 4) @ 0.5) color: (self theme color: #ink4).
		aCanvas drawString: '33 ms' in: (0 @ ((self yOfMs: 33.3) - 8) corner: ((g at: 3) - 5) @ ((self yOfMs: 33.3) + 8))
			font: (self theme font: #smallItalic) color: self theme muted align: #right].
	aCanvas clip: ((g at: 3) @ 0 corner: plotRight @ self height) during: [
		(self barsToDraw: bars) do: [:bar | self drawBar: bar ranks: ranks shades: shades on: aCanvas]].
	"budget line"
	(g at: 3) to: plotRight - 2 by: 4 do: [:x |
		aCanvas fillRect: (x @ ((self yOfMs: budgetMs) rounded - 0.5) extent: 2 @ 1) color: ink].
	self isDetailed ifTrue: [
		aCanvas drawString: '16.7' in: (0 @ ((self yOfMs: budgetMs) - 8) corner: ((g at: 3) - 5) @ ((self yOfMs: budgetMs) + 8))
			font: (self theme font: #small) color: ink align: #right].
	aCanvas fillRect: ((g at: 3) @ base extent: (g at: 4) @ 1) color: ink.
	self drawMarksOn: aCanvas.
	self drawSelectionOn: aCanvas.
	self isDetailed ifTrue: [self drawAxisOn: aCanvas]
!
drawOverviewOn: aCanvas
	"The strip's bitmap (painted incrementally), the marks and the selection on top."
	| g ranks shades |
	g := self computeGeometry.
	(self strip needsUpdateFor: self data geometry: g) ifTrue: [
		ranks := self data barTotals.
		shades := self shadesFor: ranks target: self data filter.
		self strip updateFor: self data geometry: g shades: shades order: shadeList ranks: ranks].
	aCanvas image: self strip form in: ((g at: 3) @ 0 extent: (g at: 4) @ self strip form height).
	self drawMarksOn: aCanvas.
	self drawSelectionOn: aCanvas
!
barsToDraw: bars
	"Answer bars, thinned to one per point column where they are narrower than that (the slowest of each column, a dropped one first), so drawing stays cheap with a full ring."
	| columns result |
	bars size * 1.5 < (geometry at: 4) ifTrue: [^bars].
	columns := Dictionary new.
	bars do: [:bar | | x old |
		x := (self xOf: bar end) floor.
		old := columns at: x ifAbsent: [nil].
		(old isNil
			or: [(bar isDropped and: [old isDropped not])
			or: [bar isDropped = old isDropped and: [bar duration > old duration]]])
				ifTrue: [columns at: x put: bar]].
	result := OrderedCollection new.
	bars do: [:bar | (columns at: (self xOf: bar end) floor) == bar ifTrue: [result add: bar]].
	^result
!
drawBar: bar ranks: someRanks shades: shades on: aCanvas
	| x0 x1 w top y rec base ms |
	base := geometry at: 5.
	x0 := self xOf: bar start.
	x1 := self xOf: bar end.
	x1 - x0 >= 4 ifTrue: [x1 := x1 - 1].
	w := (x1 - x0) max: 1.
	ms := bar milliseconds.
	top := self yOfMs: ms.
	aCanvas fillLeft: x0 top: top right: x0 + w bottom: base color: (idleColor ifNil: [idleColor := self class idleColor]).
	rec := bar record.
	y := base.
	(self segmentsOf: rec ranks: someRanks shades: shades) do: [:seg | | h color |
		h := ((seg first / 1000.0) / (geometry at: 8) * (base - (geometry at: 6))) min: y - top.
		h > 0 ifTrue: [
			color := seg last.
			color isSymbol
				ifTrue: [
					w >= 2
						ifTrue: [
							aCanvas fillLeft: x0 top: y - h right: x0 + w bottom: y color: self theme paper.
							aCanvas pattern: #diagonalStripes in: (x0 @ (y - h) extent: w @ h) color: self theme ink]
						ifFalse: [aCanvas fillLeft: x0 top: y - h right: x0 + w bottom: y color: self class rasterColor]]
				ifFalse: [aCanvas fillLeft: x0 top: y - h right: x0 + w bottom: y color: color].
			y := y - h]].
	bar isDropped ifTrue: [
		aCanvas fillRect: (x0 @ (top - (self isDetailed ifTrue: [2] ifFalse: [1])) extent: w @ (self isDetailed ifTrue: [3] ifFalse: [2])) color: self theme ink.
		self isDetailed ifTrue: [
			aCanvas strokeRect: (x0 @ top corner: (x0 + w) @ base) color: self theme ink width: 1.
			self drawTriangleAt: (x0 + (w / 2)) @ (base + (geometry at: 7) + 3) on: aCanvas]].
	rec gcCount > 0 ifTrue: [
		aCanvas fillRect: (x0 rounded @ (base + 1) extent: 1.5 @ (geometry at: 7)) color: self theme ink].
	self isDetailed ifTrue: [
		profiler selectedBar == bar ifTrue: [
			aCanvas strokeRect: ((x0 - 1) @ (top - 4) corner: (x0 + w + 1) @ base) color: self theme ultramarine width: 1.5].
		hoverBar == bar ifTrue: [
			aCanvas fillRect: (x0 @ (geometry at: 6) corner: (x0 + w) @ base) color: (Color black alpha: 0.06)]]
!
segmentsOf: aFrameRecord ranks: someRanks shades: shades
	"Answer {µs. color} pairs bottom up: the Processes (busiest in view first; shaded ones in their shade, the others grey), draw, raster, GPU (#hatch) and GC; kept per record until its GPU time (it arrives after the frame) or the shaded Processes change."
	| cached result |
	segments isNil ifTrue: [segments := IdentityDictionary new].
	cached := segments at: aFrameRecord ifAbsent: [nil].
	(cached notNil and: [(cached at: 1) = aFrameRecord gpu and: [(cached at: 2) = shadeList]]) ifTrue: [^cached at: 3].
	result := OrderedCollection new.
	(self processesOf: aFrameRecord ranks: someRanks) do: [:p |
		result add: (Array with: (aFrameRecord timeFor: p) with: (shades at: p ifAbsent: [self class otherColor]))].
	result add: (Array with: aFrameRecord draw with: self class drawColor).
	result add: (Array with: aFrameRecord raster with: self class rasterColor).
	result add: (Array with: aFrameRecord gpu with: #hatch).
	aFrameRecord gcMicros > 0 ifTrue: [result add: (Array with: aFrameRecord gcMicros with: self theme ink)].
	segments size > 3000 ifTrue: [segments := IdentityDictionary new].
	segments at: aFrameRecord put: (Array with: aFrameRecord gpu with: shadeList with: result asArray).
	^result asArray
!
drawTriangleAt: aPoint on: aCanvas
	0 to: 5 do: [:i |
		aCanvas fillRect: ((aPoint x - (i * 0.6)) @ (aPoint y + i) extent: (i * 1.2) + 0.6 @ 1) color: self theme ink]
!
processesOf: aFrameRecord ranks: ranks
	"The Processes to stack for aFrameRecord, busiest (in view) first; not idle, not the compositor (its draw and raster are shown separately)."
	| ps |
	ps := aFrameRecord processTimes keys asArray reject: [:p | (self data isIdle: p) or: [self class isCompositor: p]].
	^ps sort: [:p :q | (ranks at: p ifAbsent: [0]) > (ranks at: q ifAbsent: [0])]
!
ranksFor: bars key: anArray
	"ranksFor: bars, again only when the data or the window changed (I redraw also for hovering and animations)."
	ranksKey = anArray ifTrue: [^ranks].
	ranksKey := anArray.
	shadesCache := nil.
	^ranks := (self data bars size = bars size and: [self data barTotals notNil])
		ifTrue: [self data barTotals]
		ifFalse: [self ranksFor: bars]
!
ranksFor: bars
	"Answer an IdentityDictionary Process -> CPU µs in view (user Processes; they get the ultramarine shades by rank)."
	| totals |
	totals := IdentityDictionary new.
	bars do: [:bar |
		bar record processTimes keysAndValuesDo: [:p :us |
			totals at: p put: (totals at: p ifAbsent: [0]) + us]].
	^totals
!
users: isUserBlock of: ranks top: n
	"Answer the n busiest Processes of ranks (Process -> µs) that isUserBlock accepts, busiest first."
	| top |
	top := OrderedCollection new.
	ranks keysAndValuesDo: [:p :us |
		(top size < n or: [us > (ranks at: top last)]) ifTrue: [
			(isUserBlock value: p) ifTrue: [ | i |
				i := top size.
				[i >= 1 and: [(ranks at: (top at: i)) < us]] whileTrue: [i := i - 1].
				top add: p beforeIndex: i + 1.
				top size > n ifTrue: [top removeLast]]]].
	^top asArray
!
shadesFor: ranks target: target
	"Answer an IdentityDictionary Process -> Color: with a Process selected, it in ultramarine; else the three busiest user Processes in view in ultramarine shades (first the busiest). Everything else is grey. A Process keeps its shade while it stays among them: another one takes the place of the least busy only when it is busier by 10% and 2% of the busiest, so colors neither flicker nor swap (shadeList holds them by shade)."
	| shades users list margin rank isUser stopped consider |
	shades := IdentityDictionary new.
	target == #all ifFalse: [
		shades at: target put: (self class processShade: 1).
		shadeList := Array with: target.
		^shades].
	isUser := [:p | (self class isUserProcess: p) and: [(self data isIdle: p) not]].
	"The busiest users first; once the three places are taken and one fails to take a place, the less busy ones fail too, so a few are enough (all only if they all got through)."
	users := self users: isUser of: ranks top: 8.
	rank := [:p | p isNil ifTrue: [-1] ifFalse: [ranks at: p ifAbsent: [0]]].
	margin := users isEmpty ifTrue: [0] ifFalse: [(rank value: users first) * 0.02].
	list := Array new: 3.
	(shadeList notNil and: [shadeList size = 3]) ifTrue: [
		1 to: 3 do: [:i | | p |
			p := shadeList at: i.
			(p notNil and: [(ranks includesKey: p) and: [isUser value: p]]) ifTrue: [list at: i put: p]]].
	stopped := false.
	consider := [:c |
		(stopped or: [list includes: c]) ifFalse: [ | free weakest |
			free := list indexOf: nil.
			free > 0
				ifTrue: [list at: free put: c]
				ifFalse: [
					weakest := (1 to: 3) inject: 1 into: [:m :i | (rank value: (list at: i)) < (rank value: (list at: m)) ifTrue: [i] ifFalse: [m]].
					(rank value: c) > ((rank value: (list at: weakest)) * 1.1 + margin)
						ifTrue: [list at: weakest put: c]
						ifFalse: [stopped := true]]]].
	users do: consider.
	(stopped not and: [users size = 8]) ifTrue: [
		users := self users: isUser of: ranks top: ranks size.
		9 to: users size do: [:i | consider value: (users at: i)]].
	shadeList := list.
	list doWithIndex: [:p :i | p isNil ifFalse: [shades at: p put: (self class processShade: i)]].
	^shades
!
drawMarksOn: aCanvas
	| g font ink |
	g := geometry.
	font := self theme font: #smallItalic.
	ink := self theme ink.
	self data marks do: [:m |
		(m time between: (g at: 1) and: (g at: 2)) ifTrue: [ | x |
			x := (self xOf: m time) rounded.
			((g at: 6) - (self isDetailed ifTrue: [12] ifFalse: [2])) to: (g at: 5) by: 3 do: [:y |
				aCanvas fillLeft: x top: y right: x + 1 bottom: y + 1.5 color: ink].
			self isDetailed ifTrue: [
				aCanvas drawString: m label at: (x + 3) @ 0 font: font color: self theme ink]]]
!
drawSelectionOn: aCanvas
	| range g x0 x1 bottom left right |
	range := profiler selectionRange.
	range isNil ifTrue: [^self].
	g := geometry.
	left := g at: 3.
	right := left + (g at: 4).
	x0 := ((self xOf: range first) max: left) min: right.
	x1 := ((self xOf: range last) max: left) min: right.
	bottom := (g at: 5) + (g at: 7) + 2.
	aCanvas fillRect: (left @ 0 corner: x0 @ bottom) color: (Color white alpha: 0.7).
	aCanvas fillRect: (x1 @ 0 corner: right @ bottom) color: (Color white alpha: 0.7).
	aCanvas fillRect: (x0 @ 0 corner: x1 @ bottom) color: (self theme ultramarine alpha: 0.10).
	aCanvas fillRect: ((x0 rounded - 0.5) @ 0 extent: 1.5 @ bottom) color: self theme ultramarine.
	aCanvas fillRect: ((x1 rounded - 1) @ 0 extent: 1.5 @ bottom) color: self theme ultramarine
!
drawAxisOn: aCanvas
	| g now span step t font y |
	g := geometry.
	font := self theme font: #smallItalic.
	now := self data now.
	span := (g at: 2) - (g at: 1).
	step := span > 8000000 ifTrue: [2000000] ifFalse: [span > 3000000 ifTrue: [1000000] ifFalse: [500000]].
	y := (g at: 5) + (g at: 7) + 2.
	t := ((g at: 1) - now / step) ceiling * step.
	[t <= ((g at: 2) - now + 1)] whileTrue: [ | x label |
		x := self xOf: now + t.
		(x >= ((g at: 3) + 10) and: [x <= ((g at: 3) + (g at: 4) - 4)]) ifTrue: [
			aCanvas fillRect: (x rounded @ y extent: 1 @ 3) color: self theme muted.
			label := t = 0
				ifTrue: ['now']
				ifFalse: [((t / 1000000.0) printShowingDecimalPlaces: (step < 1000000 ifTrue: [1] ifFalse: [0])), ' s'].
			aCanvas drawString: label in: ((x - 30) @ (y + 2) corner: (x + 30) @ (y + 16)) font: font color: self theme muted align: #center].
		t := t + step].
	aCanvas drawString: 'GC' in: (4 @ ((g at: 5) + 1) corner: 30 @ ((g at: 5) + 1 + (g at: 7))) font: font color: self theme muted align: #left
! !

!ProfilerTimeline methodsFor: 'events'!
mouseDown: anEvent
	anEvent button = 1 ifFalse: [^false].
	profiler isNil ifTrue: [^true].
	self computeGeometry.
	dragX := (self localEventPosition: anEvent) x.
	dragStart := self clampTime: (self timeAtX: dragX).
	moved := false.
	^true
!
mouseMove: anEvent
	| x t1 now |
	x := (self localEventPosition: anEvent) x.
	dragStart isNil ifTrue: [
		self isDetailed ifTrue: [self hoverAt: (self localEventPosition: anEvent)].
		^true].
	(moved not and: [(x - dragX) abs < 4]) ifTrue: [^true].
	moved := true.
	t1 := self clampTime: (self timeAtX: x).
	now := Time millisecondClockValue.
	profiler dragRange: (Array with: (dragStart min: t1) with: (dragStart max: t1))
		final: false
		refilter: (lastDragUpdate isNil or: [now - lastDragUpdate > 120]).
	(lastDragUpdate isNil or: [now - lastDragUpdate > 120]) ifTrue: [lastDragUpdate := now].
	^true
!
mouseUp: anEvent
	| x t1 bar |
	dragStart isNil ifTrue: [^true].
	x := (self localEventPosition: anEvent) x.
	moved
		ifTrue: [
			t1 := self clampTime: (self timeAtX: x).
			profiler dragRange: (Array with: (dragStart min: t1) with: (dragStart max: t1)) final: true refilter: true]
		ifFalse: [
			bar := self barAtX: x.
			bar isNil
				ifTrue: [profiler clearRange]
				ifFalse: [profiler selectBar: bar fromOverview: self isDetailed not]].
	dragStart := nil.
	lastDragUpdate := nil.
	^true
!
hoverAt: aPoint
	| bar |
	geometry isNil ifTrue: [^self].
	bar := (aPoint y between: 0 and: (geometry at: 5)) ifTrue: [self barAtX: aPoint x] ifFalse: [nil].
	bar == hoverBar ifFalse: [
		hoverBar := bar.
		self invalidate].
	bar isNil
		ifTrue: [profiler hideTip]
		ifFalse: [profiler showTip: (profiler tipLinesForBar: bar) near: (self pointInWindow: aPoint)]
!
mouseLeave: anEvent
	hoverBar isNil ifFalse: [hoverBar := nil. self invalidate].
	profiler isNil ifFalse: [profiler hideTip].
	^false
!
cursorAt: aPoint
	^#crosshair
! !

!ProfilerTimeline methodsFor: 'remote control'!
remoteRole
	^#chart
!
remoteLabel
	| bars w dropped worst |
	(profiler isNil or: [self data isNil]) ifTrue: [^nil].
	w := self timeWindow.
	bars := self data barsFrom: w first to: w last.
	dropped := (bars select: [:b | b isDropped]) size.
	worst := bars inject: 0 into: [:m :b | m max: b duration].
	^(self isDetailed ifTrue: ['Frame timeline: '] ifFalse: ['Frame overview: ']),
		(ProfilerFormat seconds: w last - w first), ', ', bars size printString, ' frames, ',
		dropped printString, ' dropped, worst ', (ProfilerFormat ms: worst)
!
remoteState
	| s range |
	s := OrderedCollection new.
	profiler isNil ifTrue: [^#()].
	range := profiler selectionRange.
	range isNil ifFalse: [s add: 'sel=', (self remoteQuote: (ProfilerFormat span: range last - range first))].
	profiler selectedBar isNil ifFalse: [s add: 'frame=#', profiler selectedBar number printString].
	"Where time is on the screen, so a client can drag over a given time range: the plot's screen x range and the µs it spans."
	self data isNil ifFalse: [ | g x0 x1 |
		g := self computeGeometry.
		x0 := (self screenPointFrom: (g at: 3) @ 0) x.
		x1 := (self screenPointFrom: ((g at: 3) + (g at: 4)) @ 0) x.
		s add: 'plot=', x0 rounded printString, '-', x1 rounded printString.
		s add: 'time=', (g at: 1) printString, '-', (g at: 2) printString].
	^s asArray
!
remoteChildren
	"The detailed timeline's bars (clickable), newest last."
	| w bars |
	(self isDetailed not or: [profiler isNil or: [self data isNil]]) ifTrue: [^#()].
	geometry isNil ifTrue: [self computeGeometry].
	w := self timeWindow.
	bars := self data barsFrom: w first to: w last.
	^bars collect: [:bar | | x0 x1 part |
		x0 := self xOf: bar start.
		x1 := (self xOf: bar end) max: x0 + 1.
		part := WidgetPart of: self role: #'frame-bar'
			label: '#', bar number printString, ' ', (ProfilerFormat ms: bar duration), (bar isDropped ifTrue: [' dropped'] ifFalse: [''])
			state: (profiler selectedBar == bar ifTrue: [#(#selected)] ifFalse: [#()])
			rect: (x0 @ (geometry at: 6) corner: x1 @ (geometry at: 5)).
		part name: 'frame-', bar number printString.
		part]
! !

!ProfilerTimeline class methodsFor: 'colors'!
processShade: rank
	^Color hex: (#(16r1B3A8C 16r7D8FBF 16rC3CBE2) at: rank)
!
otherColor
	^Color hex: 16rB8B8B8
!
drawColor
	^Color black
!
rasterColor
	^Color hex: 16r6B6B6B
!
idleColor
	^Color hex: 16rE2E2E2
! !

!ProfilerTimeline class methodsFor: 'processes'!
isCompositor: aProcess
	^aProcess name notNil and: [aProcess name beginsWith: 'compositor']
!
isUserProcess: aProcess
	"Window and user Processes (priority 40 and below) rather than the system's."
	^aProcess priority <= 40
! !
