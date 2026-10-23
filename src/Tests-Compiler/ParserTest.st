TestCase subclass: #ParserTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Compiler'!

ParserTest comment: 'I test the Parser''s syntax tree.'!

!ParserTest methodsFor: 'tests'!
testMethodPattern
	| node |
	node := Parser new parseMethod: 'foo: a bar: b ^a + b'.
	self assert: node selector == #foo:bar:.
	self assert: (node arguments collect: [:each | each name]) asArray equals: #('a' 'b').
	self assert: node body statements size equals: 1.
	self assert: node body statements first isReturn.
	node := Parser new parseMethod: '+ other ^self'.
	self assert: node selector == #+.
	node := Parser new parseMethod: 'size'.
	self assert: node selector == #size.
	self assert: node body statements isEmpty
!
testIntervals
	| node return message |
	node := Parser new parseMethod: 'foo ^(self bar) baz: 1'.
	return := node body statements first.
	self assert: return start equals: 5.
	self assert: return stop equals: 22.
	message := return value.
	self assert: message selector == #baz:.
	self assert: message start equals: 6.
	self assert: message stop equals: 22.
	self assert: message receiver start equals: 7.
	self assert: message receiver stop equals: 14
!
testExpression
	| node |
	node := Parser new parseExpression: '| t | t := 3. t'.
	self assert: node isDoIt.
	self assert: node selector == #DoIt.
	self assert: node temporaries size equals: 1.
	self assert: node body statements size equals: 2.
	self assert: node body statements first isAssignment
!
testPragmas
	| node |
	node := Parser new parseMethod: 'foo <primitive: ''basicNew'' error: code> <bar: 1> | t | ^t'.
	self assert: node primitive equals: 'basicNew'.
	self assert: node errorCodeVariable name equals: 'code'.
	self assert: node pragmas size equals: 1.
	self assert: node pragmas first selector == #bar:.
	self assert: node temporaries size equals: 1.
	node := Parser new parseMethod: 'foo | t | <primitive: 7> ^t'.
	self assert: node primitive equals: 7
!
testCascade
	| node cascade |
	node := Parser new parseExpression: 'Transcript show: 1; cr; show: 2 + 3'.
	cascade := node body statements first.
	self assert: cascade isCascade.
	self assert: cascade messages size equals: 3.
	self assert: (cascade messages collect: [:each | each selector]) asArray equals: #(#show: #cr #show:).
	cascade messages do: [:each | self assert: each receiver == cascade receiver]
!
testBlock
	| block |
	block := (Parser new parseExpression: '[:a :b | | t | t := a. b]') body statements first.
	self assert: block isBlock.
	self assert: (block arguments collect: [:each | each name]) asArray equals: #('a' 'b').
	self assert: (block temporaries collect: [:each | each name]) asArray equals: #('t').
	self assert: block statements size equals: 2
!
testSyntaxErrorIsSignaled
	| e |
	e := [Parser new parseExpression: '3 + '. nil] on: SyntaxError do: [:ex | ex return: ex].
	self assert: e notNil.
	self assert: e position equals: 5
! !
