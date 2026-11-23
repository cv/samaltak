Widget subclass: #LoadMeters
	instanceVariableNames: 'meters'
	classVariableNames: ''
	package: 'Tools'!

LoadMeters comment: 'I am a row of load meters, one per CPU core or device the Process Browser watches: each a label, a framed track filled to its load and the load in percent of what it can do (a core''s 100% is all of its time). meters: takes an Array of label -> percent Associations; a percent of nil draws an empty track and a dash (not measured). New readings draw me again only when they look different: another label, text or fill (whole points).

	LoadMeters new meters: {''cpu0'' -> 42.0. ''cpu1'' -> 3.5. ''gpu'' -> nil}'!

!LoadMeters methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| theme ink faint font b w |
	self meters isEmpty ifTrue: [^self].
	theme := self theme.
	ink := theme color: #ink.
	faint := theme color: #ink3.
	font := theme font: #mono11.
	b := self innerBounds.
	w := b width / self meters size.
	self meters doWithIndex: [:each :i |
		| x pct track |
		x := b left + ((i - 1) * w).
		pct := each value.
		aCanvas drawString: each key in: (x @ b top extent: 32 @ b height) font: font color: faint align: #left.
		track := (x + 32) @ (b top + (b height - 5 // 2)) extent: (w - 32 - 52 max: 8) @ 5.
		aCanvas strokeRect: track color: ink width: 1.
		pct isNil ifFalse: [aCanvas fillRect: (track origin extent: (self fillOf: pct track: track width) @ track height) color: ink].
		aCanvas drawString: (self textOf: pct)
			in: ((track right + 2) @ b top corner: (x + w - 10) @ b bottom) font: font color: ink align: #right]
! !

!LoadMeters methodsFor: 'drawing'!
fillOf: pct track: width
	"The filled width of a track for pct, in whole points: a reading that moves less draws the same."
	^(width * ((pct max: 0) min: 100) / 100) rounded
!
textOf: pct
	^pct isNil ifTrue: ['-'] ifFalse: [(pct printShowingDecimalPlaces: 1), '%']
!
looksOf: anArray
	"What anArray of meters draws: each label, text and fill."
	| width |
	anArray isEmpty ifTrue: [^#()].
	width := self innerBounds width / anArray size - 32 - 52 max: 8.
	^anArray collect: [:each |
		Array with: each key with: (self textOf: each value) with: (each value isNil ifFalse: [self fillOf: each value track: width])]
! !

!LoadMeters methodsFor: 'accessing'!
meters
	^meters ifNil: [#()]
!
meters: anArray
	"Keep the readings; draw again only when they look different."
	| old |
	meters = anArray ifTrue: [^self].
	old := self meters.
	meters := anArray.
	(self looksOf: old) = (self looksOf: self meters) ifFalse: [self invalidate]
! !

!LoadMeters methodsFor: 'remote control'!
remoteRole
	^#meter
!
remoteState
	^self meters asArray collect: [:each | each key, '=', (each value isNil ifTrue: ['-'] ifFalse: [each value printShowingDecimalPlaces: 1])]
! !
