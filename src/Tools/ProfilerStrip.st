Object subclass: #ProfilerStrip
	instanceVariableNames: 'timeline forms front width height q qChanged qNeed right renderedRight renderedNumber renderedNow renderedData renderedFirst key colors segments need'
	classVariableNames: ''
	package: 'Tools'!

ProfilerStrip comment: 'I render the FRAMES overview strip of the Profiler window into a bitmap, one pixel per point, so that a refresh only paints what is new. Time is cut into columns of q µs at fixed positions (column k covers k*q .. (k+1)*q of the microsecond clock), so as time passes the strip scrolls by whole columns: the bitmap shifts left and only the columns of new frames (and the last ones, whose GPU times arrive late) are painted; q changes, and everything is painted again, only when the ring''s span grows by more than 3% (q then leaves 25% to grow into), stopped growing for 2 s 3% below the strip (q fits it exactly again), or when the strip''s size, the shaded Processes or the filter change. Each column shows the frame bar overlapping it that matters most (dropped first, then the longest): the frame time in light grey, stacked on it the CPU of the Processes, draw, raster, GPU and GC (ProfilerTimeline''s colors), the GC lane, the dotted budget line and the base line. Two bitmaps alternate, so the compositor never shows one half painted. The timeline draws me scaled by the display scale without filtering, and its marks and selection on top.'!

!ProfilerStrip methodsFor: 'accessing'!
timeline: aProfilerTimeline
	timeline := aProfilerTimeline
!
form
	^front isNil ifTrue: [nil] ifFalse: [forms at: front]
! !

!ProfilerStrip methodsFor: 'geometry'!
windowFrom: t0 to: t1 columns: n
	"Answer {start. stop} (µs) of the n whole columns ending with the one holding t1. My column width q stays while t0..t1 fits within 3%: a growing span (a ring filling up) gets 25% to grow into, a span 3% shorter that did not grow for 2 s gets an exact fit again."
	| now |
	need := ((t1 - t0) max: n) asFloat / n.
	now := Time millisecondClockValue.
	(q isNil or: [n ~= width]) ifTrue: [q := need. qChanged := now. qNeed := need. renderedRight := nil].
	need > (q * 1.03) ifTrue: [q := need * 1.25. qChanged := now. qNeed := need. renderedRight := nil].
	now - qChanged > 2000 ifTrue: [
		(need < (q / 1.03) and: [need <= (qNeed * 1.01)])
			ifTrue: [q := need. renderedRight := nil].
		qChanged := now.
		qNeed := need].
	right := (t1 / q) floor.
	^Array with: ((right + 1 - n) * q) rounded with: ((right + 1) * q) rounded
! !

!ProfilerStrip methodsFor: 'testing'!
mayRefit
	"Answer whether my column width can change with time alone: it is more than 3% too wide for the span, so it fits again once the span stopped growing for 2 s."
	^q notNil and: [need notNil and: [need < (q / 1.03)]]
! !

!ProfilerStrip methodsFor: 'rendering'!
needsUpdateFor: data geometry: g
	^renderedRight isNil or: [renderedData ~~ data or: [right ~= renderedRight
		or: [width ~= ((g at: 4) rounded max: 1) or: [height ~= (timeline height rounded max: 1)]]]]
