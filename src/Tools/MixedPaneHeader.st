PaneHeader subclass: #MixedPaneHeader
	instanceVariableNames: 'tail cache'
	classVariableNames: ''
	package: 'Tools'!

MixedPaneHeader comment: 'I am a PaneHeader whose tracked-capitals title is followed by a tail in italic lower case (the Inspector''s "EVALUATE self = 3@4"). tail: takes a String or a block.'!

!MixedPaneHeader methodsFor: 'accessing'!
tail
	^tail isBlock ifTrue: [tail value asString] ifFalse: [tail ifNil: ['']]
!
tail: aStringOrBlock
	tail := aStringOrBlock.
	self invalidate
!
remoteLabel
	^self title, ' ', self tail
! !

!MixedPaneHeader methodsFor: 'drawing'!
truncate: aString to: width font: aFont
	"aString, cut with an ellipsis to fit width points (binary search; cached, since building a WideString is slow)."
	| ellipsis ew lo hi mid result |
	(cache notNil and: [cache first = aString and: [(cache at: 2) = width]]) ifTrue: [^cache last].
	(aFont widthOf: aString) <= width
		ifTrue: [result := aString]
		ifFalse: [
			ellipsis := Character value: 8230.
			ew := aFont advanceOf: ellipsis.
			lo := 0.
			hi := aString size.
			[lo < hi] whileTrue: [
				mid := lo + hi + 1 // 2.
				(aFont widthOf: aString from: 1 to: (aString graphemeClusterStartBefore: mid + 1)) + ew <= width ifTrue: [lo := mid] ifFalse: [hi := mid - 1]].
			lo := aString graphemeClusterStartBefore: lo + 1.
			result := WideString new: lo + 1.
			1 to: lo do: [:i | result at: i put: (aString at: i)].
			result at: lo + 1 put: ellipsis].
	cache := Array with: aString with: width with: result.
	^result
!
drawSelfOn: aCanvas
	| pad tw right rw limit |
	super drawSelfOn: aCanvas.
	pad := self theme metric: #paneHeaderPaddingX.
	tw := (self theme font: #header) widthOf: self title.
	right := self rightText.
	rw := right isEmpty ifTrue: [0] ifFalse: [((self theme font: #smallItalic) widthOf: right) + 10].
	limit := self width - pad - rw.
	aCanvas drawString: (self truncate: self tail to: (limit - pad - tw - 6 max: 0) font: (self theme font: #smallItalic))
		in: ((pad + tw + 6) @ 0 corner: limit @ (self height - 1))
		font: (self theme font: #smallItalic) color: (self theme color: #ink2) align: #left
! !
