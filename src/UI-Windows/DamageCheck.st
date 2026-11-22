Object subclass: #DamageCheck
	instanceVariableNames: 'frames frameMismatches layers layerMismatches log dumpDirectory staleReadbacks presents presentMismatches'
	classVariableNames: 'Current ForcesFull'
	package: 'UI-Windows'!

DamageCheck comment: 'I check damage-limited composition (docs/graphics-damage.md): while I run (DamageCheck start), after every frame the compositor drew only in part, it renders the frame''s composite list whole into a scratch surface and compares its pixels with the screen surface it kept and drew the damage into; likewise every layer rendered in part with its lists rendered whole. Damage that missed a change, or drawing in pieces that differs from drawing whole, shows as a mismatch (log: what and where). Slow (readbacks): for tests and debugging only.

DamageCheck forcesFull: true has every frame and layer drawn whole (the composition before damage), to tell a damage bug from another.

	DamageCheck start.
	"... interact ..."
	DamageCheck stop report'!

!DamageCheck methodsFor: 'initialization'!
initialize
	frames := frameMismatches := layers := layerMismatches := staleReadbacks := presents := presentMismatches := 0.
	log := OrderedCollection new
! !

!DamageCheck methodsFor: 'accessing'!
frames
	"Frames checked."
	^frames
!
frameMismatches
	^frameMismatches
!
layers
	"Layer renders checked."
	^layers
!
layerMismatches
	^layerMismatches
!
mismatches
	^frameMismatches + layerMismatches + presentMismatches
!
presents
	"Presents of damaged rectangles checked (the firmware's screen, an uploaded frame)."
	^presents
!
presentMismatches
	^presentMismatches
!
staleReadbacks
	"Differences that a second readback did not confirm."
	^staleReadbacks
!
log
	^log
!
dumpTo: aDirectoryPathOrNil
	"Write the first mismatches' pixels there, drawn in part and drawn whole (damage-<n>-part.png, -whole.png)."
	dumpDirectory := aDirectoryPathOrNil
!
report
	^'damage check: ', frames printString, ' frames (', frameMismatches printString, ' mismatched), ',
		layers printString, ' layer renders (', layerMismatches printString, ' mismatched), ',
		presents printString, ' presents (', presentMismatches printString, ' mismatched)',
		(log isEmpty ifTrue: [''] ifFalse: ['; first: ', log first])
! !

!DamageCheck methodsFor: 'checking'!
checkFrame: aDisplayList previous: olderList surface: aSurface clear: aColor renderer: aRenderer damage: aDamageRegion
	"The compositor kept aSurface and drew aDisplayList into it where aDamageRegion says: compare with drawing it whole."
	| whole difference |
	frames := frames + 1.
	whole := Surface width: aSurface width height: aSurface height scale: aSurface scale.
	[aRenderer render: aDisplayList on: whole clear: aColor.
	 difference := self differenceOf: aSurface and: whole extent: aSurface pixelExtent.
	 (difference notNil and: [dumpDirectory notNil and: [frameMismatches < 5]]) ifTrue: [
		PNGWriter write: aSurface to: dumpDirectory, '/damage-', frames printString, '-part.png'.
		PNGWriter write: whole to: dumpDirectory, '/damage-', frames printString, '-whole.png']]
		ensure: [whole release].
	difference isNil ifTrue: [^self].
	frameMismatches := frameMismatches + 1.
	self note: 'frame ', frames printString, ': ', difference, ' (damage ', aDamageRegion printString, ')'
