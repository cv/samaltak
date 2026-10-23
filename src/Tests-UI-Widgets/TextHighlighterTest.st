TestCase subclass: #TextHighlighterTest
	instanceVariableNames: 'buffer highlighter'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

TextHighlighterTest comment: 'I test TextHighlighter headlessly: the Scanner tokens, their incremental update after buffer edits, the styled runs (merged neighbours, forced color), method mode and switching highlighting off.'!

!TextHighlighterTest methodsFor: 'running'!
setUp
	buffer := TextBuffer string: '^self foo: #bar'.
	highlighter := TextHighlighter on: buffer
!
runsFrom: rs to: re color: aColor
	| runs |
	runs := OrderedCollection new.
	highlighter ensureTokens.
	highlighter styledRunsFrom: rs to: re color: aColor do: [:a :b :font :color |
		runs add: (Array with: a with: b with: font with: color)].
	^runs asArray
!
style: aType
	^Theme current syntaxStyleFor: aType
! !

!TextHighlighterTest methodsFor: 'tests'!
testTokens
	self assert: highlighter tokens asArray equals: #(#(#return 1 1) #(#self 2 5) #(#keyword 7 10) #(#symbol 12 15)).
	self assert: (highlighter tokenTypeAt: 3) equals: #self.
	self assert: (highlighter tokenTypeAt: 6) isNil
!
testFollowsBufferEdits
	| fresh |
	highlighter ensureTokens.
	(Array
		with: (Array with: 0 with: 1 with: '"')
		with: (Array with: 6 with: 6 with: '"')
		with: (Array with: 0 with: 0 with: '#(a ')
		with: (Array with: 10 with: 12 with: ')')
		with: (Array with: 0 with: 0 with: '''')) do: [:e |
			buffer replaceFrom: ((e at: 1) min: buffer size) to: ((e at: 2) min: buffer size) with: (e at: 3).
			fresh := TextHighlighter on: (TextBuffer string: buffer string).
			self assert: highlighter tokens asArray equals: fresh tokens asArray].
	buffer string: 'x'.
	self assert: highlighter tokens asArray equals: #(#(#identifier 1 1))
!
testRunsMergeNeighboursOfTheSameStyle
	| runs |
	buffer string: 'a b. c'.
	runs := self runsFrom: 0 to: buffer size color: nil.
	self assert: (runs collect: [:r | (r first: 2)]) equals: #(#(0 6)).
	self assert: (runs first at: 3) equals: ((self style: #identifier) at: 1).
	buffer string: '^self foo: #bar'.
	runs := self runsFrom: 0 to: buffer size color: nil.
	self assert: (runs collect: [:r | r first: 2]) equals: #(#(0 1) #(1 5) #(6 10) #(11 15)).
	self assert: (runs last at: 4) equals: ((self style: #symbol) at: 2)
!
testRunsAreClippedToTheRange
	| runs |
	runs := self runsFrom: 3 to: 8 color: nil.
	self assert: (runs collect: [:r | r first: 2]) equals: #(#(3 5) #(6 8))
!
testForcedColorMergesByFont
	| runs |
	buffer string: 'foo bar: 3'.
	runs := self runsFrom: 0 to: buffer size color: Color white.
	self assert: (runs allSatisfy: [:r | (r at: 4) = Color white]).
	self assert: runs size equals: 3
!
testMethodModeStylesTheFirstLine
	buffer string: 'foo: x', (String with: Character lf), '^x'.
	highlighter methodMode: true.
	self assert: (highlighter styleFor: #keyword at: 2) equals: (self style: #pattern).
	self assert: (highlighter styleFor: #comment at: 2) equals: (self style: #comment).
	self assert: (highlighter styleFor: #identifier at: 9) equals: (self style: #identifier)
!
testDisabled
	highlighter enabled: false.
	highlighter ensureTokens.
	self deny: highlighter isActive.
	self assert: highlighter tokens isEmpty.
	highlighter enabled: true.
	highlighter ensureTokens.
	self assert: highlighter isActive
! !
