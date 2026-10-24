Widget subclass: #SystemMonitorAxis
	instanceVariableNames: 'monitor'
	classVariableNames: ''
	package: 'Tools'!

SystemMonitorAxis comment: 'I am the time axis under the System Monitor''s charts: ticks at fixed ages (every 10 s of a minute, every minute of five), now at the right. The charts scroll; I do not.'!

!SystemMonitorAxis methodsFor: 'accessing'!
monitor: aSystemMonitor
	monitor := aSystemMonitor
! !

!SystemMonitorAxis methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| left right span step font muted age |
	aCanvas fillRect: self localBounds color: self theme paper.
	monitor isNil ifTrue: [^self].
	left := 52.
	right := self width - 10.
	span := monitor span // 1000000.
	step := span > 120 ifTrue: [60] ifFalse: [10].
	font := self theme font: #smallItalic.
	muted := self theme muted.
	age := 0.
	[age <= span] whileTrue: [ | x label |
		x := right - (age / span * (right - left)).
		aCanvas fillRect: (x rounded - 1 @ 0 extent: 1 @ 3) color: self theme ink.
		label := age = 0
			ifTrue: ['now']
			ifFalse: [step = 60 ifTrue: ['−', (age // 60) printString, ' min'] ifFalse: ['−', age printString, ' s']].
		aCanvas drawString: label in: ((x - 30) @ 2 corner: (x + (age = 0 ifTrue: [8] ifFalse: [30])) @ self height)
			font: font color: muted align: (age = 0 ifTrue: [#right] ifFalse: [#center]).
		age := age + step]
! !

!SystemMonitorAxis methodsFor: 'remote control'!
remoteIsTransparent
	^true
! !
