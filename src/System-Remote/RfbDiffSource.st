RfbFrameSource subclass: #RfbDiffSource
	instanceVariableNames: 'inner extent copy valid pending copyLock refreshes comparedArea changedArea diffMs scrolls lastScroll lastScrollRow movedTo'
	classVariableNames: ''
	package: 'System-Remote'!

RfbDiffSource comment: 'I am a frame source that takes unchanged pixels out of another''s damage, as QEMU''s VNC server does: I keep one copy of the screen as it was last compared (BGRA8, shared by all my listeners whatever their pixel format: 8 MB at 1920x1080, made when the first listener comes and dropped when the last goes), and when a listener''s writer collects its damage (collectFor:) I read what my source damaged since (once, for all of them), compare it with my copy in 16x16 blocks (the VM''s pixelBlocksDiff primitive, a rectangle at a time: 16 bytes at a time, skipping blocks of a band already known to differ; compareInSmalltalk:with:into: the same with ByteArray>>indexOfMismatchAt:with:at:size:), copy it in, and give every listener the blocks that changed, joined into runs (takeDamage:full:extent:; RfbDamage merges them further: a rectangle''s header against the unchanged pixels between). Re-laid-out text damages a whole paragraph of which few pixels change; a list redrawn the same changes none.

Pixels sent (bgraOf:, bgraOfAll:) come from my copy, so each listener''s client has my copy less the damage it has yet to take: correct for any number of listeners, a slow one''s damage merging meanwhile, and a pixel that changes after it was compared is in my source''s next damage. A move (moved:to:: the compositor''s, of a window dragged, through the frame tap) moves my copy''s pixels too and is passed on (CopyRect); its destination is compared again, since a move is a hint (a window over the moved one, damage at its origin not yet compared). A tall damaged rectangle whose sample rows are my copy''s rows a few rows lower or higher (a list or text scrolled: findScrollIn:pixels:) is such a move too, found here. A new size (resized:, or the extent a polled source hands me) makes my copy anew, all of it damage. Push sources (RfbBufferSource) tell me at once, and I only note the damage and wake my listeners; polled ones (RfbTapSource) signal me as a listener''s semaphore (signal wakes all of mine) and hand me their damage in collectFor:.

statistics: how often I compared (or made my copy whole), the area compared and the area found changed in it (pixels), and the time it took (ms).'!

!RfbDiffSource methodsFor: 'initialization'!
setInner: anRfbFrameSource
	inner := anRfbFrameSource.
	valid := false.
	copyLock := Semaphore forMutualExclusion.
	refreshes := 0.
	comparedArea := 0.
	changedArea := 0.
	diffMs := 0.
	scrolls := 0
! !

!RfbDiffSource methodsFor: 'accessing'!
inner
	^inner
!
blockSize
	^16
!
statistics
	^Dictionary new
		at: 'refreshes' put: refreshes;
		at: 'comparedArea' put: comparedArea;
		at: 'changedArea' put: changedArea;
		at: 'diffMs' put: diffMs;
		at: 'scrolls' put: scrolls;
		yourself
!
hasCopy
	^copy notNil
! !

!RfbDiffSource methodsFor: 'screen'!
extent
	^extent ifNil: [inner extent]
!
cursor
	^inner cursor
!
pointScale
	^inner pointScale
!
bgraOf: aRectangle
	^(self bgraOfAll: (Array with: aRectangle)) first
!
bgraOfAll: rects
	"From my copy (black where it has none, or a rectangle lies outside it: a new size, whose damage follows)."
	^copyLock critical: [
		rects collect: [:r | | out w |
			w := r width.
			out := ByteArray new: r area * 4.
			(copy notNil and: [(0 @ 0 extent: extent) containsRect: r]) ifTrue: [
				0 to: r height - 1 do: [:y |
					out replaceFrom: y * w * 4 + 1 to: y + 1 * w * 4 with: copy startingAt: (r top + y) * extent x + r left * 4 + 1]].
			out]]
