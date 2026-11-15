Object subclass: #TextBuffer
	instanceVariableNames: 'string lineStarts lineTabs lineOthers listeners'
	classVariableNames: ''
	package: 'UI-Widgets'!

TextBuffer comment: 'I am the text of a TextEditor: a String with line feeds only, its line index (the gap position where each line starts, the number of tabs on it and of other characters outside printable ASCII, kept up to date incrementally) and word and bracket boundaries.

A word is a run of grapheme clusters of one class: letters, digits, _ and marks of any script; or wide letters (CJK ideographs, kana, Hangul), so 日本語abc is two words. A cluster belongs to the class of its first character; punctuation (、。), symbols, emoji and spaces (NBSP and U+3000 too) are outside words. Word boundaries are cluster boundaries.

Positions are gap positions (0 = before the first character, size = after the last). replaceFrom:to:with: tells my listeners textReplacedFrom: start to: stop with: aString (after the change); string: tells them textReset.
	(TextBuffer string: ''ab'', (String with: Character lf), ''cd'') lineIndexOf: 3   "2"'!

!TextBuffer methodsFor: 'initialization'!
initialize
	string := ''.
	listeners := #()
! !

!TextBuffer methodsFor: 'accessing'!
string
	^string
!
string: aString
	"Replace the whole text (line ends normalized to line feeds)."
	string := self normalize: aString.
	lineStarts := nil.
	listeners do: [:each | each textReset]
!
size
	^string size
!
at: anIndex
	^string at: anIndex
!
copyFrom: start to: stop
	^string copyFrom: start to: stop
!
normalize: aString
	"aString (or '' for nil) with cr lf and cr turned into lf."
	| s |
	s := aString isNil ifTrue: [''] ifFalse: [aString asString].
	(s includes: Character cr) ifFalse: [^s].
	s := s copyReplaceAll: (String with: Character cr with: Character lf) with: (String with: Character lf).
	^s copyReplaceAll: (String with: Character cr) with: (String with: Character lf)
! !

!TextBuffer methodsFor: 'listeners'!
addListener: anObject
	"anObject receives textReplacedFrom:to:with: and textReset."
	listeners := listeners copyWith: anObject
!
removeListener: anObject
	listeners := listeners copyWithout: anObject
! !

!TextBuffer methodsFor: 'editing'!
replaceFrom: start to: stop with: aString
	"Replace the characters between the gap positions start and stop with aString (line feeds only)."
	(aString isWideString and: [string isWideString not]) ifTrue: [string := string asWideString].
	string := string copyReplaceFrom: start + 1 to: stop with: aString.
	self updateLinesFrom: start to: stop with: aString.
	listeners do: [:each | each textReplacedFrom: start to: stop with: aString]
! !

!TextBuffer methodsFor: 'lines'!
lineStarts
	"Gap positions where the lines start."
	| starts tabs others lf tab n m |
	lineStarts isNil ifFalse: [^lineStarts].
	starts := OrderedCollection new: string size // 30 + 4.
	tabs := OrderedCollection new: string size // 30 + 4.
	others := OrderedCollection new: string size // 30 + 4.
	starts add: 0.
	lf := Character lf.
	tab := Character tab.
	n := 0.
	m := 0.
	1 to: string size do: [:i |
		| c v |
		c := string at: i.
		c == lf
			ifTrue: [starts add: i. tabs add: n. others add: m. n := 0. m := 0]
			ifFalse: [
				c == tab
					ifTrue: [n := n + 1]
					ifFalse: [v := c value. (v > 126 or: [v < 32]) ifTrue: [m := m + 1]]]].
	tabs add: n.
	others add: m.
	lineTabs := tabs asArray.
	lineOthers := others asArray.
	^lineStarts := starts asArray
!
lineCount
	^self lineStarts size
!
lineAt: anInteger
	^string copyFrom: (self lineStarts at: anInteger) + 1 to: (self lineEndAt: anInteger)
!
lines
	^(1 to: self lineCount) collect: [:i | self lineAt: i]
!
lineEndAt: lineIndex
	"The gap position at the end of the line (before its line feed)."
	| starts |
	starts := self lineStarts.
	^lineIndex < starts size ifTrue: [(starts at: lineIndex + 1) - 1] ifFalse: [string size]
