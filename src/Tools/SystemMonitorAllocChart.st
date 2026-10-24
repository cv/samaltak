SystemMonitorChart subclass: #SystemMonitorAllocChart
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

SystemMonitorAllocChart comment: 'I am the System Monitor''s allocation chart: the bytes allocated per second, and below it the GC lane: a grey tick per scavenge, as high as its pause (20 ms fills the lane), a black bar per full GC.'!

!SystemMonitorAllocChart methodsFor: 'geometry'!
laneHeight
	^14
!
plotRows
	^form height - (self laneHeight * scale) rounded
! !

!SystemMonitorAllocChart methodsFor: 'painting'!
paintColumn: x index: k from: t0 to: t1
	| sum weight scavenges pause fulls h area row s0 ink hgt |
	sum := 0.
	weight := 0.
	scavenges := 0.
	pause := 0.
	fulls := 0.
	self data from: t0 to: t1 do: [:s :o |
		sum := sum + (s allocationRate * o).
		weight := weight + o.
		(s time >= t0 and: [s time < t1]) ifTrue: [
			scavenges := scavenges + s scavenges.
			fulls := fulls + s fullGCs.
			pause := pause + s gcMicros]].
	h := form height.
	area := self plotRows.
	s0 := scale rounded max: 1.
	ink := colors at: #ink.
	weight = 0
		ifTrue: [self paintBackground: x to: area index: k. tops at: x + 1 put: nil]
		ifFalse: [
			row := self rowOf: sum / weight / 1048576.0.
			self paintBackground: x to: row index: k.
			self fill: x from: row to: area pixel: (colors at: #area).
			self paintLine: x top: row pixel: (colors at: #line)].
	self fill: x from: area to: h pixel: (colors at: #paper).
	self fill: x from: area to: area + 1 pixel: (colors at: #hair).
	fulls > 0 ifTrue: [
		^#(0 1) do: [:dx | self fill: x - dx \\ form width from: area + s0 to: h pixel: ink]].
	scavenges > 0 ifTrue: [
		hgt := ((pause / 20000.0 min: 1.0) sqrt * (h - area - s0)) rounded max: 2 * s0.
		self fill: x from: h - hgt to: h pixel: (colors at: #scavenge)]
!
colors
	| d |
	d := super colors.
	d at: #area put: (self pixel: #ink4).
	d at: #line put: (self pixel: #ink2).
	d at: #scavenge put: (self pixel: #ink3).
	^d
!
scaleNeedOf: aSample
	^aSample allocationRate / 1048576.0
!
minimumScale
	^1
!
gridRows
	"One line, at half the scale: the strip is low."
	^Array with: (self rowOf: yMax / 2)
! !

!SystemMonitorAllocChart methodsFor: 'drawing'!
drawLabelsOn: aCanvas
	"The top of the scale only: the strip is low."
	| r |
	r := self plotRect.
	yMax >= 1000
		ifTrue: [
			self labelY: (ProfilerFormat oneDecimal: yMax / 1024.0) at: r top + 2 on: aCanvas.
			self labelY: 'GB/s' at: r top + 15 on: aCanvas]
		ifFalse: [
			self labelY: yMax printString at: r top + 2 on: aCanvas.
			self labelY: 'MB/s' at: r top + 15 on: aCanvas].
	self labelY: 'GC' at: r bottom - (self laneHeight / 2) on: aCanvas
! !

!SystemMonitorAllocChart methodsFor: 'hover'!
tipLinesFor: aSample
	^monitor heapTipLinesFor: aSample
! !

!SystemMonitorAllocChart methodsFor: 'remote control'!
remoteLabel
	^'Allocation (MB/s) and GCs'
!
remoteStateFor: aSample
	^Array
		with: 'rate=', (SystemMonitor rate: aSample allocationRate)
		with: 'gcs=', aSample gcCount printString
!
remoteValue: aNumber
	^SystemMonitor megabytes: aNumber
! !
