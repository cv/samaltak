RfbFrameSource subclass: #RfbDiffSource
	instanceVariableNames: 'inner extent copy valid pending copyLock refreshes comparedArea changedArea diffMs'
	classVariableNames: ''
	package: 'System-Remote'!

RfbDiffSource comment: 'I am a frame source that takes unchanged pixels out of another''s damage, as QEMU''s VNC server does: I keep one copy of the screen as it was last compared (BGRA8, shared by all my listeners whatever their pixel format: 8 MB at 1920x1080, made when the first listener comes and dropped when the last goes), and when a listener''s writer collects its damage (collectFor:) I read what my source damaged since (once, for all of them), compare it with my copy in 16x16 blocks (ByteArray>>indexOfMismatchAt:with:at:size:, 16 bytes at a time, skipping blocks of a band already known to differ), copy it in, and give every listener the blocks that changed, joined into runs (takeDamage:full:extent:; RfbDamage merges them further: a rectangle''s header against the unchanged pixels between). Re-laid-out text damages a whole paragraph of which few pixels change; a list redrawn the same changes none.

Pixels sent (bgraOf:, bgraOfAll:) come from my copy, so each listener''s client has my copy less the damage it has yet to take: correct for any number of listeners, a slow one''s damage merging meanwhile, and a pixel that changes after it was compared is in my source''s next damage. A move (moved:to:) moves my copy''s pixels too, and where my source''s damage not yet compared touched its origin, its destination is compared again. A new size (resized:, or the extent a polled source hands me) makes my copy anew, all of it damage. Push sources (RfbBufferSource) tell me at once, and I only note the damage and wake my listeners; polled ones (RfbTapSource) signal me as a listener''s semaphore (signal wakes all of mine) and hand me their damage in collectFor:.

statistics: how often I compared (or made my copy whole), the area compared and the area found changed in it (pixels), and the time it took (ms).'!

!RfbDiffSource methodsFor: 'initialization'!
setInner: anRfbFrameSource
	inner := anRfbFrameSource.
	valid := false.
	copyLock := Semaphore forMutualExclusion.
	refreshes := 0.
	comparedArea := 0.
	changedArea := 0.
	diffMs := 0
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
	"My source moved aRectangle's pixels to aPoint: so do I, and so may my listeners (CopyRect); where its damage I have yet to compare touches aRectangle, compare the destination again."
	| dest bounds |
	dest := aPoint extent: aRectangle extent.
	copyLock critical: [
		bounds := 0 @ 0 extent: (extent ifNil: [0 @ 0]).
		(valid and: [(bounds containsRect: aRectangle) and: [bounds containsRect: dest]])
			ifTrue: [
				self moveCopy: aRectangle to: aPoint.
				(pending notNil and: [pending intersects: aRectangle]) ifTrue: [pending add: dest].
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
				changed := OrderedCollection new.
				rects with: buffers do: [:r :b |
					comparedArea := comparedArea + r area.
					b size = (r area * 4) ifTrue: [self compare: r with: b into: changed]].
				changed isEmpty ifTrue: [
					refreshes := refreshes + 1.
					diffMs := diffMs + (Time millisecondClockValue - start).
					^false]].
		refreshes := refreshes + 1.
		changedArea := changedArea + (changed inject: 0 into: [:sum :r | sum + r area]).
		self listeners do: [:each | each takeDamage: changed full: full extent: e].
		diffMs := diffMs + (Time millisecondClockValue - start).
		true]
!
compare: r with: bytes into: changed
	"Compare r's pixels (bytes: its BGRA8 rows) with my copy, copy them in, and add the 16x16 blocks (clipped to r) that differ to changed: runs of blocks in a band of 16 rows, joined with the run of the same columns in the band above."
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
			open := self band: bandTop to: y marks: marks first: firstBlock left: left right: right open: open into: changed.
			marks atAllPut: 0.
			bandTop := y]].
	changed addAll: open
!
band: top to: bottom marks: marks first: firstBlock left: left right: right open: open into: changed
	"The runs of marked blocks of a band as rectangles: each one that continues a run of open (the band above, same columns) grows it; the open runs it does not continue are done (into changed). Answer the band's runs."
	| bs runs k |
	bs := self blockSize.
	runs := OrderedCollection new.
	k := 1.
	[k <= marks size] whileTrue: [
		(marks at: k) = 0
			ifTrue: [k := k + 1]
			ifFalse: [| j x0 x1 above |
				j := k.
				[j < marks size and: [(marks at: j + 1) ~= 0]] whileTrue: [j := j + 1].
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
