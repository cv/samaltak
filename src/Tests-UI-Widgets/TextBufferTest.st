TestCase subclass: #TextBufferTest
	instanceVariableNames: 'changes'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

TextBufferTest comment: 'I test TextBuffer headlessly: line ends, the line index and position mapping, incremental line updates after edits, listener notification and word and bracket boundaries.'!

!TextBufferTest methodsFor: 'helpers'!
lf
	^String with: Character lf
!
tab
	^String with: Character tab
!
textReset
	changes add: #reset
!
textReplacedFrom: start to: stop with: aString
	changes add: (Array with: start with: stop with: aString)
! !

!TextBufferTest methodsFor: 'tests'!
testNormalizesLineEnds
	| b |
	b := TextBuffer string: 'a', (String with: Character cr with: Character lf), 'b', (String with: Character cr), 'c'.
	self assert: b string equals: 'a', self lf, 'b', self lf, 'c'.
	self assert: (TextBuffer string: nil) string equals: ''
!
testLineIndex
	| b |
	b := TextBuffer string: 'ab', self lf, 'cd', self lf, self tab, 'x', self tab.
	self assert: b lineStarts equals: #(0 3 6).
	self assert: b lineCount equals: 3.
	self assert: (b lineEndAt: 1) equals: 2.
	self assert: (b lineEndAt: 3) equals: 9.
	self assert: (b lineAt: 2) equals: 'cd'.
	self assert: b lines asArray equals: (Array with: 'ab' with: 'cd' with: self tab, 'x', self tab).
	self assert: (b tabCountOfLine: 1) equals: 0.
	self assert: (b tabCountOfLine: 3) equals: 2.
	self assert: (b lineHasTab: 3).
	self assert: (b isPlainLine: 1).
	self deny: (b isPlainLine: 3).
	b := TextBuffer string: 'x', self lf, 'é', self tab, '日', self lf, (String with: (Character value: 127)).
	self assert: b lineOthers asArray equals: #(0 2 1).
	self assert: b lineTabs asArray equals: #(0 1 0).
	self deny: (b isPlainLine: 2)
!
testPositionToLine
	| b |
	b := TextBuffer string: 'ab', self lf, 'cd'.
	self assert: (b lineIndexOf: 0) equals: 1.
	self assert: (b lineIndexOf: 2) equals: 1.
	self assert: (b lineIndexOf: 3) equals: 2.
	self assert: (b lineIndexOf: 5) equals: 2.
	self assert: (b lineRangeAt: 4) equals: #(3 5).
	self assert: (TextBuffer indexIn: #(0 4 9) atOrBefore: 8) equals: 2
!
testEditsUpdateLinesIncrementally
	| b fresh |
	b := TextBuffer string: 'one', self lf, self tab, 'two', self lf, 'three'.
	b lineStarts.
	(Array
		with: (Array with: 3 with: 3 with: self lf, 'new', self tab)
		with: (Array with: 0 with: 5 with: '')
		with: (Array with: 2 with: 9 with: self tab, self lf, self lf)
		with: (Array with: 1 with: 1 with: 'é日', self lf, (String with: (Character value: 127)))
		with: (Array with: b size - 12 with: b size - 12 with: 'end')) do: [:e |
			b replaceFrom: ((e at: 1) min: b size) to: ((e at: 2) min: b size) with: (e at: 3).
			fresh := TextBuffer string: b string.
			self assert: b lineStarts equals: fresh lineStarts.
			self assert: b lineTabs equals: fresh lineTabs.
			self assert: b lineOthers equals: fresh lineOthers]
!
testReplaceAndListeners
	| b |
	changes := OrderedCollection new.
	b := TextBuffer string: 'hello world'.
	b addListener: self.
	b replaceFrom: 5 to: 11 with: ', you'.
	self assert: b string equals: 'hello, you'.
	self assert: changes asArray equals: (Array with: #(5 11 ', you')).
	b string: 'x'.
	self assert: changes last equals: #reset.
	b removeListener: self.
	b replaceFrom: 0 to: 1 with: 'y'.
	self assert: changes size equals: 2
!
testWideInsert
	| b |
	b := TextBuffer string: 'ab'.
	b replaceFrom: 1 to: 1 with: (String with: (Character value: 8230)).
	self assert: b size equals: 3.
	self assert: (b at: 2) value equals: 8230
!
testWordBoundaries
	| b |
	b := TextBuffer string: 'foo at: bar_2 x := (3 + [4]) ''s'''.
	self assert: (b wordRangeAt: 1) equals: #(0 3).
	self assert: (b wordRangeAt: 5) equals: #(4 7).
	self assert: (b wordRangeAt: 10) equals: #(8 13).
	self assert: (b wordRangeAt: 15) equals: #(14 15).
	self assert: (b wordRangeAt: 20) equals: #(20 27).
	self assert: (b wordRangeAt: 25) equals: #(25 26).
	self assert: (b wordRangeAt: 30) equals: #(30 31).
	self assert: (b wordStartBefore: 7) equals: 4.
	self assert: (b wordEndAfter: 3) equals: 6.
	self assert: ((TextBuffer string: 'y:=1') wordRangeAt: 1) equals: #(0 1)
!
testUnicodeWordBoundaries
	"Words are letters, digits and combining marks of any script; CJK punctuation, emoji and non-ASCII spaces separate them."
	| b |
	b := TextBuffer string: 'größe、日本語😀λ' , (String with: (Character value: 12288)) , 'e' , (String with: (Character value: 769)) , 'x'.
	self assert: (b wordRangeAt: 1) equals: #(0 5).
	self assert: (b wordRangeAt: 7) equals: #(6 9).
	self assert: (b wordEndAfter: 0) equals: 5.
	self assert: (b wordEndAfter: 5) equals: 9.
	self assert: (b wordEndAfter: 9) equals: 11.
	self assert: (b wordRangeAt: 13) equals: #(12 15).
	self assert: (b wordStartBefore: 15) equals: 12.
	self assert: (b wordStartBefore: 12) equals: 10
!
testWordsAreRunsOfClustersOfOneKind
	"CJK and Latin letters make separate words; NBSP, 、 and emoji separate words; a word never ends inside a cluster (❤ + VS16: the selector is a mark)."
	| heart b |
	heart := String with: (Character value: 16r2764) with: (Character value: 16rFE0F).
	b := TextBuffer string: '日本語abc、x', (String with: (Character value: 160)), 'y', heart, 'z'.
	self assert: (b wordRangeAt: 1) equals: #(0 3).
	self assert: (b wordRangeAt: 3) equals: #(3 6).
	self assert: (b wordRangeAt: 4) equals: #(3 6).
	self assert: (b wordEndAfter: 0) equals: 3.
	self assert: (b wordEndAfter: 3) equals: 6.
	self assert: (b wordEndAfter: 6) equals: 8.
	self assert: (b wordStartBefore: 6) equals: 3.
	self assert: (b wordRangeAt: 9) equals: #(9 10).
	self assert: (b wordEndAfter: 10) equals: 13.
	self assert: (b wordStartBefore: 13) equals: 12.
	self assert: (b wordStartBefore: 12) equals: 9
! !