!
updateFor: data geometry: g shades: shades order: shadeList ranks: ranks
	"Bring the bitmap up to date for data (a ProfilerData) and the geometry g of ProfilerTimeline>>computeGeometry; shadeList are the shaded Processes, busiest first."
	| w h newKey a back shift firstDirty newest dirtyTime bars |
	w := (g at: 4) rounded max: 1.
	h := timeline height rounded max: 1.
	newKey := Array with: w with: h with: q with: data filter with: data displayHidden with: shadeList.
	(forms isNil or: [width ~= w or: [height ~= h]]) ifTrue: [
		width := w.
		height := h.
		forms := Array with: (ProfilerStripForm width: w height: h) with: (ProfilerStripForm width: w height: h).
		front := 1.
		renderedRight := nil].
	key = newKey ifFalse: [key := newKey. renderedRight := nil. segments := nil. colors := self colorsFor: shades].
	a := (right + 1 - w) * q.
	bars := data bars.
	back := 3 - front.
	shift := renderedRight isNil ifTrue: [w] ifFalse: [right - renderedRight].
	(shift < 0 or: [shift >= w])
		ifTrue: [firstDirty := 0]
		ifFalse: [
			self copyShifted: shift from: (forms at: front) to: (forms at: back).
			"New frames, and the last ones whose GPU times arrived since (they come after the frame)."
			dirtyTime := nil.
			newest := bars size.
			[newest >= 1 and: [(bars at: newest) number > renderedNumber or: [newest > (bars size - 8)]]] whileTrue: [ | bar |
				bar := bars at: newest.
				(bar number > renderedNumber or: [(self hasSegmentsFor: bar record) not])
					ifTrue: [dirtyTime := dirtyTime isNil ifTrue: [bar start] ifFalse: [dirtyTime min: bar start]].
				newest := newest - 1].
			firstDirty := dirtyTime isNil
				ifTrue: [w - shift]
				ifFalse: [(((dirtyTime - a) / q) floor max: 0) min: w - shift]].
	self paintColumns: firstDirty to: w - 1 of: (forms at: back) from: a bars: bars geometry: g shades: shades ranks: ranks.
	"The oldest frames leave the ring at the left edge."
	(firstDirty > 4 and: [bars notEmpty and: [bars first number ~= renderedFirst]]) ifTrue: [
		self paintColumns: 0 to: 3 of: (forms at: back) from: a bars: bars geometry: g shades: shades ranks: ranks].
	(forms at: back) changed.
	front := back.
	renderedRight := right.
	renderedData := data.
	renderedNumber := bars isEmpty ifTrue: [0] ifFalse: [bars last number].
	renderedFirst := bars isEmpty ifTrue: [0] ifFalse: [bars first number].
	renderedNow := data now
!
copyShifted: s from: aForm to: anotherForm
	"anotherForm := aForm moved s columns to the left (the s columns on the right are painted next)."
	| src dst |
	src := aForm bits.
	dst := anotherForm bits.
	s = 0 ifTrue: [^dst replaceFrom: 1 to: dst size with: src startingAt: 1].
	0 to: height - 1 do: [:r | | o |
		o := r * width.
		dst replaceFrom: o + 1 to: o + width - s with: src startingAt: o + s + 1]
!
paintColumns: c0 to: c1 of: aForm from: a bars: bars geometry: g shades: shades ranks: ranks
	| best lo hi i t0 t1 |
	c1 < c0 ifTrue: [^self].
	best := Array new: c1 - c0 + 1.
	t0 := a + (c0 * q).
	t1 := a + ((c1 + 1) * q).
	"The first bar ending at or after t0."
	lo := 1.
	hi := bars size + 1.
	[lo < hi] whileTrue: [ | mid |
		mid := lo + hi // 2.
		(bars at: mid) end < t0 ifTrue: [lo := mid + 1] ifFalse: [hi := mid]].
	i := lo.
	[i <= bars size and: [(bars at: i) start < t1]] whileTrue: [ | bar b0 b1 |
		bar := bars at: i.
		b0 := ((bar start - a) / q) floor max: c0.
		b1 := ((bar end - a) / q) floor min: c1.
		b1 < b0 ifTrue: [b1 := b0].
		b0 to: b1 do: [:c | | old |
			old := best at: c - c0 + 1.
			(old isNil
				or: [(bar isDropped and: [old isDropped not])
				or: [bar isDropped = old isDropped and: [bar duration > old duration]]])
					ifTrue: [best at: c - c0 + 1 put: bar]].
		i := i + 1].
	self paintColumns: c0 to: c1 bars: best of: aForm geometry: g ranks: ranks shades: shades