! !

!RfbDiffSource methodsFor: 'listeners'!
attach: aListener
	| first |
	first := false.
	self lock critical: [
		first := self listeners isEmpty.
		listeners := self listeners copyWith: aListener].
	first ifTrue: [
		copyLock critical: [
			extent := inner extent.
			copy := nil.
			valid := false.
			pending := nil].
		inner attach: self]
!
detach: aListener
	| last |
	self lock critical: [
		last := (self listeners includes: aListener) and: [self listeners size = 1].
		listeners := self listeners copyWithout: aListener].
	last ifTrue: [
		inner detach: self.
		copyLock critical: [
			copy := nil.
			valid := false.
			pending := nil.
			extent := nil]]
!
wakeSemaphore
	"What a polled source signals when it has damage for me: myself (signal)."
	^self
!
signal
	"Wake all my listeners' writers."
	self listeners do: [:each | each wakeSemaphore signal]
!
collectFor: aListener
	"aListener's writer is about to look at its damage: compare what my source damaged since anyone last did, and hand the blocks that changed to all my listeners."
	| changed |
	inner collectFor: self.
	changed := self refresh.
	changed ifTrue: [self listeners do: [:each | each == aListener ifFalse: [each wakeSemaphore signal]]]
! !

!RfbDiffSource methodsFor: 'source events'!
damageExtent
	^extent
!
takeDamage: rects full: isFull extent: anExtent
	"From a polled source (in collectFor:)."
	copyLock critical: [
		self noteExtent: anExtent.
		pending isNil ifFalse: [isFull ifTrue: [pending beFull] ifFalse: [pending addAll: rects]]]
!
damaged: aCollectionOfRectangles
	copyLock critical: [pending isNil ifFalse: [pending addAll: aCollectionOfRectangles]].
	self signal
!
damagedAll
	copyLock critical: [pending isNil ifFalse: [pending beFull]].
	self signal
!
resized: anExtent
	copyLock critical: [self noteExtent: anExtent].
	self signal
!
cursorChanged
	self listeners do: [:each | each cursorChanged]
!
moved: aRectangle to: aPoint
	"My source moved aRectangle's pixels to aPoint: so do I, and so may my listeners (CopyRect); the destination is compared again (the move is a hint: a window over the moved one, or damage at its origin I have yet to compare, makes the screen differ there)."
	| dest bounds |
	dest := aPoint extent: aRectangle extent.
	copyLock critical: [
		bounds := 0 @ 0 extent: (extent ifNil: [0 @ 0]).
		(valid and: [(bounds containsRect: aRectangle) and: [bounds containsRect: dest]])
			ifTrue: [
				self moveCopy: aRectangle to: aPoint.
				pending isNil ifFalse: [pending add: dest].
				(movedTo ifNil: [movedTo := OrderedCollection new]) add: dest.
				self listeners do: [:each | each moved: aRectangle to: aPoint]]
			ifFalse: [pending isNil ifFalse: [pending add: dest]]].
	self signal
! !

