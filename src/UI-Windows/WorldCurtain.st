Object subclass: #WorldCurtain
	instanceVariableNames: 'world kind started'
	classVariableNames: ''
	package: 'UI-Windows'!

WorldCurtain comment: 'I cover the screen while the image comes and goes; the Compositor draws me over everything. After a restart from a snapshot (starting:) I am a splash, the image''s name and the windows composited so far, until every window is composited again, and at least minimumMilliseconds (a restart is often quicker than the eye: without it the splash would not be seen). Before the VM goes away (leaving:, a quit or the exec of a rebuilt VM) I fade the screen to black in fadeMilliseconds.'!

!WorldCurtain methodsFor: 'initialization'!
setWorld: aWorld kind: aSymbol
	world := aWorld.
	kind := aSymbol.
	started := Time millisecondClockValue
! !

!WorldCurtain methodsFor: 'accessing'!
elapsed
	^Time millisecondClockValue - started
!
isLeaving
	^kind == #leaving
!
isBlack
	^self isLeaving and: [self elapsed >= self class fadeMilliseconds]
!
isDone
	"A splash is done once every window is composited again (at most 5 s); a fade never is: the VM goes away."
	self isLeaving ifTrue: [^false].
	self elapsed < self class minimumMilliseconds ifTrue: [^false].
	^self composited = world windows size or: [self elapsed > 5000]
!
composited
	^(world windows count: [:w | w layer isRendered])
! !

!WorldCurtain methodsFor: 'drawing'!
drawOn: aCanvas
	| box bar done |
	self isLeaving ifTrue: [
		^aCanvas alpha: (self elapsed / self class fadeMilliseconds min: 1) during: [
			aCanvas fillRect: world bounds color: Color black]].
	world drawDeskOn: aCanvas.
	box := (world extent - (360 @ 118) / 2) rounded extent: 360 @ 118.
	aCanvas fillRect: (box translateBy: 4 @ 4) color: Color shadow.
	aCanvas fillRect: box color: Color paper.
	aCanvas strokeRect: box color: Color ink width: 1.
	aCanvas drawString: 'Samaltak' at: box origin + (20 @ 16) font: Font uiBold color: Color ink.
	aCanvas drawString: 'restarting ', world imageName at: box origin + (20 @ 40) font: Font ui color: Color ink.
	done := self composited.
	bar := box origin + (20 @ 72) extent: box width - 40 @ 12.
	aCanvas clip: bar during: [
		aCanvas translateBy: (self elapsed / 40) rounded \\ 8 @ 0 during: [
			aCanvas pattern: #diagonalStripes in: (bar origin - (8 @ 0) extent: bar width + 8 @ bar height) color: Color ultramarine]].
	world windows isEmpty ifFalse: [
		aCanvas fillRect: (bar origin extent: (bar width * done / world windows size) rounded @ bar height) color: Color ultramarine].
	aCanvas strokeRect: bar color: Color ink width: 1.
	aCanvas drawString: done printString, ' of ', world windows size printString, ' windows' at: bar bottomLeft + (0 @ 6) font: Font small color: Color ink
! !

!WorldCurtain class methodsFor: 'instance creation'!
starting: aWorld
	^self new setWorld: aWorld kind: #starting
!
leaving: aWorld
	^self new setWorld: aWorld kind: #leaving
! !

!WorldCurtain class methodsFor: 'settings'!
minimumMilliseconds
	"The splash shows at least this long: a restart is often too quick to see it."
	^600
!
fadeMilliseconds
	^400
! !