!
paintColumns: c0 to: c1 bars: best of: aForm geometry: g ranks: ranks shades: shades
	"Paint columns c0 .. c1 (best: the bar of each, or nil) straight into the bitmap: paper, the bar's rows from the bottom up, the budget dots and the base line."
	| bits paper idle ink base padT g8 scale baseRow budgetRow gcLow gcHigh fill |
	bits := aForm bits.
	paper := colors at: #paper.
	idle := colors at: #idle.
	ink := colors at: #ink.
	base := g at: 5.
	padT := g at: 6.
	g8 := g at: 8.
	scale := (base - padT) / g8 asFloat.
	baseRow := base rounded.
	budgetRow := (base - ((FrameRecord budgetMicros / 1000.0 min: g8) * scale)) rounded - 1.
	gcLow := (base + 1) rounded.
	gcHigh := (base + 1 + (g at: 7)) rounded.
	fill := [:c :r0 :r1 :v | | i |
		i := (r0 max: 0) * width + c + 1.
		(r0 max: 0) + 1 to: (r1 min: height) do: [:r | bits at: i put: v. i := i + width]].
	c0 to: c1 do: [:c | | bar |
		bar := best at: c - c0 + 1.
		bar isNil
			ifTrue: [fill value: c value: 0 value: height value: paper]
			ifFalse: [ | top y rec |
				top := base - ((bar milliseconds min: g8) * scale).
				"Paper around the bar, idle under it."
				fill value: c value: 0 value: top rounded value: paper.
				fill value: c value: baseRow value: height value: paper.
				fill value: c value: top rounded value: baseRow value: idle.
				rec := bar record.
				y := base.
				(self segmentsFor: rec ranks: ranks shades: shades) do: [:seg | | hgt |
					hgt := ((seg first / 1000.0) * scale) min: y - top.
					hgt > 0 ifTrue: [
						fill value: c value: (y - hgt) rounded value: y rounded value: seg last.
						y := y - hgt]].
				bar isDropped ifTrue: [fill value: c value: (top - 1) rounded value: (top + 1) rounded value: ink].
				rec gcCount > 0 ifTrue: [fill value: c value: gcLow value: gcHigh value: ink]].
		"The dotted budget line and the base line."
		c \\ 4 < 2 ifTrue: [fill value: c value: budgetRow value: budgetRow + 1 value: ink].
		fill value: c value: baseRow value: baseRow + 1 value: ink]
!
hasSegmentsFor: aFrameRecord
	"Answer whether aFrameRecord was painted with its current GPU time."
	| cached |
	segments isNil ifTrue: [^false].
	cached := segments at: aFrameRecord ifAbsent: [^false].
	^cached first = aFrameRecord gpu
!
segmentsFor: aFrameRecord ranks: ranks shades: shades
	"segmentsOf:ranks:shades:, kept per record until its GPU time changes (it arrives after the frame)."
	| cached |
	segments isNil ifTrue: [segments := IdentityDictionary new].
	cached := segments at: aFrameRecord ifAbsent: [nil].
	(cached notNil and: [cached first = aFrameRecord gpu]) ifTrue: [^cached last].
	segments size > 4000 ifTrue: [segments := IdentityDictionary new].
	cached := Array with: aFrameRecord gpu with: (self segmentsOf: aFrameRecord ranks: ranks shades: shades).
	segments at: aFrameRecord put: cached.
	^cached last
!
segmentsOf: aFrameRecord ranks: ranks shades: shades
	"Answer {µs. pixel} pairs bottom up: the Processes busiest in view first (shaded ones in their shade, others grey), then draw, raster, GPU and GC."
	| result |
	result := OrderedCollection new.
	(timeline processesOf: aFrameRecord ranks: ranks) do: [:p |
		result add: (Array with: (aFrameRecord timeFor: p) with: ((shades includesKey: p) ifTrue: [colors at: p] ifFalse: [colors at: #other]))].
	result add: (Array with: aFrameRecord draw with: (colors at: #draw)).
	result add: (Array with: aFrameRecord raster with: (colors at: #raster)).
	result add: (Array with: aFrameRecord gpu with: (colors at: #raster)).
	aFrameRecord gcMicros > 0 ifTrue: [result add: (Array with: aFrameRecord gcMicros with: (colors at: #ink))].
	^result
!
colorsFor: shades
	| d theme |
	theme := timeline theme.
	d := IdentityDictionary new.
	d at: #paper put: theme paper premultipliedRGBA8.
	d at: #ink put: theme ink premultipliedRGBA8.
	d at: #idle put: ProfilerTimeline idleColor premultipliedRGBA8.
	d at: #other put: ProfilerTimeline otherColor premultipliedRGBA8.
	d at: #draw put: ProfilerTimeline drawColor premultipliedRGBA8.
	d at: #raster put: ProfilerTimeline rasterColor premultipliedRGBA8.
	shades keysAndValuesDo: [:p :color | d at: p put: color premultipliedRGBA8].
	^d
! !
