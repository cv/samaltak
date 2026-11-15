TestCase subclass: #TerminalScreenTest
	instanceVariableNames: 'screen parser'
	classVariableNames: ''
	package: 'Tests-Tools'!

TerminalScreenTest comment: 'I test the terminal emulator''s TerminalParser and TerminalScreen without a pty: byte strings as a program would print them (printf with escape sequences) and the cells, attributes, cursor, scroll region, scrollback, alternate screen, title and replies they produce; and which cells TerminalView draws color emoji in.'!

!TerminalScreenTest methodsFor: 'running'!
setUp
	screen := TerminalScreen rows: 5 cols: 20.
	parser := TerminalParser on: screen
! !

!TerminalScreenTest methodsFor: 'support'!
feed: aString
	"aString with \e for ESC, \n LF, \r CR, \a BEL, \t TAB, \b BS (as printf would print it), UTF-8 encoded."
	parser feed: (self bytes: aString)
!
bytes: aString
	| s |
	s := WriteStream on: (String new: aString size).
	self expand: aString on: s.
	^s contents utf8Encoded
!
expand: aString on: s
	| i c |
	i := 1.
	[i <= aString size] whileTrue: [
		c := aString at: i.
		(c = $\ and: [i < aString size])
			ifTrue: [
				i := i + 1.
				c := aString at: i.
				s nextPut: (c = $e ifTrue: [Character escape] ifFalse: [
					c = $n ifTrue: [Character lf] ifFalse: [
						c = $r ifTrue: [Character cr] ifFalse: [
							c = $a ifTrue: [Character value: 7] ifFalse: [
								c = $t ifTrue: [Character tab] ifFalse: [
									c = $b ifTrue: [Character value: 8] ifFalse: [c]]]]]])]
			ifFalse: [s nextPut: c].
		i := i + 1]
!
row: r
	^screen textOfRow: r
!
attr: r col: c
	^(screen lineAt: r) attributeAt: c
!
cursor
	^screen row @ screen col
! !