!RfbDiffSource methodsFor: 'comparing'!
refresh
	"Compare my source's damage since the last time with my copy (a copy made whole first if I have none) and give my listeners what changed; answer whether anything did."
	| start rects buffers changed full e |
	^copyLock critical: [
		e := extent.
		(e isNil or: [pending isNil and: [valid]]) ifTrue: [^false].
		(inner extent = e) ifFalse: [^false].
		start := Time millisecondClockValue.
		valid
			ifFalse: [
				copy := inner bgraOf: (0 @ 0 extent: e).
				copy size = (e x * e y * 4) ifFalse: [copy := ByteArray new: e x * e y * 4].
				valid := true.
				pending := RfbDamage extent: e.
				pending maxRects: 64.
				full := true.
				changed := #()]
			ifTrue: [
				pending isEmpty ifTrue: [^false].
				full := false.
				rects := pending rects asArray.
				pending reset.
				buffers := inner bgraOfAll: rects.
				rects with: buffers do: [:r :b | b size = (r area * 4) ifTrue: [self findScrollIn: r pixels: b]].
				changed := OrderedCollection new.
				rects with: buffers do: [:r :b |
					comparedArea := comparedArea + r area.
					b size = (r area * 4) ifTrue: [self compare: r with: b into: changed]].
				movedTo := nil.
				changed isEmpty ifTrue: [
					refreshes := refreshes + 1.
					diffMs := diffMs + (Time millisecondClockValue - start).
					^false]].
		refreshes := refreshes + 1.
		movedTo := nil.
		changedArea := changedArea + (changed inject: 0 into: [:sum :r | sum + r area]).
		self listeners do: [:each | each takeDamage: changed full: full extent: e].
		diffMs := diffMs + (Time millisecondClockValue - start).
		true]
!
compare: r with: bytes into: changed
	"Compare r's pixels (bytes: its BGRA8 rows) with my copy, copy them in, and add the 16x16 blocks (clipped to r) that differ to changed: runs of blocks in a band of 16 rows, joined with the run of the same columns in the band above. The VM's pixelBlocksDiff marks the blocks; compareInSmalltalk:with:into: where it cannot."
	| bs firstBlock cols bands marks n open bandTop |
	bs := self blockSize.
	firstBlock := r left // bs.
	cols := (r right - 1) // bs - firstBlock + 1.
	bands := (r bottom - 1) // bs - (r top // bs) + 1.
	marks := ByteArray new: cols * bands.
	n := self primBlocks: bytes width: r width height: r height into: copy stride: extent x * 4 left: r left top: r top block: bs marks: marks.
	n isNil ifTrue: [^self compareInSmalltalk: r with: bytes into: changed].
	n = 0 ifTrue: [^self].
	open := OrderedCollection new.
	bandTop := r top.
	0 to: bands - 1 do: [:b | | bottom |
		bottom := (r top // bs + b + 1) * bs min: r bottom.
		open := self band: bandTop to: bottom marks: marks at: b * cols first: firstBlock left: r left right: r right open: open into: changed.
		bandTop := bottom].
	changed addAll: open
!
primBlocks: bytes width: w height: h into: aCopy stride: stride left: left top: top block: bs marks: marks
	"The VM's pixelBlocksDiff (ObjectPrimitives>>primPixelBlocksDiff): compare and copy in, marking the blocks that differ; answer how many do, nil if it cannot (an older VM, arguments out of range)."
	<primitive: 'pixelBlocksDiff'>
	^nil
!
compareInSmalltalk: r with: bytes into: changed
	"compare:with:into:, the blocks found here."
	| bs w stride left right firstBlock marks bandTop open y |
	bs := self blockSize.
	w := r width.
	stride := extent x * 4.
	left := r left.
	right := r right.
	firstBlock := left // bs.
	marks := ByteArray new: (right - 1) // bs - firstBlock + 1.
	open := OrderedCollection new.
	bandTop := r top.
	y := r top.
	[y < r bottom] whileTrue: [| from to x |
		from := (y - r top) * w * 4 + 1.
		to := y * stride + (left * 4) + 1.
		x := left.
		[x < right] whileTrue: [| k e m |
			k := x // bs - firstBlock + 1.
			(marks at: k) = 0
				ifTrue: [
					e := x.
					[e < right and: [(marks at: e // bs - firstBlock + 1) = 0]] whileTrue: [e := (e // bs + 1) * bs min: right].
					m := bytes indexOfMismatchAt: from + (x - left * 4) with: copy at: to + (x - left * 4) size: e - x * 4.
					m = 0
						ifTrue: [x := e]
						ifFalse: [| px |
							px := x + (m - 1 // 4).
							marks at: px // bs - firstBlock + 1 put: 1.
							x := (px // bs + 1) * bs]]
				ifFalse: [x := (x // bs + 1) * bs]].
		copy replaceFrom: to to: to + (w * 4) - 1 with: bytes startingAt: from.
		y := y + 1.
		(y \\ bs = 0 or: [y = r bottom]) ifTrue: [
			open := self band: bandTop to: y marks: marks at: 0 first: firstBlock left: left right: right open: open into: changed.
			marks atAllPut: 0.
			bandTop := y]].
	changed addAll: open
!
band: top to: bottom marks: marks at: base first: firstBlock left: left right: right open: open into: changed
	"The runs of marked blocks of a band (marks after base, a byte a block from firstBlock to right) as rectangles: each one that continues a run of open (the band above, same columns) grows it; the open runs it does not continue are done (into changed). Answer the band's runs."
	| bs runs k cols |
	bs := self blockSize.
	cols := (right - 1) // bs - firstBlock + 1.
	runs := OrderedCollection new.
	k := 1.
	[k <= cols] whileTrue: [
		(marks at: base + k) = 0
			ifTrue: [k := k + 1]
			ifFalse: [| j x0 x1 above |
				j := k.
				[j < cols and: [(marks at: base + j + 1) ~= 0]] whileTrue: [j := j + 1].
				x0 := (firstBlock + k - 1) * bs max: left.
				x1 := (firstBlock + j) * bs min: right.
				above := open detect: [:o | o left = x0 and: [o right = x1 and: [o bottom = top]]] ifNone: [nil].
				above isNil
					ifTrue: [runs add: (x0 @ top corner: x1 @ bottom)]
					ifFalse: [
						open remove: above.
						runs add: (above origin corner: x1 @ bottom)].
				k := j + 1]].
	changed addAll: open.
	^runs
! !

!RfbDiffSource methodsFor: 'scrolling'!
findScrollIn: r pixels: bytes
	"If the new pixels of r (bytes) are my copy's scrolled up or down (a list or text scrolled: sample rows of it found again in my copy, all at the same distance), move my copy's rows and tell my listeners (moved:to:, a CopyRect); comparing r afterwards finds what the scroll uncovered, and what did not scroll with it."
	| dy src rows |
	dy := self scrollOf: r pixels: bytes.
	dy isNil ifTrue: [^self].
	rows := self rowsScrolledBy: dy in: r pixels: bytes.
	rows last - rows first < 16 ifTrue: [^self].
	src := r left @ (r top + rows first + dy) corner: r right @ (r top + rows last + dy).
	self moveCopy: src to: src left @ (src top - dy).
	scrolls := scrolls + 1.
	self listeners do: [:each | each moved: src to: src left @ (src top - dy)]
!
rowsScrolledBy: dy in: r pixels: bytes
	"{first. last + 1}: the rows of r (0-based) around the sample row that told dy which are my copy's rows dy lower (higher if dy is negative), in the middle of r: what scrolled (text inserted above a paragraph moves only what follows it)."
	| h w x0 n y0 y1 |
	h := r height.
	w := r width.
	x0 := w // 8.
	n := w - (2 * x0) * 4.
	y0 := lastScrollRow.
	[y0 > 0 and: [y0 - 1 + dy >= 0 and: [y0 - 1 + dy < h and: [self row: y0 - 1 of: r pixels: bytes at: n from: x0 matchesCopyRow: y0 - 1 + dy]]]] whileTrue: [y0 := y0 - 1].
	y1 := lastScrollRow + 1.
	[y1 < h and: [y1 + dy >= 0 and: [y1 + dy < h and: [self row: y1 of: r pixels: bytes at: n from: x0 matchesCopyRow: y1 + dy]]]] whileTrue: [y1 := y1 + 1].
	^Array with: y0 with: y1
!
scrollOf: r pixels: bytes
	"The rows dy (not 0; the last one found first, then the nearest, at most half of r's height or 64) by which r's content moved up (down if negative): its new row y is my copy's row y + dy, for the middle of each sample row that changed and is not of one colour; nil if there is none (or fewer than 3 such rows to tell it by), or if r is where a window was moved to (the compositor told: moved:to:)."
	| h w x0 n stride samples first limit |
	h := r height.
	w := r width.
	(h >= 48 and: [w >= 32]) ifFalse: [^nil].
	(movedTo notNil and: [movedTo anySatisfy: [:each | each intersects: r]]) ifTrue: [^nil].
	x0 := w // 8.
	n := w - (2 * x0) * 4.
	stride := extent x * 4.
	samples := OrderedCollection new.
	1 to: 12 do: [:k | | y from |
		y := h * k // 13.
		from := y * w * 4 + (x0 * 4) + 1.
		((bytes indexOfMismatchAt: from with: copy at: (r top + y) * stride + (r left + x0 * 4) + 1 size: n) ~= 0
			and: [(bytes indexOfMismatchAt: from with: bytes at: from + 4 size: n - 4) ~= 0])
				ifTrue: [samples add: y]].
	samples size < 3 ifTrue: [^nil].
	first := samples at: samples size + 1 // 2.
	lastScrollRow := first.
	limit := h // 2 min: 64.
	(lastScroll notNil and: [lastScroll abs <= (h // 2) and: [self scroll: lastScroll fits: samples first: first in: r pixels: bytes at: n from: x0]]) ifTrue: [^lastScroll].
	1 to: limit do: [:a |
		(self scroll: a fits: samples first: first in: r pixels: bytes at: n from: x0) ifTrue: [^lastScroll := a].
		(self scroll: a negated fits: samples first: first in: r pixels: bytes at: n from: x0) ifTrue: [^lastScroll := a negated]].
	^nil
!
scroll: dy fits: samples first: first in: r pixels: bytes at: n from: x0
	"Whether every sample row y (at least 3) for which y + dy is in r is my copy's row y + dy (the row first tried first)."
	| h inRange |
	h := r height.
	(first + dy >= 0 and: [first + dy < h]) ifFalse: [^false].
	(self row: first of: r pixels: bytes at: n from: x0 matchesCopyRow: first + dy) ifFalse: [^false].
	inRange := 0.
	samples do: [:y |
		(y + dy >= 0 and: [y + dy < h]) ifTrue: [
			inRange := inRange + 1.
			(self row: y of: r pixels: bytes at: n from: x0 matchesCopyRow: y + dy) ifFalse: [^false]]].
	^inRange >= 3
!
row: y of: r pixels: bytes at: n from: x0 matchesCopyRow: y2
	"Whether n bytes from x0 of r's new row y (0-based in r) are those of my copy's row y2 (0-based in r) there."
	^(bytes indexOfMismatchAt: y * r width * 4 + (x0 * 4) + 1 with: copy at: (r top + y2) * extent x * 4 + (r left + x0 * 4) + 1 size: n) = 0
! !

!RfbDiffSource methodsFor: 'private'!
noteExtent: anExtent
	"(Under my lock.) A new size: a new copy, all of it damage."
	(anExtent isNil or: [anExtent = extent]) ifTrue: [^self].
	extent := anExtent.
	copy := nil.
	valid := false.
	pending := nil
!
moveCopy: aRectangle to: aPoint
	| pixels w |
	w := aRectangle width.
	pixels := ByteArray new: aRectangle area * 4.
	0 to: aRectangle height - 1 do: [:y |
		pixels replaceFrom: y * w * 4 + 1 to: y + 1 * w * 4 with: copy startingAt: (aRectangle top + y) * extent x + aRectangle left * 4 + 1].
	0 to: aRectangle height - 1 do: [:y | | to |
		to := (aPoint y + y) * extent x + aPoint x * 4 + 1.
		copy replaceFrom: to to: to + (w * 4) - 1 with: pixels startingAt: y * w * 4 + 1]
! !

!RfbDiffSource methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an RfbDiffSource on '; nextPutAll: inner class name
! !

!RfbDiffSource class methodsFor: 'instance creation'!
on: anRfbFrameSource
	^self new setInner: anRfbFrameSource
! !
