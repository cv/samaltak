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
	self deny: 'abc' = 3.
	self assert: ('abc' max: 'abd') = 'abd'
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
	self assert: Character cr value = 13.
	self assert: Character lf value = 10.
	self assert: Character tab value = 9.
	self assert: $a < $b.
	self assert: $a == (Character value: 97).
	self assert: ($a to: $e) size = 5.
	self assert: $é isLetter.
	self assert: $é asUppercase = $É
! !
