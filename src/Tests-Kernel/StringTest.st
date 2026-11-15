TestCase subclass: #StringTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

StringTest comment: 'Tests String and Character protocol, including wide strings and UTF-8.'!

!StringTest methodsFor: 'tests'!
testComparing
	self assert: 'abc' = 'abc'.
	self deny: 'abc' = 'abd'.
	self deny: 'abc' = 'ab'.
	self assert: 'abc' < 'abd'.
	self assert: 'ab' < 'abc'.
	self assert: 'B' < 'a'.
	self assert: 'abc' hash = 'abc' copy hash.
	self assert: 'abc' hash = #abc hash.
	self assert: 'abc' = #abc.
	self assert: ('abc' sameAs: 'ABC').
	self deny: ('abc' sameAs: 'ABCD').
	self deny: ('abc' sameAs: 'abd').
	self assert: ('ÜBER' sameAs: 'über').
	self assert: ('Apple' caseInsensitiveLessOrEqual: 'apple').
	self assert: ('apple' caseInsensitiveLessOrEqual: 'BANANA').
	self deny: ('banana' caseInsensitiveLessOrEqual: 'APPLE').
	self assert: ('AB' caseInsensitiveLessOrEqual: 'abc').
	self deny: ('ABC' caseInsensitiveLessOrEqual: 'ab').
	self assert: ('a_' caseInsensitiveLessOrEqual: 'B') = ('a_' asLowercase <= 'B' asLowercase).
	self assert: ('Z' caseInsensitiveLessOrEqual: '[') = ('z' <= '[').
	self deny: 'abc' = 3.
	self assert: ('abc' max: 'abd') = 'abd'
