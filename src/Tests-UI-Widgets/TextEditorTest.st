WidgetTestCase subclass: #TextEditorTest
	instanceVariableNames: 'editor'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

TextEditorTest comment: 'I drive a TextEditor like a user: typing, caret movement by characters, words and lines, selection with shift, the mouse (drag, double and triple click), backspace/delete, auto-indent, tabs, undo/redo, the clipboard, the do it / print it / accept hooks, marks, syntax highlighting tokens, scrolling, the remote-control protocol, and rendered pixels (caret, selection, error marks).'!

!TextEditorTest methodsFor: 'running'!
setUp
	super setUp.
	editor := TextEditor new title: 'code'; yourself.
	self open: editor extent: 400 @ 200.
	editor focus
!
lf
	^String with: Character lf
!
pointOf: aPosition
	"The local point in the middle of the caret slot before aPosition."
	^editor caretRect center
!
clusters
	"é (e + U+0301), a ZWJ family, a flag, a thumb with a skin tone, a Hangul syllable of jamo, x: clusters of 2 5 2 2 3 1 characters."
	^(String with: $e with: (Character value: 16r301)),
		(String withAll: ((#(16r1F469 16r200D 16r1F469 16r200D 16r1F467) collect: [:cp | Character value: cp]))),
		(String with: (Character value: 16r1F1E9) with: (Character value: 16r1F1EA)),
		(String with: (Character value: 16r1F44D) with: (Character value: 16r1F3FD)),
		(String with: (Character value: 16r1112) with: (Character value: 16r1161) with: (Character value: 16r11AB)), 'x'
!
preedit: aString cursor: anInteger
	^window textEditing: (TextEditingEvent string: aString cursor: anInteger selectionSize: nil modifiers: Modifiers none time: Time millisecondClockValue)
! !

!TextEditorTest methodsFor: 'unicode'!
testCaretMovesOverClusters
	| stops |
	editor text: self clusters.
	stops := OrderedCollection new.
	[editor caret < editor size] whileTrue: [self key: #right. stops add: editor caret].
	self assert: stops asArray equals: #(2 7 9 11 14 15).
	stops := OrderedCollection new.
	[editor caret > 0] whileTrue: [self key: #left. stops add: editor caret].
	self assert: stops asArray equals: #(14 11 9 7 2 0).
	self key: #right modifiers: #(#shift).
	self key: #right modifiers: #(#shift).
	self assert: editor selectionInterval equals: (1 to: 7).
	editor caret: 0.
	self click: (editor caretRect center + (((editor xOf: 7) - (editor xOf: 2)) / 3 @ 0) + ((editor xOf: 2) @ 0)).
	self assert: editor caret equals: 2
!
testBackspaceAndDeleteRemoveClusters
	| text |
	text := self clusters.
	editor text: text.
	editor caret: text size.
	#(14 11 9 7 2 0) do: [:n |
		self key: #backspace.
		self assert: editor text equals: (text first: n)].
	self cmd: $z.
	self assert: editor text equals: text.
	editor caret: 0.
	self key: #delete.
	self assert: editor text equals: (text allButFirst: 2).
	self key: #delete.
	self assert: editor text equals: (text allButFirst: 7)
!
testTypedControlsAreDropped
	self type: 'a', (String with: (Character value: 127) with: (Character value: 16r85) with: (Character value: 7)), 'b', (String with: Character tab), (String with: (Character value: 16r200D)).
	self assert: editor text equals: 'ab', (String with: Character tab with: (Character value: 16r200D))
!
testPasteNormalizesLineEnds
	window world clipboard: 'a', (String with: Character cr with: Character lf), 'b', (String with: Character cr), 'c'.
	self cmd: $v.
	self assert: editor text equals: 'a', self lf, 'b', self lf, 'c'.
	self assert: editor lineCount equals: 3
!
testRunsAreDrawnWhereTheyAreMeasured
	"A styled run after CJK and a combining mark starts at its measured x, not at its character count times the cell."
	| form text first last |
	text := '"日本語é', (String with: (Character value: 16r301)), '"#bar'.
	editor text: text.
	form := self render.
	first := (editor rectsFrom: text size - 4 to: text size - 3) first.
	last := (editor rectsFrom: text size - 1 to: text size) first.
	self assert: (self inkIn: first of: form) > 4.
	self assert: (self inkIn: ((last right + 1) @ last top extent: 20 @ last height) of: form) equals: 0
!
testPreeditShowsAtTheCaretUntilCommitted
	| form r x w |
	editor text: 'ab'.
	editor caret: 1.
	r := editor caretRect.
	self preedit: 'にほ' cursor: 2.
	self assert: editor text equals: 'ab'.
	self assert: editor preedit string equals: 'にほ'.
	w := editor font widthOf: 'にほ'.
	x := r left + 0.5.
	form := self render.
	self assert: (self inkIn: (x @ (r bottom - 2) extent: w @ 1) of: form) > (w * 2 * 0.8).
	self assert: (self inkIn: ((x + w) @ r top extent: (editor font widthOf: 'b') @ r height) of: form) > 4.
	self key: #return.
	self key: #backspace.
	self key: #left.
	self assert: editor text equals: 'ab'.
	self assert: editor caret equals: 1.
	self assert: (window world textInputArea first left - (editor screenPointFrom: r origin) x) abs < 1.
	self assert: window world textInputArea last equals: w.
	self type: '日本'.
	self assert: editor preedit isNil.
	self assert: editor text equals: 'a日本b'.
	self assert: editor caret equals: 3.
	self cmd: $z.
	self assert: editor text equals: 'ab'
!
testPreeditCancelledAndReplacingTheSelection
	editor text: 'abc'.
	editor selectFrom: 2 to: 2.
	self preedit: 'x' cursor: 1.
	self assert: editor text equals: 'ac'.
	self preedit: '' cursor: 0.
	self assert: editor preedit isNil.
	self key: #right.
	self assert: editor caret equals: 2.
	self preedit: 'y' cursor: 1.
	editor focusLost.
	self assert: editor preedit isNil
! !

!TextEditorTest methodsFor: 'typing'!
testTyping
	self type: 'abc'.
	self assert: editor text equals: 'abc'.
	self assert: editor caret equals: 3.
	self assert: editor isDirty.
	self key: #left; key: #left.
	self type: 'X'.
	self assert: editor text equals: 'aXbc'.
	self key: #backspace.
	self assert: editor text equals: 'abc'.
	self key: #delete.
	self assert: editor text equals: 'ac'
!
testReadOnlyIgnoresTyping
	editor text: 'fixed'; readOnly: true.
	self type: 'x'.
	self key: #backspace.
	self assert: editor text equals: 'fixed'.
	self cmd: $a.
	self assert: editor selectedText equals: 'fixed'
!
testWordAndLineMovement
	editor text: 'foo bar baz', self lf, 'second line'.
	editor caret: 0.
	self key: #right modifiers: #(#option).
	self assert: editor caret equals: 3.
	self key: #right modifiers: #(#option).
	self assert: editor caret equals: 7.
	self key: #left modifiers: #(#option).
	self assert: editor caret equals: 4.
	self key: #right modifiers: #(#command).
	self assert: editor caret equals: 11.
	self key: #down.
	self assert: editor caret equals: 23.
	self key: #left modifiers: #(#command).
	self assert: editor caret equals: 12.
	self key: #up.
	self assert: editor caret equals: 0.
	self key: #down modifiers: #(#command).
	self assert: editor caret equals: editor text size.
	self key: #up modifiers: #(#command).
	self assert: editor caret equals: 0
!
testGoalColumnSurvivesShortLines
	editor text: 'abcdefgh', self lf, 'ab', self lf, 'abcdefgh'.
	editor caret: 6.
	self key: #down.
	self assert: editor caret equals: 11.
	self key: #down.
	self assert: editor caret equals: 18
!
testShiftSelection
	editor text: 'hello world'.
	editor caret: 0.
	self key: #right modifiers: #(#shift #option).
	self assert: editor selectedText equals: 'hello'.
	self key: #right modifiers: #(#shift).
	self assert: editor selectedText equals: 'hello '.
	self key: #left.
	self assert: editor hasSelection not.
	self assert: editor caret equals: 0.
	self key: #end modifiers: #(#shift).
	self assert: editor selectedText equals: 'hello world'.
	self type: 'bye'.
	self assert: editor text equals: 'bye'
!
testDeleteWords
	editor text: 'one two three'.
	editor caret: 13.
	self key: #backspace modifiers: #(#option).
	self assert: editor text equals: 'one two '.
	editor caret: 0.
	self key: #delete modifiers: #(#option).
	self assert: editor text equals: ' two '.
	editor caret: 5.
	self key: #backspace modifiers: #(#command).
	self assert: editor text equals: ''
!
testReturnKeepsIndentation
	editor text: (String with: Character tab), 'foo'.
	editor caret: 4.
	self key: #return.
	self type: 'bar'.
	self assert: editor text equals: (String with: Character tab), 'foo', self lf, (String with: Character tab), 'bar'
!
testTabIndentsSelectedLines
	| tab |
	tab := String with: Character tab.
	editor text: 'a', self lf, 'b', self lf, 'c'.
	editor selectFrom: 1 to: 3.
	self key: #tab.
	self assert: editor text equals: tab, 'a', self lf, tab, 'b', self lf, 'c'.
	self key: #tab modifiers: #(#shift).
	self assert: editor text equals: 'a', self lf, 'b', self lf, 'c'.
	editor caret: 1.
	self key: #tab.
	self assert: editor text equals: 'a', tab, self lf, 'b', self lf, 'c'
! !

!TextEditorTest methodsFor: 'undo and clipboard'!
testUndoRedoGroupsTyping
	self type: 'abc'; type: 'd'.
	self key: #return.
	self type: 'xy'.
	self cmd: $z.
	self assert: editor text equals: 'abcd', self lf.
	self cmd: $z.
	self assert: editor text equals: 'abcd'.
	self cmd: $z.
	self assert: editor text equals: ''.
	self key: $z modifiers: #(#command #shift).
	self assert: editor text equals: 'abcd'.
	self key: $z modifiers: #(#command #shift); key: $z modifiers: #(#command #shift).
	self assert: editor text equals: 'abcd', self lf, 'xy'.
	self assert: editor caret equals: 7
!
testUndoBackspaceRun
	editor text: 'hello'.
	editor caret: 5.
	self key: #backspace; key: #backspace; key: #backspace.
	self assert: editor text equals: 'he'.
	self cmd: $z.
	self assert: editor text equals: 'hello'.
	self assert: editor caret equals: 5
!
testClipboard
	editor text: 'alpha beta'.
	editor selectFrom: 1 to: 5.
	self cmd: $c.
	self assert: window world clipboard equals: 'alpha'.
	editor caret: 10.
	self cmd: $v.
	self assert: editor text equals: 'alpha betaalpha'.
	editor selectFrom: 7 to: 10.
	self cmd: $x.
	self assert: editor text equals: 'alpha alpha'.
	self assert: window world clipboard equals: 'beta'.
	self cmd: $z.
	self assert: editor text equals: 'alpha betaalpha'
! !

!TextEditorTest methodsFor: 'mouse'!
testClickPlacesCaret
	| p |
	editor text: 'abcdef'.
	editor caret: 3.
	p := editor caretRect center.
	editor caret: 0.
	self click: p.
	self assert: editor caret equals: 3
!
testDragSelects
	| from to |
	editor text: 'hello world'.
	editor caret: 1.
	from := editor caretRect center.
	editor caret: 8.
	to := editor caretRect center.
	self drag: from to: to.
	self assert: editor selectedText equals: 'ello wo'
!
testDoubleClickWordAndTripleClickLine
	| p |
	editor text: 'foo at: bar put: 3', self lf, 'next'.
	editor caret: 5.
	p := editor caretRect center.
	self click: p count: 2.
	self assert: editor selectedText equals: 'at:'.
	self click: p count: 3.
	self assert: editor selectedText equals: 'foo at: bar put: 3', self lf
!
testDoubleClickInsideBrackets
	| p |
	editor text: 'x := (3 + 4) * 2'.
	editor caret: 6.
	p := editor caretRect center + (-1 @ 0).
	self click: p count: 2.
	self assert: editor selectedText equals: '3 + 4'
!
testShiftClickExtends
	| p |
	editor text: 'abcdefgh'.
	editor caret: 6.
	p := editor caretRect center.
	editor caret: 2.
	self click: p modifiers: #(#shift).
	self assert: editor selectedText equals: 'cdef'
! !

!TextEditorTest methodsFor: 'hooks'!
testDoItSelectsLineAndPassesRange
	| got range |
	editor onDoIt: [:t :r | got := t. range := r].
	editor text: '3 + 4', self lf, '100 factorial'.
	editor caret: 8.
	self cmd: $d.
	self assert: got equals: '100 factorial'.
	self assert: range equals: (7 to: 19).
	self assert: editor selectedText equals: '100 factorial'
!
testPrintItInsertsResultWithMark
	| range mark |
	editor onPrintIt: [:t :r | range := editor insertAfterSelection: ' 7' select: true. mark := editor addMark: range style: #result].
	editor text: '3 + 4'.
	editor caret: 2.
	self cmd: $p.
	self assert: editor text equals: '3 + 4 7'.
	self assert: editor selectedText equals: '7'.
	self assert: range equals: (7 to: 7).
	self assert: (editor marksStyled: #result) size equals: 1.
	self assert: (editor remoteChildren first remoteRole) equals: #selection.
	self assert: ((editor remoteChildren at: 2) remoteState) equals: #(#result).
	self type: 'x'.
	self assert: (editor marksStyled: #result) isEmpty
!
testAcceptCleans
	| accepted |
	editor onAccept: [:t | accepted := t. true].
	editor text: 'foo'.
	self type: 'x'.
	self assert: editor isDirty.
	self assert: (editor remoteState includes: 'dirty').
	self cmd: $s.
	self assert: accepted equals: 'xfoo'.
	self deny: editor isDirty.
	self assert: (editor remoteState includes: 'dirty=false').
	editor onAccept: [:t | false].
	self type: 'y'.
	self cmd: $s.
	self assert: editor isDirty
!
testCommandPeriodBubbles
	self assert: (self cmd: $.) isNil
!
testContextMenu
	| menu |
	editor onDoIt: [:t :r | ].
	self rightClick: 20 @ 20.
	menu := window world lastMenu menu.
	self assert: (menu itemLabeled: 'do it') isEnabled.
	self deny: (menu itemLabeled: 'accept') isEnabled.
	self assert: (menu itemLabeled: 'select all') notNil
! !

!TextEditorTest methodsFor: 'marks'!
testMarksShiftAndDisappear
	| mark |
	editor text: 'abc def ghi'.
	mark := editor addMark: (5 to: 7) style: #pc.
	editor caret: 0.
	self type: 'XX'.
	self assert: mark interval equals: (7 to: 9).
	editor caret: 8.
	self type: 'Y'.
	self deny: (editor marks includes: mark)
!
testPcMarkGlides
	editor text: 'a := 1.', self lf, 'b := 2.'.
	editor pcMark: (1 to: 6).
	window keepAnimations.
	editor pcMark: (9 to: 14).
	self assert: editor isGliding.
	window runAnimationsAt: 0.5.
	self assert: editor isGliding.
	window finishAnimations.
	self deny: editor isGliding.
	self assert: editor pcMark interval equals: (9 to: 14)
!
testErrorMarkIsInverted
	| form r |
	editor text: 'foo bar baz'.
	editor addMark: (5 to: 7) style: #error.
	editor caret: 0.
	form := self render.
	r := (editor rectsFrom: 4 to: 7) first.
	self assert: (self fractionDarkIn: r of: form) > 0.6.
	r := (editor rectsFrom: 8 to: 11) first.
	self assert: (self fractionDarkIn: r of: form) < 0.4
! !

!TextEditorTest methodsFor: 'drawing'!
testCaretIsDrawnAndBlinks
	| form r |
	editor text: 'abc'.
	editor caret: 1.
	r := editor caretRect.
	form := self render.
	self assertBlackAt: (r left + 0.75) @ (r top + 10) in: form.
	window fireTimers.
	self deny: editor isCaretOn.
	form := self render.
	self assertWhiteAt: (r left + 0.75) @ (r top + 10) in: form.
	self type: 'x'.
	self assert: editor isCaretOn
!
testSelectionIsTinted
	| form r rgb |
	editor text: 'hello world'.
	editor selectFrom: 1 to: 5.
	form := self render.
	r := (editor rectsFrom: 0 to: 5) first.
	rgb := self rgbAt: (r left + 1) @ (r top + 1) in: form.
	self assert: (rgb at: 3) > (rgb at: 1)
!
testWrapping
	editor text: ((1 to: 30) inject: '' into: [:s :i | s, 'word ']).
	self assert: editor lineCount equals: 1.
	self assert: editor rowCount > 1.
	self assert: (editor rowStart: 2) > 0.
	self assert: ((editor text at: (editor rowStart: 2)) = $ )
!
testScrollingFollowsCaret
	editor text: ((1 to: 60) inject: '' into: [:s :i | s, 'line ', i printString, (String with: Character lf)]).
	editor caret: 0.
	self key: #down modifiers: #(#command).
	self assert: editor scrollOffset > 0.
	self assert: editor caretRect bottom <= editor height.
	self wheel: 50 @ 50 by: 100.
	self assert: editor scrollOffset equals: 0
!
testHighlightTokens
	| types |
	editor text: '"note" ^self foo: #bar with: Transcript'.
	types := editor tokens collect: [:t | t first].
	self assert: types asArray equals: #(#comment #return #self #keyword #symbol #keyword #global).
	self assert: (editor tokenTypeAt: 2) equals: #comment.
	self assert: (editor tokenTypeAt: 7) isNil.
	self assert: ((Theme current syntaxStyleFor: #global) at: 2) equals: Theme current ultramarine.
	self assert: ((Theme current syntaxStyleFor: #keyword) at: 1) face isBold.
	self assert: ((Theme current syntaxStyleFor: #comment) at: 1) face isItalic
!
testIncrementalUpdatesMatchFullRecomputation
	| fresh edits |
	editor text: 'foo: x
	"a comment"
	| t |
	t := #(1 $a #(nested sym) ''str'') , #[1 2].
	^self bar: t baz: ''it''''s'' , Transcript'.
	editor ensureTokens; lineStarts.
	edits := #(#(10 0 '"') #(11 0 '"') #(30 3 'x := 3') #(50 0 '''') #(51 0 '''') #(5 0 '
') #(20 6 '') #(0 0 '#(') #(2 0 ')')).
	edits do: [:e |
		editor replaceFrom: ((e at: 1) min: editor size) to: (((e at: 1) + (e at: 2)) min: editor size) with: (e at: 3).
		fresh := TextEditor new text: editor text; yourself.
		self assert: editor tokens asArray equals: fresh tokens asArray.
		self assert: editor lineStarts equals: fresh lineStarts.
		self assert: ((1 to: editor lineCount) collect: [:i | editor tabCountOfLine: i]) equals: ((1 to: fresh lineCount) collect: [:i | fresh tabCountOfLine: i])]
!
testRedrawOf300LinesIsFast
	| source canvas t0 t |
	source := String new: 20000 streamContents: [:s |
		1 to: 300 do: [:i | s nextPutAll: '	x := self foo: ', i printString, ' bar: #sym. "comment" ^Transcript show: ''text'''; nextPut: Character lf]].
	editor text: source.
	editor bounds: (0 @ 0 extent: 600 @ 800).
	editor drawOn: (Canvas extent: 600 @ 800 scale: 2).
	canvas := Canvas extent: 600 @ 800 scale: 2.
	t0 := Time microsecondClockValue.
	editor drawOn: canvas.
	t := Time microsecondClockValue - t0.
	self assert: t < 30000 description: 'redraw took ', t printString, ' us'
! !

!TextEditorTest methodsFor: 'remote'!
testRemoteState
	| state kids |
	editor text: 'foo', self lf, 'bar'.
	editor selectFrom: 2 to: 3.
	state := editor remoteState.
	self assert: (state includes: 'lines=2').
	self assert: (state includes: 'sel=1-3').
	self assert: (state includes: #focused).
	self assert: (state includes: 'text="foo bar"').
	kids := editor remoteChildren.
	self assert: kids first remoteLabel equals: 'oo'.
	self assert: (kids at: 2) equals: '| foo'.
	self assert: editor remoteText equals: 'foo', self lf, 'bar'
!
testRemoteSelect
	editor text: 'foo', self lf, 'bar baz'.
	editor remoteSelect: 'all'.
	self assert: editor selectedText equals: editor text.
	editor remoteSelect: 'end'.
	self assert: editor caret equals: 11.
	editor remoteSelect: 'line:2'.
	self assert: editor selectedText equals: 'bar baz'.
	editor remoteSelect: 'baz'.
	self assert: editor selectionInterval equals: (9 to: 11).
	editor remoteSelect: (Dictionary new at: 'from' put: 1; at: 'to' put: 3; yourself).
	self assert: editor selectedText equals: 'oo'.
	self assert: (editor remoteState includes: 'sel=1-3')
! !
