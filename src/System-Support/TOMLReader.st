Object subclass: #TOMLReader
	instanceVariableNames: 'source position root table line'
	classVariableNames: ''
	package: 'System-Support'!

TOMLReader comment: 'I read TOML (toml.io), the configuration format of Omarchy, Alacritty and many other Linux programs, into Dictionaries: a table is a Dictionary with String keys, an array an Array, a string a String, an integer an Integer, a float a Float, true and false Booleans. Dotted keys and [a.b] headers nest tables; [[a]] appends a table to the array a.

	TOMLReader parse: ''[popups]
background = "#FFFCF0"   # a comment
border-alpha = 1.0''
	"a Dictionary(''popups''->a Dictionary(''background''->''#FFFCF0'' ''border-alpha''->1.0 ))"

Not read: dates and times (kept as their text), multi-line strings, inline tables, and the checks that make a document invalid (a key defined twice is redefined). A syntax error signals an Error naming the line.'!

!TOMLReader methodsFor: 'initialization'!
setSource: aString
	source := aString.
	position := 1.
	line := 1.
	root := Dictionary new.
	table := root
! !

!TOMLReader methodsFor: 'reading'!
read
	"Answer the document's root table."
	[self skipBlankAndComments. self atEnd] whileFalse: [
		self peek = $[
			ifTrue: [self readHeader]
			ifFalse: [self readKeyValue].
		self skipSpaces.
		self skipComment.
		(self atEnd or: [self peek = Character lf or: [self peek = Character cr]])
			ifFalse: [self syntaxError: 'end of line expected']].
	^root
!
readHeader
	| array keys |
	self next.
	array := self peek = $[.
	array ifTrue: [self next].
	keys := self readKeyPath.
	self expect: $].
	array ifTrue: [self expect: $]].
	array
		ifTrue: [
			| list |
			list := (self tableAt: keys allButLast in: root) at: keys last ifAbsent: [#()].
			table := Dictionary new.
			(self tableAt: keys allButLast in: root) at: keys last put: (list copyWith: table)]
		ifFalse: [table := self tableAt: keys in: root]
!
readKeyValue
	| keys |
	keys := self readKeyPath.
	self expect: $=.
	(self tableAt: keys allButLast in: table) at: keys last put: self readValue
!
readKeyPath
	"key, or key.key...; bare keys (A-Za-z0-9_-) or quoted."
	| keys |
	keys := OrderedCollection new.
	[self skipSpaces.
	 keys add: self readKey.
	 self skipSpaces.
	 self peek = $.] whileTrue: [self next].
	^keys asArray
!
readKey
	| start |
	(self peek = $" or: [self peek = $']) ifTrue: [^self readString].
	start := position.
	[self atEnd not and: [self peek isLetter or: [self peek isDigit or: [self peek = $_ or: [self peek = $-]]]]] whileTrue: [self next].
	position = start ifTrue: [self syntaxError: 'key expected'].
	^source copyFrom: start to: position - 1
!
readValue
	| c |
	self skipSpaces.
	self atEnd ifTrue: [self syntaxError: 'value expected'].
	c := self peek.
	(c = $" or: [c = $']) ifTrue: [^self readString].
	c = $[ ifTrue: [^self readArray].
	^self readBare
!
readArray
	| items |
	self next.
	items := OrderedCollection new.
	[self skipBlankAndComments.
	 self peek = $]] whileFalse: [
		items add: self readValue.
		self skipBlankAndComments.
		self peek = $, ifTrue: [self next]].
	self next.
	^items asArray
!
readString
	| quote out c |
	quote := self next.
	out := WriteStream on: String new.
	[(self atEnd or: [self peek = Character lf]) ifTrue: [self syntaxError: 'unterminated string'].
	 (c := self next) = quote] whileFalse: [
		(c = $\ and: [quote = $"])
			ifTrue: [out nextPut: self readEscape]
			ifFalse: [out nextPut: c]].
	^out contents
!
readEscape
	| c |
	c := self next.
	c = $n ifTrue: [^Character lf].
	c = $t ifTrue: [^Character tab].
	c = $r ifTrue: [^Character cr].
	c = $b ifTrue: [^Character value: 8].
	c = $f ifTrue: [^Character value: 12].
	c = $e ifTrue: [^Character value: 27].
	c = $u ifTrue: [^self readHexDigits: 4].
	c = $U ifTrue: [^self readHexDigits: 8].
	^c
!
readHexDigits: n
	| value |
	value := 0.
	n timesRepeat: [
		| d |
		d := self next digitValue.
		(d between: 0 and: 15) ifFalse: [self syntaxError: 'hex digit expected'].
		value := value * 16 + d].
	^Character value: value
!
readBare
	"true, false, a number, or (dates, inf, nan) the text."
	| start text clean |
	start := position.
	[self atEnd not and: [(' ,]#' includes: self peek) not and: [self peek value > 32]]] whileTrue: [self next].
	text := source copyFrom: start to: position - 1.
	text isEmpty ifTrue: [self syntaxError: 'value expected'].
	text = 'true' ifTrue: [^true].
	text = 'false' ifTrue: [^false].
	clean := text reject: [:ch | ch = $_].
	(clean beginsWith: '0x') ifTrue: [^Integer readFrom: (clean allButFirst: 2) asUppercase base: 16].
	(clean allSatisfy: [:ch | ch isDigit or: ['+-' includes: ch]]) ifTrue: [^Integer readFrom: clean].
	(clean allSatisfy: [:ch | ch isDigit or: ['+-.eE' includes: ch]]) ifTrue: [
		^[Number readFrom: clean] on: Error do: [:e | e return: text]].
	^text
! !

!TOMLReader methodsFor: 'tables'!
tableAt: keys in: aDictionary
	"The table at the path keys below aDictionary, made where missing; for an array of tables its last."
	| t |
	t := aDictionary.
	keys do: [:k |
		| next |
		next := t at: k ifAbsent: [t at: k put: Dictionary new].
		next isArray ifTrue: [next := next last].
		next isDictionary ifFalse: [self syntaxError: k, ' is not a table'].
		t := next].
	^t
! !

!TOMLReader methodsFor: 'scanning'!
atEnd
	^position > source size
!
peek
	^self atEnd ifTrue: [nil] ifFalse: [source at: position]
!
next
	| c |
	c := source at: position.
	position := position + 1.
	c = Character lf ifTrue: [line := line + 1].
	^c
!
expect: aCharacter
	self skipSpaces.
	self peek = aCharacter ifFalse: [self syntaxError: (String with: aCharacter), ' expected'].
	self next
!
skipSpaces
	[self atEnd not and: [self peek = $  or: [self peek = Character tab]]] whileTrue: [self next]
!
skipComment
	self peek = $# ifTrue: [[self atEnd not and: [self peek ~= Character lf]] whileTrue: [self next]]
!
skipBlankAndComments
	[self skipSpaces. self skipComment.
	 self atEnd not and: [self peek = Character lf or: [self peek = Character cr]]] whileTrue: [self next]
!
syntaxError: aString
	^self error: 'TOML line ', line printString, ': ', aString
! !

!TOMLReader class methodsFor: 'reading'!
parse: aString
	^self new setSource: aString; read
!
readFile: aPath
	^self parse: (File readText: aPath)
! !
