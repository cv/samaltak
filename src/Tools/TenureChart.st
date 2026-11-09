Widget subclass: #TenureChart
	instanceVariableNames: 'runs seconds'
	classVariableNames: ''
	package: 'Tools'!

TenureChart comment: 'I draw the Tenure Test''s runs, one lane each, on the same axes (0 to 200 MB of old space, the seconds of a run): the run''s TENURE_AGE and what old space did above its plot, old space as a line, a dotted line at each full GC.'!

!TenureChart methodsFor: 'accessing'!
runs: aCollection seconds: aNumber
	runs := aCollection.
	seconds := aNumber.
	self invalidate
! !

!TenureChart methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| h |
	aCanvas fillRect: self localBounds color: self theme paper.
	h := self height // 2.
	1 to: 2 do: [:i |
		self drawLane: (i <= runs size ifTrue: [runs at: i] ifFalse: [nil]) on: aCanvas top: i - 1 * h height: h]
!
drawLane: aRunOrNil on: aCanvas top: top height: h
	"A header line above the plot; 40 points at the left for the MB axis."
	| theme plot |
	theme := self theme.
	aCanvas drawString: (aRunOrNil isNil ifTrue: ['not run yet'] ifFalse: ['TENURE_AGE ' , aRunOrNil age printString])
		at: 12 @ (top + 6) font: (theme font: #readout) color: theme ink.
	aRunOrNil isNil ifFalse: [
		aCanvas drawString: aRunOrNil summary at: 12 @ (top + 32) font: (theme font: #small) color: theme ink].
	plot := 60 @ (top + 68) corner: (self width - 16) @ (top + h - 24).
	self drawAxesIn: plot on: aCanvas.
	aRunOrNil isNil ifFalse: [self drawRun: aRunOrNil in: plot on: aCanvas]
!
drawAxesIn: plot on: aCanvas
	| theme small |
	theme := self theme.
	small := theme font: #small.
	0 to: 200 by: 50 do: [:mb | | y |
		y := self yOf: mb in: plot.
		aCanvas line: plot left @ y to: plot right @ y color: (theme ink alpha: 0.15) width: 1.
		aCanvas drawString: (mb = 200 ifTrue: ['200 MB'] ifFalse: [mb printString]) at: 12 @ (y - 8) font: small color: theme muted].
	aCanvas drawString: '0 s' at: plot left @ (plot bottom + 3) font: small color: theme muted.
	aCanvas drawString: seconds rounded printString , ' s' at: (plot right - 20) @ (plot bottom + 3) font: small color: theme muted
!
drawRun: aRun in: plot on: aCanvas
	| theme previous points |
	theme := self theme.
	points := aRun points.
	aRun fullGCs do: [:i | | x |
		x := self xOf: (points at: i) x in: plot.
		plot top to: plot bottom by: 6 do: [:y |
			aCanvas line: x @ y to: x @ (y + 2) color: theme ink width: 1]].
	points do: [:p | | q |
		q := (self xOf: p x in: plot) @ (self yOf: p y in: plot).
		previous isNil ifFalse: [aCanvas line: previous to: q color: theme ultramarine width: 2].
		previous := q]
!
yOf: megabytes in: plot
	^plot bottom - ((megabytes min: 200) / 200.0 * plot height)
!
xOf: secs in: plot
	^plot left + ((secs min: seconds) / seconds * plot width)
! !
