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
	self assert: #foo displayString = 'foo'
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