!TerminalScreenTest methodsFor: 'tests'!
testColorEmojiInTheirFirstTwoCells
	"A family (a ZWJ sequence, 6 cells), a thumb with a skin tone (4 cells) and a flag (2 cells) are drawn as color emoji in their first two cells, their other cells blank; a keycap (1 cell) stays text."
	| view line canvas list xs cw |
	view := TerminalView new.
	view parser feed: (String withAll: (#(16r1F468 16r200D 16r1F469 16r200D 16r1F467 16r78 16r1F44D 16r1F3FD 16r78 16r1F1E9 16r1F1EA 16r78 16r31 16rFE0F 16r20E3 16r78)
		collect: [:cp | Character value: cp])) utf8Encoded.
	line := view screen lineAt: 1.
	self assert: (view emojiAt: 1 of: line) last equals: 6.
	self assert: (view emojiAt: 1 of: line) first size equals: 5.
	self assert: (line characterAt: 7) equals: $x.
	self assert: (view emojiAt: 8 of: line) last equals: 11.
	self assert: (view emojiAt: 13 of: line) last equals: 14.
	self assert: (line characterAt: 16) equals: $1.
	self assert: (view emojiAt: 16 of: line) isNil.
	cw := view cellExtent x.
	canvas := Canvas extent: 400 @ 40 scale: (Theme current font: #code) scale.
	view drawLine: line selection: nil on: canvas.
	list := canvas displayList.
	xs := (1 to: list quadCount) collect: [:i | ((list quadAt: i) at: #origin) x / canvas scale].
	self assert: (xs count: [:x | x < (2 * cw)]) > 3.
	"(glyph quads start at the pen, a whole device pixel)"
	self assert: (xs count: [:x | x > (2.25 * cw) and: [x < (5.75 * cw)]]) equals: 0.
	self assert: (xs count: [:x | x > (9.25 * cw) and: [x < (10.75 * cw)]]) equals: 0.
	self assert: (xs count: [:x | (x - (15 * cw)) abs < 0.25]) equals: 1.
	"in the last two columns, also followed by a ZWJ; with U+FE0E text"
	view := TerminalView new.
	view parser feed: ((String new: 78 withAll: $x), (String with: (Character value: 16r1F600) with: (Character value: 16r200D))) utf8Encoded.
	line := view screen lineAt: 1.
	self assert: line size equals: 80.
	self assert: (view emojiAt: 79 of: line) last equals: 80.
	view parser feed: (String with: Character cr with: Character lf with: (Character value: 16r1F600) with: (Character value: 16rFE0E)) utf8Encoded.
	line := view screen lineAt: 2.
	self assert: (view emojiAt: 1 of: line) isNil.
	canvas := Canvas extent: 400 @ 40 scale: (Theme current font: #code) scale.
	view drawLine: line selection: nil on: canvas.
	self assert: canvas displayList quadCount equals: 1
!
testPrintingAndDelayedAutowrap
	self feed: 'abc'.
	self assert: (self row: 1) equals: 'abc'.
	self assert: self cursor equals: 1 @ 4.
	self feed: '\r\n0123456789012345678'.
	self assert: self cursor equals: 2 @ 20.
	self feed: '9'.
	self assert: self cursor equals: 2 @ 20.
	self assert: screen pendingWrap.
	self deny: (screen lineAt: 2) isWrapped.
	self feed: 'X'.
	self assert: (self row: 2) equals: '01234567890123456789'.
	self assert: (self row: 3) equals: 'X'.
	self assert: (screen lineAt: 2) isWrapped.
	self assert: self cursor equals: 3 @ 2
!
testAutowrapOffOverwritesTheLastColumn
	self feed: '\e[?7l01234567890123456789XY'.
	self assert: (self row: 1) equals: '0123456789012345678Y'.
	self assert: self cursor equals: 1 @ 20
!
testControlCharacters
	self feed: 'abc\bX\rY\tZ'.
	self assert: (self row: 1) equals: 'YbX     Z'.
	self feed: '\n'.
	self assert: self cursor equals: 2 @ 10.
	self feed: '\e[3g\e[5G\eH\e[9G\eH\r\tU'.
	self assert: (self row: 2) equals: '    U'.
	self feed: '\r\e[2I'.
	self assert: screen col equals: 9.
	self feed: '\e[Z'.
	self assert: screen col equals: 5
!
testSgrColorsAndAttributes
	| red |
	self feed: '\e[1;31mred\e[0m ok \e[4;7;44mu\e[22;24;27;49m \e[38;5;208mo\e[38;2;10;20;30;48;5;17mt\e[39;49m.\e[3;2;9;8mx\e[m'.
	self assert: (self row: 1) equals: 'red ok u ot.x'.
	red := self attr: 1 col: 1.
	self assert: (TerminalScreen isBold: red).
	self assert: (TerminalScreen foregroundOf: red) equals: 2.
	self assert: (TerminalScreen backgroundOf: red) equals: 0.
	self assert: (self attr: 1 col: 3) equals: red.
	self assert: (self attr: 1 col: 4) equals: 0.
	self assert: (self attr: 1 col: 5) equals: 0.
	self assert: (TerminalScreen isUnderline: (self attr: 1 col: 8)).
	self assert: (TerminalScreen isInverse: (self attr: 1 col: 8)).
	self assert: (TerminalScreen backgroundOf: (self attr: 1 col: 8)) equals: 5.
	self assert: (self attr: 1 col: 9) equals: 0.
	self assert: (TerminalScreen foregroundOf: (self attr: 1 col: 10)) equals: 209.
	self assert: (TerminalScreen foregroundOf: (self attr: 1 col: 11)) equals: 16r1000000 + 16r0A141E.
	self assert: (TerminalScreen backgroundOf: (self attr: 1 col: 11)) equals: 18.
	self assert: (TerminalScreen foregroundOf: (self attr: 1 col: 12)) equals: 0.
	self assert: (TerminalScreen backgroundOf: (self attr: 1 col: 12)) equals: 0.
	self assert: (TerminalScreen isItalic: (self attr: 1 col: 13)).
	self assert: (TerminalScreen isDim: (self attr: 1 col: 13)).
	self assert: (TerminalScreen isStrike: (self attr: 1 col: 13)).
	self assert: (TerminalScreen isHidden: (self attr: 1 col: 13)).
	self assert: screen attribute equals: 0
!
testBrightAndDefaultColors
	self feed: '\e[92;103ma\e[39mb'.
	self assert: (TerminalScreen foregroundOf: (self attr: 1 col: 1)) equals: 11.
	self assert: (TerminalScreen backgroundOf: (self attr: 1 col: 1)) equals: 12.
	self assert: (TerminalScreen foregroundOf: (self attr: 1 col: 2)) equals: 0.
	self assert: (TerminalScreen backgroundOf: (self attr: 1 col: 2)) equals: 12
!
testCursorMovement
	self feed: '\e[3;5H'.
	self assert: self cursor equals: 3 @ 5.
	self feed: '\e[A\e[2C'.
	self assert: self cursor equals: 2 @ 7.
	self feed: '\e[10B\e[40D'.
	self assert: self cursor equals: 5 @ 1.
	self feed: '\e[99;99f'.
	self assert: self cursor equals: 5 @ 20.
	self feed: '\e[7G\e[2d'.
	self assert: self cursor equals: 2 @ 7.
	self feed: '\e7\e[H\e[1;4mx\e8'.
	self assert: self cursor equals: 2 @ 7.
	self feed: 'y'.
	self assert: (self attr: 2 col: 7) equals: 0.
	self feed: '\e[s\e[5;1H\e[u'.
	self assert: self cursor equals: 2 @ 8.
	self feed: '\e[2E'.
	self assert: self cursor equals: 4 @ 1.
	self feed: '\e[H'.
	self assert: self cursor equals: 1 @ 1
!
testEraseUsesTheCurrentBackground
	self feed: '0123456789\r\n0123456789\r\n0123456789\e[2;5H'.
	self feed: '\e[K'.
	self assert: (self row: 2) equals: '0123'.
	self feed: '\e[1;5H\e[1K'.
	self assert: (self row: 1) equals: '     56789'.
	self feed: '\e[3;3H\e[41m\e[2X\e[0m'.
	self assert: (self row: 3) equals: '01  456789'.
	self assert: (TerminalScreen backgroundOf: (self attr: 3 col: 3)) equals: 2.
	self assert: (TerminalScreen foregroundOf: (self attr: 3 col: 3)) equals: 0.
	self feed: '\e[2;1H\e[J'.
	self assert: (self row: 1) equals: '     56789'.
	self assert: (self row: 2) equals: ''.
	self assert: (self row: 3) equals: ''.
	self feed: 'abc\e[2J'.
	self assert: screen text equals: (String new: 4 withAll: Character lf).
	self assert: self cursor equals: 2 @ 4
!
testInsertAndDeleteCharacters
	self feed: 'abcdef\e[3G\e[2@'.
	self assert: (self row: 1) equals: 'ab  cdef'.
	self feed: '\e[3P'.
	self assert: (self row: 1) equals: 'abdef'.
	self feed: '\e[4hXY\e[4l'.
	self assert: (self row: 1) equals: 'abXYdef'
!
testInsertAndDeleteLines
	self feed: 'a\r\nb\r\nc\r\nd\r\ne\e[2;1H\e[L'.
	self assert: screen text equals: 'a

b
c
d'.
	self feed: '\e[2M'.
	self assert: screen text equals: 'a
c
d

'.
	self assert: screen scrollback isEmpty
!
testScrollRegion
	self feed: '1\r\n2\r\n3\r\n4\r\n5\e[2;4r'.
	self assert: self cursor equals: 1 @ 1.
	self feed: '\e[4;1H\nX'.
	self assert: screen text equals: '1
3
4
X
5'.
	self assert: screen scrollback isEmpty.
	self feed: '\e[2;1H\eMY'.
	self assert: screen text equals: '1
Y
3
4
5'.
	self feed: '\e[S'.
	self assert: (self row: 2) equals: '3'.
	self feed: '\e[2T'.
	self assert: screen text equals: '1


3
5'
!
testScrollingIntoTheBoundedScrollback
	screen maxScrollback: 10.
	1 to: 30 do: [:i | self feed: 'line ', i printString, '\r\n'].
	self assert: screen scrollback size equals: 10.
	self assert: screen scrolledTotal equals: 26.
	self assert: screen scrollback first string equals: 'line 17'.
	self assert: screen scrollback last string equals: 'line 26'.
	self assert: (self row: 4) equals: 'line 30'.
	self assert: (screen lineAtIndex: screen firstLineIndex) string equals: 'line 17'.
	self assert: (screen lineAtIndex: screen scrolledTotal + 1) string equals: 'line 27'.
	self feed: '\e[3J'.
	self assert: screen scrollback isEmpty
!
testAlternateScreenRestoresTheMainScreen
	self feed: 'main 1\r\nmain 2\e[1;31m'.
	self feed: '\e[?1049h'.
	self assert: screen isAlternateScreen.
	self assert: screen text equals: (String new: 4 withAll: Character lf).
	self feed: '\e[Hfull screen\r\n\n\n\n\n\n'.
	self assert: screen scrollback isEmpty.
	self feed: '\e[?1049l'.
	self deny: screen isAlternateScreen.
	self assert: (self row: 1) equals: 'main 1'.
	self assert: (self row: 2) equals: 'main 2'.
	self assert: self cursor equals: 2 @ 7.
	self assert: (TerminalScreen foregroundOf: screen attribute) equals: 2.
	self feed: '\e[?47hx\e[?47l'.
	self assert: (self row: 2) equals: 'main 2'
!
testUtf8SplitAcrossReads
	parser feed: #[16rC3].
	self assert: (self row: 1) equals: ''.
	parser feed: #[16rBC 16rE2 16r94].
	parser feed: #[16r80 16rF0 16r9F].
	parser feed: #[16r98 16r80 65].
	self assert: (self row: 1) equals: (String with: (Character value: 252) with: (Character value: 16r2500) with: (Character value: 16r1F600) with: $A).
	parser feed: #[16rC3 65 16rFF].
	self assert: ((self row: 1) last: 3) equals: (String with: (Character value: 16rFFFD) with: $A with: (Character value: 16rFFFD))
!
testOscSetsTheTitle
	self feed: '\e]0;first title\a'.
	self assert: screen title equals: 'first title'.
	self feed: '\e]2;sec'.
	self assert: screen title equals: 'first title'.
	self feed: 'ond ✓\e\\after'.
	self assert: screen title equals: 'second ✓'.
	self assert: (self row: 1) equals: 'after'.
	self feed: '\e]7;file:///tmp\a\e]1;icon\a'.
	self assert: screen title equals: 'second ✓'
!
testModes
	self assert: screen isCursorVisible.
	self feed: '\e[?25l\e[?1h\e[?2004h\e[?1000h'.
	self deny: screen isCursorVisible.
	self assert: screen appCursorKeys.
	self assert: screen bracketedPaste.
	self assert: screen mouseTracking equals: 1000.
	self feed: '\e[?1;2004;1000l\e[?25h'.
	self assert: screen isCursorVisible.
	self deny: screen appCursorKeys.
	self deny: screen bracketedPaste.
	self assert: screen mouseTracking equals: 0
!
testDeviceReports
	self feed: '\e[2;3H\e[6n\e[5n\e[c'.
	self assert: screen takeReplies equals: (self bytes: '\e[2;3R\e[0n\e[?62;22c') asString.
	self assert: screen takeReplies equals: ''
!
testUnknownSequencesAreIgnored
	self feed: '\eP1$r0m\e\\\e[>4;1m\e[ q\e[?u\e=\e>\e#3ok\e[1$p'.
	self assert: (self row: 1) equals: 'ok'
!
testLineDrawingCharset
	self feed: '\e(0lqk\e(Bq'.
	self assert: (self row: 1) equals: (String with: (Character value: 16r250C) with: (Character value: 16r2500) with: (Character value: 16r2510) with: $q)
!
testResizeKeepsTheCursorLine
	self feed: '1\r\n2\r\n3\r\n4\r\n5'.
	screen rows: 3 cols: 10.
	self assert: screen text equals: '3
4
5'.
	self assert: screen scrollback size equals: 2.
	self assert: self cursor equals: 3 @ 2.
	screen rows: 6 cols: 30.
	self assert: screen rows equals: 6.
	self assert: (screen lineAt: 6) size equals: 30.
	self assert: (self row: 3) equals: '5'
!
testFullResetAndSoftReset
	self feed: 'abc\e[?25l\e[2;3r\e[1m\e[!!p'.
	self assert: screen isCursorVisible.
	self assert: screen attribute equals: 0.
	self assert: (self row: 1) equals: 'abc'.
	self feed: '\ec'.
	self assert: screen text equals: (String new: 4 withAll: Character lf).
	self assert: self cursor equals: 1 @ 1
!
testRepeatAndAlignment
	self feed: 'x\e[3b'.
	self assert: (self row: 1) equals: 'xxxx'.
	self feed: '\e#8'.
	self assert: (self row: 5) equals: (String new: 20 withAll: $E)
!
testWideCharactersTakeTwoCells
	| line |
	self feed: 'a日b\r\n😀x'.
	line := screen lineAt: 1.
	self assert: (self row: 1) equals: 'a日b'.
	self assert: (line isWideAt: 2).
	self assert: (line isContinuationAt: 3).
	self assert: (line characterAt: 4) equals: $b.
	self assert: (self row: 2) equals: '😀x'.
	self assert: self cursor equals: 2 @ 4.
	self feed: '\e[31m語'.
	self assert: (self attr: 2 col: 5) equals: (self attr: 2 col: 4).
	self assert: (TerminalScreen foregroundOf: (self attr: 2 col: 5)) equals: 2
!
testWideCharacterAtTheLastColumn
	self feed: '\e[1;20H日'.
	self assert: (self row: 1) equals: ''.
	self assert: (screen lineAt: 1) isWrapped.
	self assert: (self row: 2) equals: '日'.
	self assert: self cursor equals: 2 @ 3.
	self feed: '\e[3;19H語'.
	self assert: self cursor equals: 3 @ 20.
	self assert: screen pendingWrap.
	self feed: 'x'.
	self assert: (self row: 3) equals: (String new: 18 withAll: $ ), '語'.
	self assert: (self row: 4) equals: 'x'.
	self feed: '\e[?7l\e[5;20H本'.
	self assert: (self row: 5) equals: (String new: 18 withAll: $ ), '本'.
	self assert: self cursor equals: 5 @ 20
!
testOverwritingHalfAWideCharacterBlanksTheOther
	self feed: '日本語\e[1;2Hx'.
	self assert: (self row: 1) equals: ' x本語'.
	self feed: '\e[1;3Hy'.
	self assert: (self row: 1) equals: ' xy 語'.
	self feed: '\e[1;4H日'.
	self assert: (self row: 1) equals: ' xy日'.
	self assert: ((screen lineAt: 1) isContinuationAt: 5).
	self deny: ((screen lineAt: 1) isContinuationAt: 6)
!
testZeroWidthCharactersJoinTheCharacterBefore
	| acute zwj line |
	acute := Character value: 16r301.
	zwj := Character value: 16r200D.
	parser feed: (String with: $e with: acute with: $z) utf8Encoded.
	self assert: self cursor equals: 1 @ 3.
	line := screen lineAt: 1.
	self assert: (line marksAt: 1) equals: (String with: acute).
	self assert: (self row: 1) equals: (String with: $e with: acute with: $z).
	parser feed: (String with: (Character value: 16r1F468) with: zwj with: (Character value: 16r1F469) with: (Character value: 16rFE0F)) utf8Encoded.
	self assert: self cursor equals: 1 @ 7.
	self assert: (line marksAt: 3) equals: (String with: zwj).
	self assert: (line marksAt: 5) equals: (String with: (Character value: 16rFE0F)).
	self assert: ((self row: 1) allButFirst: 3) equals: (String with: (Character value: 16r1F468) with: zwj with: (Character value: 16r1F469) with: (Character value: 16rFE0F)).
	self feed: '\e[1;1Hx'.
	self assert: (line marksAt: 1) isNil.
	self feed: '\e[2;1H'.
	parser feed: (String with: acute) utf8Encoded.
	self assert: (self row: 2) equals: ''.
	self feed: '\e[2;20Ha'.
	parser feed: (String with: acute) utf8Encoded.
	self assert: ((screen lineAt: 2) marksAt: 20) equals: (String with: acute).
	self assert: screen pendingWrap
!
testEraseInsertDeleteOverWideCharacters
	self feed: 'a日本b\e[1;3H\e[X'.
	self assert: (self row: 1) equals: 'a  本b'.
	self feed: '\e[2K\e[1Ga日本b\e[1;3H\e[@'.
	self assert: (self row: 1) equals: 'a   本b'.
	self assert: ((screen lineAt: 1) isWideAt: 5).
	self feed: '\e[2K\e[1Ga日本b\e[1;2H\e[P'.
	self assert: (self row: 1) equals: 'a 本b'.
	self assert: ((screen lineAt: 1) isWideAt: 3).
	self feed: '\e[2;19H日\e[2;1H\e[@'.
	self assert: (self row: 2) equals: ''.
	self deny: ((screen lineAt: 2) isContinuationAt: 20).
	self feed: '\e[3;1Hx日y\e[3;3H\e[K'.
	self assert: (self row: 3) equals: 'x'
!
testResizeCutsAWideCharacter
	self feed: '\e[1;9H日'.
	screen rows: 5 cols: 9.
	self assert: (self row: 1) equals: ''.
	self deny: ((screen lineAt: 1) isWideAt: 9)
! !
