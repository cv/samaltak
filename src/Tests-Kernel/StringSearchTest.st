TestCase subclass: #StringSearchTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

StringSearchTest comment: 'The String search primitives (indexOf:startingAt:, indexOfSubCollection:startingAt:) answer what a plain loop answers: ByteStrings, WideStrings and Symbols in every role, every size around the blocks the primitives search by.'!

!StringSearchTest methodsFor: 'running'!
timeLimitMilliseconds
	^120000
! !

!StringSearchTest methodsFor: 'tests'!
testAgainstLoops
	"indexOfSubCollection:startingAt: and indexOf:startingAt: answer what a plain loop answers, for ByteStrings and WideStrings as receiver and argument in every combination: receivers of every size to 70 (the primitives look at 8 or 16 positions at once) and two longer; needles of every size to 20 and longer than the receiver, cut from it at the start, the end and across 8 and 16 positions, some with a middle character changed (first and last still match); characters 0, ASCII, Latin-1 above 127, and above 255 and 65535 with an ASCII low byte; starts from 1 to past the end. Then Symbols, case-insensitive search (whose case folding can make either String wide) and the largest start."
	| random alphabets symbol |
	random := Random seed: 4711.
	alphabets := {
		{$a. $b}.
		{$a. Character value: 0. Character value: 128. Character value: 233. Character value: 255}.
		{$a. $b. Character value: 16r161. Character value: 16r10061}}.
	((0 to: 70) , #(129 200)) do: [:n |
		alphabets do: [:alphabet |
			| haystack strings |
			haystack := (1 to: n) collect: [:i | alphabet at: (random nextInt: alphabet size)].
			strings := self stringsWith: haystack.
			alphabet , {$z. Character value: 16r162} do: [:c |
				({1. 2. random nextInt: n + 2. n. n + 1} select: [:i | i >= 1]) do: [:i |
					self check: strings indexOf: c from: i]].
			0 to: (n + 1 min: 20) do: [:m |
				| last |
				last := n - m + 1.
				m > n ifTrue: [
					self check: strings indexOfSubCollection: ((1 to: m) collect: [:i | alphabet at: (random nextInt: alphabet size)]) from: 1].
				({1. 8. 16. last. random nextInt: (last max: 1)} select: [:o | o between: 1 and: last]) asSet do: [:o |
					| needle |
					needle := haystack copyFrom: o to: o + m - 1.
					({1. o. o + 1} select: [:i | i >= 1]) asSet do: [:i |
						self check: strings indexOfSubCollection: needle from: i].
					m >= 3 ifTrue: [
						| k |
						k := random between: 2 and: m - 1.
						needle at: k put: (alphabet , {$z} detect: [:c | c ~= (needle at: k)]).
						self check: strings indexOfSubCollection: needle from: o]]]]].
	symbol := ((String new: 40 withAll: $a) , 'b') asSymbol.
	{'ab'. #aab. 'b'. (String new: 20 withAll: $a) , 'b'. 'ba'} do: [:p |
		1 to: symbol size + 1 by: 7 do: [:i |
			self assert: (symbol indexOfSubCollection: p startingAt: i) equals: (symbol asArray indexOfSubCollection: p asArray startingAt: i)]].
	symbol := (WideString withAll: {$a. Character value: 16r10061. $b}) asSymbol.
	self assert: (symbol indexOfSubCollection: (String with: (Character value: 16r10061) with: $b) startingAt: 1) equals: 2.
	self assert: ('xab' indexOfSubCollection: symbol startingAt: 1) equals: 0.
	self assert: ('xfoo:bar:' indexOfSubCollection: #foo:bar: startingAt: 1) equals: 2.
	self assert: ('Größe µm' includesSubstring: 'ÖSSE' caseSensitive: false) not.
	self assert: ('Größe µm' includesSubstring: 'ÖßE' caseSensitive: false).
	self assert: ('Größe µm' includesSubstring: (String with: (Character value: 16r39C) with: $M) caseSensitive: false).
	self assert: ('Größe µm' includesSubstring: 'µm' caseSensitive: true).
	self deny: ('Größe µm' includesSubstring: (String with: (Character value: 16r3BC) with: $m) caseSensitive: true).
	self assert: ('abc' indexOfSubCollection: 'b' startingAt: SmallInteger maxVal) equals: 0.
	self assert: ('abc' indexOfSubCollection: '' startingAt: SmallInteger maxVal) equals: SmallInteger maxVal.
	self assert: ('abc' indexOf: $b startingAt: SmallInteger maxVal) equals: 0
! !

!StringSearchTest methodsFor: 'helpers'!
stringsWith: characters
	"characters as a ByteString if they fit, and as a WideString."
	| wide |
	wide := WideString withAll: characters.
	^(characters allSatisfy: [:c | c value < 256])
		ifTrue: [{String withAll: characters. wide}]
		ifFalse: [{wide}]
!
check: strings indexOf: aCharacter from: start
	"strings: the same characters as a ByteString and a WideString, or as a WideString; against a plain loop."
	| expected |
	expected := self indexOf: {aCharacter} in: strings last from: start.
	strings do: [:s |
		self assert: (s indexOf: aCharacter startingAt: start) equals: expected]
!
check: strings indexOfSubCollection: needle from: start
	"needle: an Array of Characters; its Strings in every combination with strings (as for check:indexOf:from:), against a plain loop."
	| expected |
	expected := self indexOf: needle in: strings last from: start.
	(self stringsWith: needle) do: [:p |
		strings do: [:s |
			self assert: (s indexOfSubCollection: p startingAt: start) equals: expected]]
!
indexOf: needle in: characters from: start
	| k |
	needle isEmpty ifTrue: [^start].
	start to: characters size - needle size + 1 do: [:i |
		k := 1.
		[k <= needle size and: [(characters at: i + k - 1) = (needle at: k)]] whileTrue: [k := k + 1].
		k > needle size ifTrue: [^i]].
	^0
! !
