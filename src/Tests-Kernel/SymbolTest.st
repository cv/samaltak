TestCase subclass: #SymbolTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

SymbolTest comment: 'Tests that Symbols are unique, read-only and behave like Strings.'!

!SymbolTest methodsFor: 'tests'!
testUniqueness
	| s |
	s := (String with: $f with: $o with: $o) , 'Bar'.
	self assert: s asSymbol == #fooBar.
	self assert: (Symbol intern: 'fooBar') == #fooBar.
	self assert: #fooBar asSymbol == #fooBar.
	self assert: 'aNewSymbolNobodyUsed' asSymbol == 'aNewSymbolNobodyUsed' asSymbol.
	self assert: (Symbol lookup: 'zzzNoSuchSymbolzzz') isNil.
	self assert: (Symbol lookup: 'printString') == #printString
!
testEqualityWithStrings
	"A Symbol equals a String with its characters both ways round (Squeak, Pharo), so they find each other in Sets and Dictionaries; two Symbols are equal only if identical."
	| set dictionary |
	self assert: #abc = 'abc'.
	self assert: 'abc' = #abc.
	self assert: #abc = 'abc' asWideString.
	self deny: #abc = 'abd'.
	self deny: #abc = #abd.
	self deny: #abc = 3.
	self assert: #abc hash equals: 'abc' hash.
	set := Set new.
	set add: #abc.
	self assert: (set includes: 'abc').
	set := Set new.
	set add: 'abc'.
	self assert: (set includes: #abc).
	dictionary := Dictionary new.
	dictionary at: #abc put: 1.
	self assert: (dictionary at: 'abc' ifAbsent: [nil]) equals: 1.
	dictionary := Dictionary new.
	dictionary at: 'abc' put: 2.
	self assert: (dictionary at: #abc ifAbsent: [nil]) equals: 2
!
testProperties
	self assert: #at:put: numArgs = 2.
	self assert: #+ numArgs = 1.
	self assert: #size numArgs = 0.
	self assert: #at:put: isKeyword.
	self assert: #+ isBinary.
	self assert: #size isUnary.
	self assert: #at:put: keywords = #('at:' 'put:').
	self assert: #foo size = 3.
	self assert: #foo first = $f.
	self assert: #foo isSymbol.
	self assert: #foo isString
!
testPrinting
	self assert: #foo printString = '#foo'.
	self assert: #at:put: printString = '#at:put:'.
	self assert: #+ printString = '#+'.
	self assert: 'hello world' asSymbol printString = '#''hello world'''.
	self assert: 'größe' asSymbol printString = '#größe'.
	self assert: 'größe:von:' asSymbol printString = '#größe:von:'.
	self assert: '×' asSymbol printString = '#×'.
	self assert: '😀' asSymbol printString = '#''😀'''.
	self assert: #foo displayString = 'foo'
!
testPrintStringReadsBack
	"Every Symbol prints as a literal the compiler reads back as the same Symbol: unquoted where the Scanner allows, as names of any script, marks and digits included, or binary selectors with math symbols."
	| symbols |
	symbols := #('foo' 'at:put:' '+' '->' 'hello world' '' 'a:b' 'a:' '_x' 'x_1' 'größe' 'größe:' 'größe:von:' 'λ' 'λ1' '日本' 'Größe'
		'×' '≠' '÷' '≤=' '+×' '😀' 'a😀' '٣x' 'x٣' '3x' 'é' 'e' ':' '#foo' 'a b:' 'ab:c:' '!!' '|' '||' '++' 'a-b') asOrderedCollection.
	symbols add: 'e' , (String with: (Character value: 769)); add: (String with: (Character value: 769)) , 'e'; add: 'a' , (String with: (Character value: 160)) , 'b'.
	symbols do: [:each |
		| symbol |
		symbol := each asSymbol.
		self assert: (Compiler evaluate: symbol printString) == symbol].
	#('größe' 'größe:' 'λ1' '日本' 'x٣' '×' '≠' '+×') do: [:each |
		self assert: each asSymbol printString equals: '#' , each].
	#('😀' 'a😀' '٣x' 'a b:') do: [:each |
		self assert: (each asSymbol printString first: 2) equals: '#'''].
	self assert: 'größe:' numArgs equals: 1.
	self assert: 'größe:von:' numArgs equals: 2.
	self assert: 'größe' numArgs equals: 0.
	self assert: '×' numArgs equals: 1.
	self assert: '😀' numArgs equals: -1.
	self assert: '×' asSymbol isBinary
!
testImmutability
	self assert: #foo isReadOnlyObject.
	self should: [#foo at: 1 put: $x] raise: ModificationForbidden.
	self assert: #foo copy == #foo.
	self should: [Symbol new: 3] raise: Error
!
testEquality
	self assert: #foo = #foo.
	self deny: #foo = #bar.
	self assert: #foo hash = 'foo' hash.
	self assert: (#foo , 'bar') = 'foobar'.
	self assert: (#foo , 'bar') class == ByteString
!
testAsBlock
	self assert: (#(1 2 3) collect: #negated) = #(-1 -2 -3).
	self assert: (#size value: 'abc') = 3.
	self assert: (#(3 4) inject: 0 into: #+) = 7
! !