!
testCompare
	"compareWith: answers -1, 0 or 1 by code points; compare: (ignoring case) and compare:caseSensitive: answer 1, 2 or 3, as in Squeak and Pharo."
	self assert: ('abc' compareWith: 'abd') equals: -1.
	self assert: ('abc' compareWith: 'abc' asWideString) equals: 0.
	self assert: ('abd' compareWith: #abc) equals: 1.
	self assert: ('B' compareWith: 'a') equals: -1.
	self assert: ('aa' compare: 'ab') equals: 1.
	self assert: ('aa' compare: 'aa') equals: 2.
	self assert: ('ab' compare: 'aa') equals: 3.
	self assert: ('abc' compare: 'ABC') equals: 2.
	self assert: ('B' compare: 'a') equals: 3.
	self assert: ('ÜBER' compare: 'über') equals: 2.
	self assert: ('abc' compare: 'ABC' caseSensitive: true) equals: 3.
	self assert: ('abc' compare: 'ABC' caseSensitive: false) equals: 2.
	self assert: ('B' compare: 'a' caseSensitive: true) equals: 1.
	self assert: ('abc' compare: 'abc' caseSensitive: true) equals: 2
!
testCaseInsensitiveCompare
	"The primitive (byte strings and Symbols) and the loop (wide strings) answer what compareWith: answers for caseFolded copies: Latin-1 letters, × ÷ ß ÿ µ (folding to Greek mu), Ÿ (376), whose lowercase is ÿ, Greek."
	| strings |
	strings := #('' 'a' 'A' 'ab' 'AB' 'abc' 'ABD' 'abcd' 'Z' 'z' '[' '_' '`' '@' 'a_' 'B' 'über' 'ÜBER' 'Über' 'ü' 'Ü' 'À' 'à' 'Þ' 'þ' '×' '÷' 'ß' 'ÿ' 'µ' 'aµ' 'aü' 'ab×' 'abÿ' #abc #ABC 'μ' 'Μ' 'ΟΔΟΣ' 'οδος' 'οδοσ') asOrderedCollection.
	strings add: 'Ÿ'; add: 'aŸ'; add: (String with: (Character value: 300)); add: 'ÜBER' , (String with: (Character value: 300)).
	strings do: [:a | strings do: [:b |
		self assert: (a caseInsensitiveCompare: b) equals: (a caseFolded compareWith: b caseFolded)]]
!
testUnicodeCase
	"Simple (one-to-one) case mappings and caseless comparison by simple case folding, beyond Latin-1."
	self assert: 'ΑΒΓ δ' asLowercase equals: 'αβγ δ'.
	self assert: 'Привет, мир' asUppercase equals: 'ПРИВЕТ, МИР'.
	self assert: 'Բարեւ' asUppercase equals: 'ԲԱՐԵՒ'.
	self assert: 'straße' asUppercase equals: 'STRAßE'.
	self assert: 'ǆemal' capitalized first value equals: 453.
	self assert: 'µ' asUppercase equals: (String with: (Character value: 924)).
	self assert: 'aµ' asUppercase class equals: WideString.
	self assert: 'ÿ' asUppercase equals: (String with: (Character value: 376)).
	self assert: 'aµ' asSymbol asUppercase class equals: WideString.
	self assert: 'µ' caseFolded equals: 'μ'.
	self assert: ('µ' sameAs: 'μ').
	self assert: ('µ' sameAs: 'Μ').
	self assert: ('µ' caseInsensitiveCompare: 'μ') equals: 0.
	self assert: ('ΟΔΟΣ' sameAs: 'οδος').
	self assert: ('ΟΔΟΣ' sameAs: 'οδοσ').
	self assert: ('ПРИВЕТ' sameAs: 'привет').
	self deny: ('ПРИВЕТ' sameAs: 'пока').
	self assert: ('ſ' sameAs: 'S').
	self assert: ('日本語' sameAs: '日本語').
	self assert: ('Привет, мир' includesSubstring: 'МИР' caseSensitive: false).
	self deny: ('Привет, мир' includesSubstring: 'МИР' caseSensitive: true).
	self assert: ('*.ΤΧΤ' match: 'αβγ.τχτ').
	self assert: ('ÜBER*' match: 'überall')
!
testCase
	self assert: 'Hello World' asUppercase = 'HELLO WORLD'.
	self assert: 'Hello World' asLowercase = 'hello world'.
	self assert: 'hello' capitalized = 'Hello'.
	self assert: 'über' asUppercase = 'ÜBER'.
	self assert: #hello capitalized = 'Hello'.
	self assert: $a asUppercase = $A.
	self assert: $Z asLowercase = $z
!
testSubstrings
	self assert: 'the quick  brown fox' substrings = #('the' 'quick' 'brown' 'fox').
	self assert: ('a,b,,c' substrings: ',') = #('a' 'b' 'c').
	self assert: ('a,b,,c' splitOn: ',') = #('a' 'b' '' 'c').
	self assert: ('one
two' lines) = #('one' 'two').
	self assert: (', ' join: #('a' 'b' 'c')) = 'a, b, c'.
	self assert: 'at:put:' keywords = #('at:' 'put:').
	self assert: 'at:put:' numArgs = 2.
	self assert: '+' numArgs = 1.
	self assert: 'size' numArgs = 0
!
testCasePrimitives
	"asUppercase and asLowercase of byte strings and Symbols (the primitives) answer what the Character loop answers: every Latin-1 code, µ and ÿ going up to wide characters, wide strings."
	| all wide |
	all := String new: 256.
	1 to: 256 do: [:i | all at: i put: (Character value: i - 1)].
	self assert: all asUppercase equals: (all collect: [:c | c asUppercase]).
	self assert: all asLowercase equals: (all collect: [:c | c asLowercase]).
	self assert: (all reject: [:c | c value = 181 or: [c value = 255]]) asUppercase class equals: ByteString.
	self assert: all asUppercase class equals: WideString.
	self assert: all asUppercase last value equals: 376.
	self assert: (all asUppercase at: 182) value equals: 924.
	self assert: all caseFolded equals: (all collect: [:c | c caseFolded]).
	self assert: (all reject: [:c | c value = 181]) caseFolded class equals: ByteString.
	self assert: #abcXYZ asUppercase equals: 'ABCXYZ'.
	self assert: #abcXYZ asLowercase class equals: ByteString.
	self assert: '' asUppercase equals: ''.
	wide := String with: $a with: (Character value: 955) with: $Z.
	self assert: wide asUppercase equals: (String with: $A with: (Character value: 923) with: $Z).
	self assert: wide asLowercase equals: (String with: $a with: (Character value: 955) with: $z)
!
testIndexOfPrimitives
	"indexOf:startingAt: and indexOfSubCollection:startingAt: (primitives for Strings) answer what the loops of SequenceableCollection answer: byte, wide and Symbol receivers and arguments, starts past the end, arguments that are not Characters or Strings."
	| lambda strings chars patterns |
	lambda := Character value: 955.
	strings := {'abcabc'. #abcabc. 'abc' , (String with: lambda) , 'abc'. ''. 'a'}.
	chars := {$a. $c. lambda. $z. (Character value: 300). 97. nil}.
	patterns := {'bc'. 'abc'. #ca. 'c' , (String with: lambda). (String with: lambda). 'abcabcx'. ''. {$b. $c}. 'x'}.
	strings do: [:s |
		chars do: [:c |
			0 to: s size + 2 do: [:i |
				self
					assert: (i = 0 ifTrue: [s indexOf: c] ifFalse: [s indexOf: c startingAt: i])
					equals: (i = 0
						ifTrue: [(s asArray indexOf: c) ]
						ifFalse: [s asArray indexOf: c startingAt: i])]].
		patterns do: [:p |
			1 to: s size + 2 do: [:i |
				self
					assert: (s indexOfSubCollection: p startingAt: i)
					equals: (s asArray indexOfSubCollection: p asArray startingAt: i)]]].
	self should: ['abc' indexOf: $a startingAt: 0] raise: Error.
	self assert: ('hello' indexOf: $l ifAbsent: [0]) equals: 3.
	self assert: ('hello' indexOf: $z ifAbsent: [#none]) equals: #none.
	self assert: ('hello' includes: $o).
	self deny: ('hello' includes: 111).
	self assert: ('banana' occurrencesOf: $a) equals: 3.
	self assert: ('banana' occurrencesOf: 97) equals: 0
!
testLines
	| cr lf |
	cr := String with: Character cr.
	lf := String with: Character lf.
	self assert: '' lines equals: #().
	self assert: 'a' lines equals: #('a').
	self assert: ('a' , lf) lines equals: #('a').
	self assert: ('a' , cr , lf , 'b') lines equals: #('a' 'b').
	self assert: ('a' , lf , cr , 'b') lines equals: #('a' '' 'b').
	self assert: ('a' , cr , cr , 'b' , lf , lf) lines equals: #('a' '' 'b' '').
	self assert: (lf , 'a' , cr , 'b' , cr , lf , 'c') lines equals: #('' 'a' 'b' 'c')
!
testSearching
	self assert: ('hello world' includesSubstring: 'o w').
	self deny: ('hello world' includesSubstring: 'xyz').
	self assert: ('hello' beginsWith: 'he').
	self assert: ('hello' endsWith: 'llo').
	self deny: ('hello' beginsWith: 'lo').
	self assert: ('hello' indexOf: $l) = 3.
	self assert: ('hello world' indexOfSubCollection: 'world') = 7.
	self assert: ('hello' occurrencesOf: $l) = 2.
	self assert: ('*.st' match: 'Object.st').
	self deny: ('*.st' match: 'Object.txt')
!
testCopying
	self assert: '  hi there  ' trimBoth = 'hi there'.
	self assert: '  hi' trimLeft = 'hi'.
	self assert: 'hi  ' trimRight = 'hi'.
	self assert: ('hello world' copyReplaceAll: 'o' with: '0') = 'hell0 w0rld'.
	self assert: ('aaa' copyReplaceAll: 'a' with: 'bb') = 'bbbbbb'.
	self assert: 'abc' reversed = 'cba'.
	self assert: 'abc' , 'def' = 'abcdef'.
	self assert: ('hello' copyFrom: 2 to: 4) = 'ell'.
	self assert: ('hello' copyWithout: $l) = 'heo'.
	self assert: ('abc' collect: [:c | c asUppercase]) = 'ABC'.
	self assert: ('a1b2' select: [:c | c isDigit]) = '12'.
	self assert: ('7' padLeftTo: 3 with: $0) = '007'.
	self assert: ('7' padLeftTo: 3) = '  7'.
	self assert: ('7' padRightTo: 3) = '7  '.
	self assert: ('7' padRightTo: 3 with: $.) = '7..'.
	self assert: 'hello' asSymbol == #hello.
	self assert: 'cba' sorted = 'abc'
!
testFormat
	self assert: ('{1} + {2} = {3}' format: #(1 2 3)) = '1 + 2 = 3'.
	self assert: ('Hello {1}!!' format: {'World'}) = 'Hello World!!'.
	self assert: ('{a}-{b}' format: (Dictionary new at: 'a' put: 1; at: 'b' put: 2; yourself)) = '1-2'
!
testPrinting
	self assert: 'it''s' printString = '''it''''s'''.
	self assert: 'it''s' displayString = 'it''s'.
	self assert: 'abc' printString size = 5.
	self assert: $a printString = '$a'.
	self assert: Character space printString = 'Character space'.
	self assert: $a displayString = 'a'.
	self assert: 'abc' storeString = '''abc'''
!
testConversion
	self assert: '42' asNumber = 42.
	self assert: '3.5' asNumber = 3.5.
	self assert: 'x12y' asInteger = 12.
	self assert: '٣4' asInteger = 34.
	self assert: 'x-١٢٣' asInteger = -123.
	self assert: '٣' asNumber isNil.
	self assert: (Number readFrom: '1٣') = 1.
	self assert: (Integer readFrom: '٣' ifFail: [nil]) isNil.
	self assert: 'none' asInteger isNil.
	self assert: 'abc' asSymbol class == ByteSymbol.
	self assert: #abc asString class == ByteString.
	self assert: #abc asString = 'abc'.
	self assert: 'abc' asArray = #($a $b $c).
	self assert: (String new: 3) size = 3.
	self assert: (String new: 2 withAll: $z) = 'zz'.
	self assert: (String with: $a with: $b) = 'ab'
!
testStreamContents
	| s |
	s := String new: 2 streamContents: [:stream |
		stream nextPutAll: 'Hello'; nextPut: $,; space; print: 42; tab; << 'x'; << 7].
	self assert: s = ('Hello, 42', (String with: Character tab), 'x7').
	self assert: (String streamContents: [:stream | 1 to: 1000 do: [:i | stream print: i]]) size = 2893
!
testWideStrings
	| s lambda |
	lambda := Character value: 955.
	s := 'abc' copy.
	self assert: s class == ByteString.
	s at: 2 put: lambda.
	self assert: s class == WideString.
	self assert: (s at: 2) == lambda.
	self assert: s size = 3.
	self assert: s first = $a.
	self assert: s = (String with: $a with: lambda with: $c).
	self assert: s hash = (String with: $a with: lambda with: $c) hash.
	self assert: ('x' , s) class == WideString.
	self assert: ('x' , s) size = 4.
	self assert: (s copyFrom: 2 to: 3) = (String with: lambda with: $c).
	self assert: (String with: lambda) asSymbol class == WideSymbol.
	self assert: (String with: lambda) asSymbol == (String with: lambda) asSymbol.
	self assert: s utf8Encoded size = 4.
	self assert: s utf8Encoded utf8Decoded = s.
	self assert: (String streamContents: [:stream | stream nextPutAll: 'ab'; nextPut: lambda]) class == WideString.
	self assert: (String with: lambda) asUppercase size = 1
!
testUtf8DecodingIllFormed
	"Each maximal ill-formed subpart (Unicode 3.9, as WHATWG) decodes to one U+FFFD."
	#(
		#[16r80] #(16rFFFD)
		#[16rBF 16r41] #(16rFFFD 16r41)
		#[16rC0 16rAF] #(16rFFFD 16rFFFD)
		#[16rC1 16rBF] #(16rFFFD 16rFFFD)
		#[16rE0 16r80 16rAF] #(16rFFFD 16rFFFD 16rFFFD)
		#[16rF0 16r80 16r80] #(16rFFFD 16rFFFD 16rFFFD)
		#[16rF1 16r80 16r80] #(16rFFFD)
		#[16rF1 16r80 16r80 16r41] #(16rFFFD 16r41)
		#[16rED 16rA0 16r80] #(16rFFFD 16rFFFD 16rFFFD)
		#[16rED 16r9F 16rBF] #(16rD7FF)
		#[16rF4 16r90 16r80 16r80] #(16rFFFD 16rFFFD 16rFFFD 16rFFFD)
		#[16rF4 16r8F 16rBF 16rBF] #(16r10FFFF)
		#[16rF5 16r80] #(16rFFFD 16rFFFD)
		#[16rFE 16rFF] #(16rFFFD 16rFFFD)
		#[16rF8 16r88 16r80 16r80 16r80] #(16rFFFD 16rFFFD 16rFFFD 16rFFFD 16rFFFD)
		#[16rE9 16r61] #(16rFFFD 16r61)
		#[16rC2 16rC2 16rA9] #(16rFFFD 16rA9)
		#[16rE2 16r82] #(16rFFFD)
		#[16rC3] #(16rFFFD)
		#[16rE2 16r82 16rAC] #(16r20AC)
		#[16r61 16rF0 16r9F 16r98 16r80 16r62] #(16r61 16r1F600 16r62))
			pairsDo: [:bytes :codePoints |
				self assert: (bytes utf8Decoded asArray collect: [:c | c value]) equals: codePoints].
	self assert: #[16rC3 16rA9] utf8Decoded class == ByteString.
	self assert: #[16r61 16r62] utf8Decoded equals: 'ab'.
	self assert: #[] utf8Decoded equals: ''
!
testUtf8RoundTrips
	#(0 16r7F 16r80 16r7FF 16r800 16rFFFF 16r10000 16r1F600 16r10FFFF) with: #(1 1 2 2 3 3 4 4 4) do: [:cp :n |
		| s |
		s := String with: (Character value: cp).
		self assert: s utf8Encoded size equals: n.
		self assert: s utf8Encoded utf8Decoded equals: s].
	"A surrogate has no UTF-8: it is encoded as U+FFFD."
	self assert: (String with: (Character value: 16rD800)) utf8Encoded equals: #[16rEF 16rBF 16rBD].
	self assert: (String with: $a with: (Character value: 16rDCFF)) utf8Encoded equals: #[16r61 16rEF 16rBF 16rBD]
!
testCharacterValueRange
	self assert: (Character value: 16r10FFFF) value equals: 16r10FFFF.
	self assert: (Character value: 16rD800) value equals: 16rD800.
	self should: [Character value: 16r110000] raise: Error.
	self should: [Character value: -1] raise: Error.
	self should: [Character value: 16r3FFFFFFF] raise: Error
!
testWideStringsAreCreatedWide
	"Constructors, copies and streams choose WideString up front instead of widening with becomeForward."
	| lambda |
	lambda := Character value: 955.
	self assert: (String with: lambda) class == WideString.
	self assert: (String with: $a with: lambda) class == WideString.
	self assert: (String with: $a) class == ByteString.
	self assert: (String new: 2 withAll: lambda) = (String with: lambda with: lambda).
	self assert: lambda asString class == WideString.
	self assert: ('ab' copyWith: lambda) = (String with: $a with: $b with: lambda).
	self assert: ('abc' copyReplaceFrom: 2 to: 2 with: lambda asString) = (String with: $a with: lambda with: $c).
	self assert: (String streamContents: [:s | s nextPutAll: (Array with: $a with: lambda)]) size = 2.
	self assert: (Time microsecondsToRun: [100 timesRepeat: [String with: lambda. String streamContents: [:s | s nextPut: lambda]]]) < 100000
!
testCharacters
	self assert: $a value = 97.
	self assert: (Character value: 65) = $A.
	self assert: $a isVowel.
	self deny: $b isVowel.
	self assert: $a isLetter.
	self assert: $5 isDigit.
	self assert: $5 digitValue = 5.
	self assert: $F digitValue = 15.
	self assert: (Character digitValue: 11) = $B.
	self assert: Character space isSeparator.
	self assert: ((0 to: 255) select: [:v | (Character value: v) isSeparator]) asArray equals: #(9 10 12 13 32).
	self assert: Character separators asSet equals: (String with: Character space with: Character tab with: Character cr with: Character lf with: Character newPage) asSet.
	self assert: ((0 to: 255) select: [:v | (Character value: v) isWhiteSpace]) asArray equals: #(9 10 11 12 13 32 133 160).
	self assert: (String with: (Character value: 160) with: $a with: Character tab) trimBoth equals: (String with: (Character value: 160) with: $a).
	self assert: (String with: (Character value: 12288)) isAllSeparators not.
	self assert: (Character value: 160) printString equals: '(Character value: 160)'.
	self assert: Character cr value = 13.
	self assert: Character lf value = 10.
	self assert: Character tab value = 9.
	self assert: $a < $b.
	self assert: $a == (Character value: 97).
	self assert: ($a to: $e) size = 5.
	self assert: $é isLetter.
	self assert: $é asUppercase = $É
! !