!
checkLayer: aLayer named: aString renderer: aRenderer
	"aLayer was rendered in part (lastDamage): compare with rendering its lists whole."
	| surface whole difference |
	layers := layers + 1.
	surface := aLayer surface.
	whole := Surface width: surface width height: surface height scale: surface scale.
	[aRenderer render: aLayer renderedContent on: whole clear: (aLayer clearColorOrPaper).
	 aLayer renderedChrome isNil ifFalse: [aRenderer render: aLayer renderedChrome on: whole clear: nil].
	 difference := self differenceOf: surface and: whole extent: aLayer pixelExtent.
	 (difference notNil and: [dumpDirectory notNil and: [layerMismatches < 5]]) ifTrue: [
		PNGWriter write: surface to: dumpDirectory, '/layer-', layers printString, '-part.png'.
		PNGWriter write: whole to: dumpDirectory, '/layer-', layers printString, '-whole.png']]
		ensure: [whole release].
	difference isNil ifTrue: [^self].
	layerMismatches := layerMismatches + 1.
	self note: 'layer of ', aString, ': ', difference, ' (damage ', aLayer lastDamage printString, ')'
!
notePresent: aString same: aBoolean
	"A present of damaged rectangles (HostFramePresenter, FirmwareScreen) compared what it shows with the whole frame."
	presents := presents + 1.
	aBoolean ifTrue: [^self].
	presentMismatches := presentMismatches + 1.
	self note: aString, ' after present ', presents printString, ' differs from the frame'
!
differenceOf: aSurface and: wholeSurface extent: aPoint
	"nil if aPoint pixels at the top left of both surfaces are equal, else where they differ. A difference is read back once more before it counts: the first download of a texture can show what it held before the frame (the GB10's Vulkan driver under Xvfb), and staleReadbacks counts those."
	| whole difference |
	whole := wholeSurface readbackBytes.
	difference := self differenceOf: aSurface readbackBytes width: aSurface width and: whole width: wholeSurface width extent: aPoint.
	difference isNil ifTrue: [^nil].
	difference := self differenceOf: aSurface readbackBytes width: aSurface width and: wholeSurface readbackBytes width: wholeSurface width extent: aPoint.
	difference isNil ifTrue: [staleReadbacks := staleReadbacks + 1].
	^difference
!
differenceOf: aBytes width: aWidth and: bBytes width: bWidth extent: aPoint
	"nil if the RGBA pixels of aPoint at the top left of both are equal, else where they differ: the rows, the columns and how many pixels."
	| rowA rowB n top bottom left right count first |
	n := aPoint x * 4.
	rowA := ByteArray new: n.
	rowB := ByteArray new: n.
	count := 0.
	0 to: aPoint y - 1 do: [:y |
		rowA replaceFrom: 1 to: n with: aBytes startingAt: y * aWidth * 4 + 1.
		rowB replaceFrom: 1 to: n with: bBytes startingAt: y * bWidth * 4 + 1.
		(rowA compareBytes: rowB) = 0 ifFalse: [
			top isNil ifTrue: [top := y].
			bottom := y.
			0 to: aPoint x - 1 do: [:x |
				(rowA uint32At: x * 4 + 1) = (rowB uint32At: x * 4 + 1) ifFalse: [
					first isNil ifTrue: [first := (x @ y) printString, ' is ', ((rowA uint32At: x * 4 + 1) printStringRadix: 16), ' not ', ((rowB uint32At: x * 4 + 1) printStringRadix: 16)].
					count := count + 1.
					left := left isNil ifTrue: [x] ifFalse: [left min: x].
					right := right isNil ifTrue: [x] ifFalse: [right max: x]]]]].
	top isNil ifTrue: [^nil].
	^count printString, ' pixels differ in ', (left @ top corner: (right + 1) @ (bottom + 1)) printString, ', first ', first
!
note: aString
	log size < 50 ifTrue: [log add: aString].
	Transcript show: 'DamageCheck: ', aString; cr
! !

!DamageCheck class methodsFor: 'checking'!
current
	"The running check, or nil (the default)."
	^Current
!
start
	^Current := self new
!
stop
	"Stop checking; answer the check."
	| c |
	c := Current.
	Current := nil.
	^c
! !

!DamageCheck class methodsFor: 'switches'!
forcesFull
	"Whether every frame and layer is drawn whole (damage ignored)."
	^ForcesFull == true
!
forcesFull: aBoolean
	ForcesFull := aBoolean
! !