!
lineIndexOf: aPosition
	^TextBuffer indexIn: self lineStarts atOrBefore: aPosition
!
lineRangeAt: aPosition
	| line |
	line := self lineIndexOf: aPosition.
	^Array with: (self lineStarts at: line) with: (self lineEndAt: line)
!
lineHasTab: lineIndex
	^(self tabCountOfLine: lineIndex) > 0
!
tabCountOfLine: lineIndex
	self lineStarts.
	^lineTabs at: lineIndex
!
lineTabs
	"The number of tabs on each line."
	self lineStarts.
	^lineTabs
!
isPlainLine: lineIndex
	"Whether the line holds only printable ASCII (no tabs)."
	self lineStarts.
	^(lineTabs at: lineIndex) = 0 and: [(lineOthers at: lineIndex) = 0]
!
lineOthers
	"The number of characters outside printable ASCII on each line, tabs aside."
	self lineStarts.
	^lineOthers
!
updateLinesFrom: start to: stop with: aString
	"Update the line starts and character counts after the characters start + 1 .. stop became aString."
	| delta first last newStarts newTabs newOthers before after lf |
	lineStarts isNil ifTrue: [^self].
	delta := aString size - (stop - start).
	lf := Character lf.
	first := TextBuffer indexIn: lineStarts atOrBefore: start.
	last := TextBuffer indexIn: lineStarts atOrBefore: stop.
	"lines first..last are replaced by the lines of the new region"
	newStarts := OrderedCollection new.
	newStarts add: (lineStarts at: first).
	1 to: aString size do: [:i | (aString at: i) == lf ifTrue: [newStarts add: start + i]].
	before := lineStarts copyFrom: 1 to: first - 1.
	after := (lineStarts copyFrom: last + 1 to: lineStarts size) collect: [:each | each + delta].
	lineStarts := before , newStarts asArray , after.
	newTabs := Array new: newStarts size.
	newOthers := Array new: newStarts size.
	1 to: newStarts size do: [:k | | counts |
		counts := self countsInLine: first + k - 1.
		newTabs at: k put: counts x.
		newOthers at: k put: counts y].
	lineTabs := (lineTabs copyFrom: 1 to: first - 1) , newTabs , (lineTabs copyFrom: last + 1 to: lineTabs size).
	lineOthers := (lineOthers copyFrom: 1 to: first - 1) , newOthers , (lineOthers copyFrom: last + 1 to: lineOthers size)
!
countsInLine: lineIndex
	"tabs @ other characters outside printable ASCII"
	| n m tab |
	n := 0.
	m := 0.
	tab := Character tab.
	(lineStarts at: lineIndex) + 1 to: (self lineEndAt: lineIndex) do: [:i | | c |
		c := string at: i.
		c == tab
			ifTrue: [n := n + 1]
			ifFalse: [(c value > 126 or: [c value < 32]) ifTrue: [m := m + 1]]].
	^n @ m
! !

!TextBuffer methodsFor: 'words'!
wordRangeAt: aPosition
	"Answer {start. stop} gap positions of the word, bracket contents or whitespace run around aPosition."
	| s e k before after |
	before := aPosition > 0 ifTrue: [string at: aPosition] ifFalse: [nil].
	after := aPosition < string size ifTrue: [string at: aPosition + 1] ifFalse: [nil].
	(before notNil and: ['([{''"' includes: before]) ifTrue: [
		e := self matchingCloseFor: aPosition.
		e isNil ifFalse: [^Array with: aPosition with: e]].
	(after notNil and: [')]}''"' includes: after]) ifTrue: [
		s := self matchingOpenFor: aPosition + 1.
		s isNil ifFalse: [^Array with: s with: aPosition]].
	k := after isNil ifTrue: [0] ifFalse: [self wordClassAt: aPosition + 1].
	(k = 0 and: [before notNil]) ifTrue: [k := self wordClassAt: (string graphemeClusterStartBefore: aPosition) + 1].
	k = 0 ifTrue: [
		(aPosition = (self lineStarts at: (self lineIndexOf: aPosition)) or: [aPosition = (self lineEndAt: (self lineIndexOf: aPosition))])
			ifTrue: [^self lineRangeAt: aPosition].
		^Array with: aPosition with: aPosition].
	s := self start: aPosition ofRunOf: k.
	e := self end: aPosition ofRunOf: k.
	(e < string size and: [(string at: e + 1) = $:]) ifTrue: [
		(e + 1 < string size and: [(string at: e + 2) = $=]) ifFalse: [e := e + 1]].
	^Array with: s with: e
