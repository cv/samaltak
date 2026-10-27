Object subclass: #CSourceScanner
	instanceVariableNames: ''
	classVariableNames: 'Classes Keywords'
	package: 'Tools'!

CSourceScanner comment: 'I tokenize C source for the File Browser''s highlighting (TextHighlighter scanner:), as Scanner does Smalltalk, in the Smalltalk highlighter''s types (Theme syntaxStyleFor:): #comment (/* */ and //), #keyword (keywords, the standard types, a preprocessor directive''s # and name), #global (string and character literals: the accent); everything between them, white space included, comes as one #identifier token (vm/gen/interpreter.c, 12,681 lines: 11,000 tokens). Simple: no trigraphs, no line continuations.

	CSourceScanner highlight: ''static int x = 1; /* one */'' do: [:type :start :stop | Transcript show: type; cr]'!

!CSourceScanner class methodsFor: 'highlighting'!
highlight: aString do: aBlock
	"Evaluate aBlock with the type, start and stop of every token of aString. Never fails."
	| classes keywords n i plain lineStart c k stop type |
	classes := self classes.
	keywords := self keywords.
	n := aString size.
	i := 1.
	plain := 1.
	lineStart := true.
	[i <= n] whileTrue: [
		c := (aString at: i) value.
		k := c < 128 ifTrue: [classes at: c + 1] ifFalse: [1].
		stop := i.
		type := nil.
		k = 1
			ifTrue: [
				[stop < n and: [(c := (aString at: stop + 1) value) >= 128 or: [(classes at: c + 1) = 1]]] whileTrue: [stop := stop + 1].
				(stop - i < 9 and: [keywords includes: (aString copyFrom: i to: stop)]) ifTrue: [type := #keyword].
				lineStart := false]
			ifFalse: [
				k = 2
					ifTrue: [[stop < n and: [(c := (aString at: stop + 1) value) < 128 and: [(classes at: c + 1) = 2]]] whileTrue: [stop := stop + 1]]
					ifFalse: [
						k = 3
							ifTrue: [lineStart := true]
							ifFalse: [
								k = 4 ifTrue: [
									stop := self literalIn: aString at: i.
									type := #global].
								(k = 5 and: [i < n]) ifTrue: [
									(aString at: i + 1) == $* ifTrue: [
										stop := aString indexOfSubCollection: '*/' startingAt: i + 2.
										stop := stop = 0 ifTrue: [n] ifFalse: [stop + 1].
										type := #comment].
									(aString at: i + 1) == $/ ifTrue: [
										stop := (aString indexOf: Character lf startingAt: i) - 1.
										stop < 0 ifTrue: [stop := n].
										type := #comment]].
								(k = 6 and: [lineStart]) ifTrue: [
									[stop < n and: [(aString at: stop + 1) == $ ]] whileTrue: [stop := stop + 1].
									[stop < n and: [(aString at: stop + 1) isLetter]] whileTrue: [stop := stop + 1].
									type := #keyword].
								lineStart := false]]].
		type isNil ifFalse: [
			plain < i ifTrue: [aBlock value: #identifier value: plain value: i - 1].
			aBlock value: type value: i value: stop.
			plain := stop + 1].
		i := stop + 1].
	plain <= n ifTrue: [aBlock value: #identifier value: plain value: n]
!
literalIn: s at: i
	"The stop of the string or character literal at i: its closing quote, or the end of its line."
	| j c |
	j := i + 1.
	[j <= s size] whileTrue: [
		c := s at: j.
		c == (s at: i) ifTrue: [^j].
		c == Character lf ifTrue: [^j - 1].
		c == $\ ifTrue: [j := j + 1].
		j := j + 1].
	^s size
!
classes
	"By code point below 128: 1 letter, digit or _ (and above 127), 2 white space, 3 line feed, 4 quote, 5 slash, 6 #, 0 the rest."
	| t |
	Classes isNil ifFalse: [^Classes].
	t := Array new: 128 withAll: 0.
	1 to: 128 do: [:i | | ch |
		ch := Character value: i - 1.
		(ch isLetter or: [ch isDigit or: [ch == $_]]) ifTrue: [t at: i put: 1].
		ch isSeparator ifTrue: [t at: i put: 2]].
	t at: 11 put: 3.
	t at: $" value + 1 put: 4; at: $' value + 1 put: 4; at: $/ value + 1 put: 5; at: $# value + 1 put: 6.
	^Classes := t
!
keywords
	^Keywords ifNil: [Keywords := Set withAll: #('auto' 'break' 'case' 'char' 'const' 'continue' 'default' 'do' 'double' 'else' 'enum' 'extern' 'float' 'for' 'goto' 'if' 'inline' 'int' 'long' 'register' 'restrict' 'return' 'short' 'signed' 'sizeof' 'static' 'struct' 'switch' 'typedef' 'union' 'unsigned' 'void' 'volatile' 'while' '_Bool' 'bool' 'true' 'false' 'NULL' 'size_t' 'int8_t' 'int16_t' 'int32_t' 'int64_t' 'uint8_t' 'uint16_t' 'uint32_t' 'uint64_t' 'intptr_t' 'uintptr_t')]
! !
