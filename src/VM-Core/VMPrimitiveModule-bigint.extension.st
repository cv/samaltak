!VMPrimitiveModule methodsFor: 'integer magnitude kernel'!
compare: a count: na with: b count: nb
	"-1, 0 or 1: the magnitude a against b (no leading zero limbs)."
	| i |
	na ~= nb ifTrue: [^na < nb ifTrue: [-1] ifFalse: [1]].
	i := na - 1.
	[i >= 0 and: [(a at: i) = (b at: i)]] whileTrue: [i := i - 1].
	i < 0 ifTrue: [^0].
	^(a at: i) < (b at: i) ifTrue: [-1] ifFalse: [1]

! !
