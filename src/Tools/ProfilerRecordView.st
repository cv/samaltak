Widget subclass: #ProfilerRecordView
	instanceVariableNames: 'heading rows'
	classVariableNames: ''
	package: 'Tools'!

ProfilerRecordView comment: 'I show the Frames tab''s text below the timeline: an italic heading and key/value rows (keys in tracked capitals). Texts are runs, Arrays of {String. style} with style #plain #bold #italic or #drop (inverted). The Profiler window fills me with the selected FrameRecord or the summary of the range.'!

!ProfilerRecordView methodsFor: 'accessing'!
heading: runs
	heading := runs.
	self invalidate
!
rows: anArray
	"anArray of {key. runs}."
	rows := anArray.
	self invalidate
!
plainText
	^String new: 200 streamContents: [:s |
		s nextPutAll: (self textOf: heading); nextPut: Character lf.
		(rows ifNil: [#()]) do: [:r | s nextPutAll: r first; nextPutAll: ': '; nextPutAll: (self textOf: r last); nextPut: Character lf]]
!
textOf: runs
	^String new: 80 streamContents: [:s | (runs ifNil: [#()]) do: [:run | s nextPutAll: run first]]
! !

!ProfilerRecordView methodsFor: 'drawing'!
fontFor: aStyle base: aSymbol
	aStyle == #bold ifTrue: [^self theme font: #uiBold].
	aStyle == #drop ifTrue: [^self theme font: #uiBold].
	aStyle == #italic ifTrue: [^self theme font: #uiItalic].
	^self theme font: aSymbol
!
drawRuns: runs at: aPoint base: aSymbol limit: right on: aCanvas
	| x |
	x := aPoint x.
	(runs ifNil: [#()]) do: [:run | | f w |
		f := self fontFor: run last base: aSymbol.
		w := f widthOf: run first.
		x < right ifTrue: [
			run last == #drop
				ifTrue: [
					aCanvas fillRect: (x @ (aPoint y + 1) extent: (w + 8) @ (f lineHeight - 2)) color: self theme ink.
					aCanvas drawString: run first at: (x + 4) @ aPoint y font: f color: self theme paper.
					x := x + 8]
				ifFalse: [aCanvas drawString: run first at: x @ aPoint y font: f color: self theme ink]].
		x := x + w]
!
drawSelfOn: aCanvas
	| y keyFont right |
	aCanvas fillRect: self localBounds color: self theme paper.
	aCanvas fillRect: (0 @ 0 corner: self width @ 1) color: self theme rule.
	right := self width - 8.
	y := 6.
	aCanvas clip: (0 @ 0 corner: right @ self height) during: [
		self drawRuns: heading at: 12 @ y base: #uiItalic limit: right on: aCanvas.
		y := y + 20.
		keyFont := self theme font: #header.
		(rows ifNil: [#()]) do: [:r |
			aCanvas drawString: r first in: (12 @ y corner: 104 @ (y + 18)) font: keyFont color: self theme ink align: #left.
			self drawRuns: r last at: 106 @ y base: #ui limit: right on: aCanvas.
			y := y + 18]]
! !

!ProfilerRecordView methodsFor: 'remote control'!
remoteRole
	^#record
!
remoteLabel
	^self textOf: heading
!
remoteText
	^self plainText
!
remoteChildren
	^(rows ifNil: [#()]) collect: [:r |
		(WidgetPart of: self role: #field label: r first, ': ', (self textOf: r last)) name: r first; yourself]
! !