!
matchingCloseFor: aPosition
	"The character before aPosition opens a bracket or quote; answer the gap position before its partner, or nil."
	| open close depth i c |
	open := string at: aPosition.
	close := open = $( ifTrue: [$)] ifFalse: [open = $[ ifTrue: [$]] ifFalse: [open = ${ ifTrue: [$}] ifFalse: [open]]].
	depth := 1.
	i := aPosition + 1.
	[i <= string size] whileTrue: [
		c := string at: i.
		(c = close) ifTrue: [depth := depth - 1. depth = 0 ifTrue: [^i - 1]]
			ifFalse: [(c = open and: [open ~= close]) ifTrue: [depth := depth + 1]].
		i := i + 1].
	^nil
!
matchingOpenFor: anIndex
	"The character at anIndex closes a bracket or quote; answer the gap position after its partner, or nil."
	| close open depth i c |
	close := string at: anIndex.
	open := close = $) ifTrue: [$(] ifFalse: [close = $] ifTrue: [$[] ifFalse: [close = $} ifTrue: [${] ifFalse: [close]]].
	depth := 1.
	i := anIndex - 1.
	[i >= 1] whileTrue: [
		c := string at: i.
		(c = open) ifTrue: [depth := depth - 1. depth = 0 ifTrue: [^i]]
			ifFalse: [(c = close and: [open ~= close]) ifTrue: [depth := depth + 1]].
		i := i - 1].
	^nil
!
isWordCharacter: aCharacter
	^aCharacter isLetter or: [aCharacter isDigit or: [aCharacter = $_ or: [aCharacter isMark]]]
!
wordClassAt: anIndex
	"The word class of the cluster starting with the character at anIndex: 0 outside words, 1 letters, digits, _ and marks, 2 wide letters (CJK, Hangul)."
	| c |
	c := string at: anIndex.
	(self isWordCharacter: c) ifFalse: [^0].
	^(c value >= 16r1100 and: [c displayWidth = 2]) ifTrue: [2] ifFalse: [1]
!
start: aPosition ofRunOf: aClass
	"The start of the run of clusters of word class aClass that ends at aPosition."
	| p q |
	p := aPosition.
	[p > 0 and: [(self wordClassAt: (q := string graphemeClusterStartBefore: p) + 1) = aClass]] whileTrue: [p := q].
	^p
!
end: aPosition ofRunOf: aClass
	"The end of the run of clusters of word class aClass that starts at aPosition."
	| p |
	p := aPosition.
	[p < string size and: [(self wordClassAt: p + 1) = aClass]] whileTrue: [p := string graphemeClusterEndAfter: p].
	^p
!
wordStartBefore: aPosition
	| p |
	p := self start: aPosition ofRunOf: 0.
	p = 0 ifTrue: [^0].
	^self start: p ofRunOf: (self wordClassAt: (string graphemeClusterStartBefore: p) + 1)
!
wordEndAfter: aPosition
	| p |
	p := self end: aPosition ofRunOf: 0.
	p = string size ifTrue: [^p].
	^self end: p ofRunOf: (self wordClassAt: p + 1)
! !

!TextBuffer class methodsFor: 'instance creation'!
string: aString
	^self new string: aString; yourself
! !

!TextBuffer class methodsFor: 'searching'!
indexIn: anArray atOrBefore: aPosition
	"The largest index whose element is <= aPosition (binary search; anArray ascending, first element 0)."
	| lo hi mid |
	lo := 1.
	hi := anArray size.
	[lo < hi] whileTrue: [
		mid := lo + hi + 1 // 2.
		(anArray at: mid) <= aPosition ifTrue: [lo := mid] ifFalse: [hi := mid - 1]].
	^lo
! !
