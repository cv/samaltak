Object subclass: #ProfilerFormat
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

ProfilerFormat comment: 'I format the Profiler window''s numbers: counts with thousands separators, percentages, µs as ms or s, bytes; and I cut labels to a width with an ellipsis.'!

!ProfilerFormat class methodsFor: 'numbers'!
count: anInteger
	^anInteger rounded asStringWithCommas
!
percent: part of: whole
	^self oneDecimal: (whole = 0 ifTrue: [0.0] ifFalse: [part * 100.0 / whole])
!
oneDecimal: aNumber
	"aNumber with one decimal, e.g. '16.7' (like printShowingDecimalPlaces: 1, without exact fractions: live views format many numbers per refresh)."
	| t |
	t := (aNumber abs * 10) rounded.
	^((aNumber < 0 and: [t > 0]) ifTrue: ['-'] ifFalse: ['']), (t // 10) printString, '.', (t \\ 10) printString
!
percentString: part of: whole
	^(self percent: part of: whole), '%'
!
ms: micros
	"Answer micros (µs) as milliseconds, e.g. '16.7 ms'."
	| v |
	v := micros / 1000.0.
	^(v >= 100 ifTrue: [v rounded printString] ifFalse: [self oneDecimal: v]), ' ms'
!
seconds: micros
	^(self oneDecimal: micros / 1000000.0), ' s'
!
span: micros
	"A duration: seconds from 1 s, else milliseconds."
	^micros >= 1000000 ifTrue: [self seconds: micros] ifFalse: [self ms: micros]
!
bytes: anInteger
	^Profiler printBytes: anInteger rounded
!
weight: anInteger unit: aSymbol
	"Samples or bytes, as the flame graphs label them."
	aSymbol == #bytes ifTrue: [^self bytes: anInteger].
	^(self count: anInteger), (anInteger = 1 ifTrue: [' sample'] ifFalse: [' samples'])
! !

!ProfilerFormat class methodsFor: 'text'!
dot
	"The separator of status texts."
	^' · '
!
ellipsis
	^'…'
!
fit: aString font: aFont width: points
	"Answer aString, cut with an ellipsis so it fits points (empty if not even the ellipsis fits)."
	| lo hi mid ell |
	(aFont widthOf: aString) <= points ifTrue: [^aString].
	ell := self ellipsis.
	(aFont widthOf: ell) > points ifTrue: [^''].
	lo := 0.
	hi := aString size.
	[lo < hi] whileTrue: [
		mid := lo + hi + 1 // 2.
		(aFont widthOf: (aString copyFrom: 1 to: mid), ell) <= points
			ifTrue: [lo := mid]
			ifFalse: [hi := mid - 1]].
	^(aString copyFrom: 1 to: lo), ell
!
fit: aString advance: charWidth width: points
	"Like fit:font:width: for a monospaced font whose characters are charWidth wide (no measuring)."
	| n |
	aString size * charWidth <= points ifTrue: [^aString].
	n := (points / charWidth) floor - 1.
	n < 1 ifTrue: [^''].
	^(aString copyFrom: 1 to: n), self ellipsis
! !
