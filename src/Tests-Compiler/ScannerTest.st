TestCase subclass: #ScannerTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Compiler'!

ScannerTest comment: 'I test the Scanner, including its syntax-highlighting interface.'!

!ScannerTest methodsFor: 'helpers'!
typesOf: aString
	^((Scanner highlightTokens: aString) collect: [:each | each first]) asArray
!
tokensOf: aString
	| scanner result |
	scanner := Scanner on: aString.
	result := OrderedCollection new.
	[scanner nextToken == #eof] whileFalse: [
		result add: (Array with: scanner tokenType with: scanner tokenValue)].
	^result asArray
! !

!ScannerTest methodsFor: 'tests'!
testTokens
	self assert: (self tokensOf: 'foo: x ^bar')
		equals: {{#keyword. 'foo:'}. {#identifier. 'x'}. {#return. '^'}. {#identifier. 'bar'}}.
	self assert: (self tokensOf: 'x:=3') equals: {{#identifier. 'x'}. {#assignment. ':='}. {#number. 3}}.
	self assert: (self tokensOf: 'a >= b') equals: {{#identifier. 'a'}. {#binary. '>='}. {#identifier. 'b'}}.
	self assert: (self tokensOf: 'x--1') equals: {{#identifier. 'x'}. {#binary. '-'}. {#binary. '-'}. {#number. 1}}
!
testIntervals
	| triples |
	triples := Scanner highlightTokens: 'foo: x ^#(a 1)'.
	self assert: triples first equals: #(#keyword 1 4).
	self assert: (triples at: 2) equals: #(#identifier 6 6).
	self assert: (triples at: 3) equals: #(#return 8 8).
	self assert: (triples at: 4) equals: #(#literalArrayStart 9 10).
	self assert: (triples at: 5) equals: #(#symbol 11 11).
	self assert: (triples at: 6) equals: #(#number 13 13).
	self assert: (triples at: 7) equals: #(#punctuation 14 14)
!
testHighlightTypes
	self assert: (self typesOf: 'x := Foo self super true false nil thisContext')
		equals: #(#identifier #assignment #global #self #super #true #false #nil #thisContext).
	self assert: (self typesOf: '''s'' "c" $c #sym 3 , ;')
		equals: #(#string #comment #character #symbol #number #binary #punctuation).
	self assert: (self typesOf: '#(foo #bar baz: (1 x) #[1 2] nil) x')
		equals: #(#literalArrayStart #symbol #symbol #symbol #literalArrayStart #number #symbol #punctuation #literalArrayStart #number #number #punctuation #nil #punctuation #identifier)
!
testHighlightTolerance
	self assert: (Scanner highlightTokens: '''abc') asArray equals: {#(#string 1 4)}.
	self assert: (Scanner highlightTokens: 'x "abc') asArray equals: {#(#identifier 1 1). #(#comment 3 6)}.
	self assert: (self typesOf: 'x `') equals: #(#identifier #error).
	self assert: (self typesOf: '#(') equals: #(#literalArrayStart).
	self assert: (self typesOf: '$') equals: #(#error).
	self assert: (self typesOf: '#') equals: #(#error).
	self assert: (self typesOf: '16r') equals: #(#error).
	self assert: (self typesOf: '') equals: #()
!
testUnicodeNames
	"Identifiers start with a letter of any script and go on with letters, digits and marks; non-ASCII math symbols are binary characters; non-ASCII White_Space and U+FEFF separate; emoji are errors outside strings and comments."
	| nbsp acute arabicThree |
	nbsp := String with: (Character value: 160).
	acute := String with: (Character value: 769).
	arabicThree := String with: (Character value: 1635).
	self assert: (self tokensOf: 'größe := 3') equals: {{#identifier. 'größe'}. {#assignment. ':='}. {#number. 3}}.
	self assert: (self tokensOf: 'λ 日本 _x Größe') equals: {{#identifier. 'λ'}. {#identifier. '日本'}. {#identifier. '_x'}. {#identifier. 'Größe'}}.
	self assert: (self tokensOf: 'x größe: 1 von: 2') equals: {{#identifier. 'x'}. {#keyword. 'größe:'}. {#number. 1}. {#keyword. 'von:'}. {#number. 2}}.
	self assert: (self tokensOf: '#größe #größe:von: #× #≠=') equals: {{#symbol. 'größe' asSymbol}. {#symbol. 'größe:von:' asSymbol}. {#symbol. '×' asSymbol}. {#symbol. '≠=' asSymbol}}.
	self assert: (self tokensOf: '3 × 4 ≤ 5') equals: {{#number. 3}. {#binary. '×'}. {#number. 4}. {#binary. '≤'}. {#number. 5}}.
	self assert: (self tokensOf: 'e' , acute , 'x x' , arabicThree) equals: {{#identifier. 'e' , acute , 'x'}. {#identifier. 'x' , arabicThree}}.
	self assert: (self tokensOf: 'a' , nbsp , 'b' , (String with: (Character value: 12288)) , 'c' , (String with: (Character value: 65279)) , 'd')
		equals: {{#identifier. 'a'}. {#identifier. 'b'}. {#identifier. 'c'}. {#identifier. 'd'}}.
	self assert: (self typesOf: 'a := 😀') equals: #(#identifier #assignment #error).
	self assert: (self typesOf: 'a😀') equals: #(#identifier #error).
	self assert: (self typesOf: acute , 'a') equals: #(#error #identifier).
	self assert: (self typesOf: arabicThree) equals: #(#error).
	self assert: (self typesOf: '''😀'' "😀" $😀') equals: #(#string #comment #character).
	self assert: (self typesOf: 'Größe größe Λ λ') equals: #(#global #identifier #global #identifier)
!
testNumbers
	self assert: (self tokensOf: '16r1F 2r101 1e2 2.5 1.5e1') equals: {{#number. 31}. {#number. 5}. {#number. 100}. {#number. 2.5}. {#number. 15.0}}.
	self assert: (self tokensOf: '1. 2') equals: {{#number. 1}. {#period. '.'}. {#number. 2}}
! !
