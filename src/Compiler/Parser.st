Object subclass: #Parser
	instanceVariableNames: 'source scanner hereType hereValue hereStart hereStop peekType peekValue peekStart peekStop hasPeek prevStop'
	classVariableNames: ''
	package: 'Compiler'!

Parser comment: 'I parse Smalltalk source into a tree of ParseNodes. Errors are signaled as SyntaxError with the source position.

	Parser new parseMethod: ''foo ^1''
	Parser new parseExpression: ''| a | a := 3. a + 4'''!

!Parser class methodsFor: 'parsing'!
parseExpression: aString
	^self new parseExpression: aString
!
parseMethod: aString
	^self new parseMethod: aString
! !

!Parser methodsFor: 'parsing'!
parseExpression: aString
	"Parse a do-it: optional temporaries and a statement sequence. Answer a MethodNode with selector #DoIt."
	| node |
	self init: aString.
	node := MethodNode new.
	node source: aString; selector: #DoIt; arguments: #(); beDoIt.
	node temporaries: (hereType == #bar ifTrue: [self parseTemporaries] ifFalse: [#()]).
	node body: (self parseStatementsUntil: #eof).
	node start: 1 stop: aString size.
	^node
!
parseMethod: aString
	| node |
	self init: aString.
	node := MethodNode new.
	node source: aString.
	self parseMessagePatternInto: node.
	self parseMethodBodyInto: node.
	node start: 1 stop: aString size.
	^node
! !

!Parser methodsFor: 'private'!
init: aString
	source := aString.
	scanner := Scanner on: aString.
	hasPeek := false.
	hereStop := 0.
	prevStop := 0.
	self advance
!
advance
	prevStop := hereStop.
	hasPeek
		ifTrue: [
			hasPeek := false.
			hereType := peekType.
			hereValue := peekValue.
			hereStart := peekStart.
			hereStop := peekStop]
		ifFalse: [
			scanner nextToken.
			hereType := scanner tokenType.
			hereValue := scanner tokenValue.
			hereStart := scanner tokenStart.
			hereStop := scanner tokenStop].
	hereType == #error ifTrue: [self syntaxError: hereValue at: hereStart]
!
peek
	hasPeek ifFalse: [
		scanner nextToken.
		peekType := scanner tokenType.
		peekValue := scanner tokenValue.
		peekStart := scanner tokenStart.
		peekStop := scanner tokenStop.
		hasPeek := true].
	^peekType
!
syntaxError: aString at: anInteger
	^SyntaxError signal: aString at: anInteger in: source
!
expected: aString
	^self syntaxError: aString , ' expected' at: hereStart
!
isReservedName: aString
	^#('self' 'super' 'true' 'false' 'nil' 'thisContext') includes: aString
!
atBinaryOperator
	^hereType == #binary or: [hereType == #bar]
!
atNegativeNumber
	^hereType == #binary
		and: [hereValue = '-'
		and: [self peek == #number
		and: [peekStart = (hereStop + 1)]]]
! !

!Parser methodsFor: 'method'!
parseMessagePatternInto: aMethodNode
	| selector arguments |
	arguments := OrderedCollection new.
	hereType == #identifier
		ifTrue: [
			selector := hereValue.
			self advance]
		ifFalse: [
			self atBinaryOperator
				ifTrue: [
					selector := hereValue.
					self advance.
					arguments add: self parseArgumentName]
				ifFalse: [
					hereType == #keyword ifFalse: [^self expected: 'Message pattern'].
					selector := ''.
					[hereType == #keyword] whileTrue: [
						selector := selector , hereValue.
						self advance.
						arguments add: self parseArgumentName]]].
	aMethodNode selector: selector asSymbol; arguments: arguments asArray
!
parseArgumentName
	| node |
	hereType == #identifier ifFalse: [^self expected: 'Argument name'].
	(self isReservedName: hereValue)
		ifTrue: [^self syntaxError: 'Reserved name ' , hereValue , ' cannot be an argument' at: hereStart].
	node := VariableNode name: hereValue start: hereStart stop: hereStop.
	self advance.
	^node
!
parseMethodBodyInto: aMethodNode
	| temps |
	temps := nil.
	[(hereType == #binary and: [hereValue = '<'])
		ifTrue: [
			self parsePragmaInto: aMethodNode.
			true]
		ifFalse: [
			(hereType == #bar and: [temps isNil])
				ifTrue: [
					temps := self parseTemporaries.
					true]
				ifFalse: [false]]] whileTrue.
	aMethodNode temporaries: (temps isNil ifTrue: [#()] ifFalse: [temps]).
	aMethodNode body: (self parseStatementsUntil: #eof)
!
parsePragmaInto: aMethodNode
	| start selector arguments primitive |
	start := hereStart.
	self advance.
	arguments := OrderedCollection new.
	hereType == #identifier
		ifTrue: [
			selector := hereValue.
			self advance]
		ifFalse: [
			hereType == #keyword ifFalse: [^self expected: 'Pragma keyword'].
			selector := ''.
			[hereType == #keyword] whileTrue: [
				selector := selector , hereValue.
				self advance.
				arguments add: (self parsePragmaArgumentFor: selector)]].
	(hereType == #binary and: [hereValue = '>']) ifFalse: [^self expected: '>'].
	self advance.
	selector := selector asSymbol.
	(selector == #primitive: or: [selector == #primitive:error:]) ifFalse: [
		^aMethodNode addPragma: (PragmaNode selector: selector arguments: arguments asArray start: start stop: prevStop)].
	aMethodNode primitive notNil ifTrue: [^self syntaxError: 'Duplicate primitive' at: start].
	primitive := arguments at: 1.
	(primitive isString or: [primitive isInteger])
		ifFalse: [^self syntaxError: 'Primitive name or number expected' at: start].
	aMethodNode primitive: primitive.
	selector == #primitive:error: ifTrue: [
		((arguments at: 2) isKindOf: VariableNode)
			ifFalse: [^self syntaxError: 'Error code variable name expected' at: start].
		aMethodNode errorCodeVariable: (arguments at: 2)]
!
parsePragmaArgumentFor: selectorString
	(hereType == #identifier and: [selectorString = 'primitive:error:'])
		ifTrue: [^self parseArgumentName].
	^self parseLiteralValue
!
parseLiteralValue
	| value |
	(hereType == #number or: [hereType == #string or: [hereType == #symbol or: [hereType == #character]]])
		ifTrue: [
			value := hereValue.
			self advance.
			^value].
	hereType == #literalArrayStart ifTrue: [^self parseLiteralArrayBody].
	hereType == #byteArrayStart ifTrue: [^self parseByteArrayBody].
	hereType == #identifier ifTrue: [
		hereValue = 'true' ifTrue: [self advance. ^true].
		hereValue = 'false' ifTrue: [self advance. ^false].
		hereValue = 'nil' ifTrue: [self advance. ^nil]].
	self atNegativeNumber ifTrue: [
		self advance.
		value := hereValue negated.
		self advance.
		^value].
	^self expected: 'Literal'
!
parseTemporaries
	| temps |
	self advance.
	temps := OrderedCollection new.
	[hereType == #identifier] whileTrue: [
		(self isReservedName: hereValue)
			ifTrue: [^self syntaxError: 'Reserved name ' , hereValue , ' cannot be a temporary' at: hereStart].
		temps do: [:each |
			each name = hereValue ifTrue: [^self syntaxError: 'Duplicate temporary ' , hereValue at: hereStart]].
		temps add: (VariableNode name: hereValue start: hereStart stop: hereStop).
		self advance].
	hereType == #bar ifFalse: [^self expected: 'Vertical bar'].
	self advance.
	^temps asArray
! !

!Parser methodsFor: 'statements'!
parseStatementsUntil: terminator
	| start statements statement |
	start := hereStart.
	statements := OrderedCollection new.
	[hereType == terminator] whileFalse: [
		hereType == #period
			ifTrue: [self advance]
			ifFalse: [
				hereType == #eof ifTrue: [^self expected: (self nameOfTerminator: terminator)].
				statement := self parseStatement.
				statements add: statement.
				hereType == #period
					ifTrue: [
						self advance.
						[hereType == #period] whileTrue: [self advance]]
					ifFalse: [
						hereType == terminator ifFalse: [
							terminator == #eof ifTrue: [^self syntaxError: 'Nothing more expected' at: hereStart].
							^self expected: 'Period or ' , (self nameOfTerminator: terminator)]].
				(statement isReturn and: [hereType ~~ terminator])
					ifTrue: [^self syntaxError: 'Statement after return' at: hereStart]]].
	^SequenceNode statements: statements asArray start: start stop: prevStop
!
nameOfTerminator: aSymbol
	aSymbol == #rightBracket ifTrue: [^']'].
	aSymbol == #rightBrace ifTrue: [^'}'].
	aSymbol == #rightParen ifTrue: [^')'].
	^'end of input'
!
parseStatement
	| start value |
	hereType == #return ifTrue: [
		start := hereStart.
		self advance.
		value := self parseExpressionNode.
		^ReturnNode value: value start: start stop: prevStop].
	^self parseExpressionNode
! !

!Parser methodsFor: 'expressions'!
parseExpressionNode
	| variable value |
	(hereType == #identifier and: [self peek == #assignment]) ifTrue: [
		(self isReservedName: hereValue)
			ifTrue: [^self syntaxError: 'Cannot store into ' , hereValue at: hereStart].
		variable := VariableNode name: hereValue start: hereStart stop: hereStop.
		self advance.
		self advance.
		value := self parseExpressionNode.
		^AssignmentNode variable: variable value: value start: variable start stop: prevStop].
	^self parseCascade
!
parseCascade
	| start expression receiver messages |
	start := hereStart.
	expression := self parseKeywordExpression.
	hereType == #semicolon ifFalse: [^expression].
	expression isMessage ifFalse: [^self syntaxError: 'Cascade must follow a message send' at: hereStart].
	receiver := expression receiver.
	messages := OrderedCollection with: expression.
	[hereType == #semicolon] whileTrue: [
		self advance.
		messages add: (self parseCascadeMessageTo: receiver)].
	^CascadeNode receiver: receiver messages: messages asArray start: start stop: prevStop
!
parseCascadeMessageTo: receiver
	| start |
	start := hereStart.
	hereType == #identifier ifTrue: [^self parseUnaryMessageTo: receiver start: start].
	self atBinaryOperator ifTrue: [^self parseBinaryMessageTo: receiver start: start].
	hereType == #keyword ifTrue: [^self parseKeywordMessageTo: receiver start: start].
	^self expected: 'Cascaded message'
!
parseKeywordExpression
	| start receiver |
	start := hereStart.
	receiver := self parseBinaryExpression.
	hereType == #keyword ifFalse: [^receiver].
	^self parseKeywordMessageTo: receiver start: start
!
parseKeywordMessageTo: receiver start: start
	| selector arguments |
	selector := ''.
	arguments := OrderedCollection new.
	[hereType == #keyword] whileTrue: [
		selector := selector , hereValue.
		self advance.
		arguments add: self parseBinaryExpression].
	^MessageNode receiver: receiver selector: selector asSymbol arguments: arguments asArray start: start stop: prevStop
!
parseBinaryExpression
	| start node |
	start := hereStart.
	node := self parseUnaryExpression.
	[self atBinaryOperator] whileTrue: [node := self parseBinaryMessageTo: node start: start].
	^node
!
parseBinaryMessageTo: receiver start: start
	| selector argumentStart argument |
	selector := hereValue asSymbol.
	self advance.
	argumentStart := hereStart.
	argument := self parseUnaryMessagesTo: self parsePrimary start: argumentStart.
	^MessageNode receiver: receiver selector: selector arguments: (Array with: argument) start: start stop: prevStop
!
parseUnaryExpression
	| start |
	start := hereStart.
	^self parseUnaryMessagesTo: self parsePrimary start: start
!
parseUnaryMessagesTo: aNode start: start
	| node |
	node := aNode.
	[hereType == #identifier] whileTrue: [node := self parseUnaryMessageTo: node start: start].
	^node
!
parseUnaryMessageTo: receiver start: start
	| node |
	node := MessageNode receiver: receiver selector: hereValue asSymbol arguments: #() start: start stop: hereStop.
	self advance.
	^node
! !

!Parser methodsFor: 'primaries'!
parsePrimary
	| node |
	hereType == #identifier ifTrue: [^self parseVariable].
	(hereType == #number or: [hereType == #string or: [hereType == #symbol or: [hereType == #character]]])
		ifTrue: [
			node := LiteralNode value: hereValue start: hereStart stop: hereStop.
			self advance.
			^node].
	hereType == #leftBracket ifTrue: [^self parseBlock].
	hereType == #leftParen ifTrue: [
		self advance.
		node := self parseExpressionNode.
		hereType == #rightParen ifFalse: [^self expected: ')'].
		self advance.
		^node].
	hereType == #literalArrayStart ifTrue: [^self parseLiteralArray].
	hereType == #byteArrayStart ifTrue: [^self parseByteArray].
	hereType == #leftBrace ifTrue: [^self parseBrace].
	self atNegativeNumber ifTrue: [^self parseNegativeNumber].
	^self expected: 'Expression'
!
parseVariable
	| node |
	hereValue = 'true' ifTrue: [node := LiteralNode value: true start: hereStart stop: hereStop].
	hereValue = 'false' ifTrue: [node := LiteralNode value: false start: hereStart stop: hereStop].
	hereValue = 'nil' ifTrue: [node := LiteralNode value: nil start: hereStart stop: hereStop].
	node isNil ifTrue: [node := VariableNode name: hereValue start: hereStart stop: hereStop].
	self advance.
	^node
!
parseNegativeNumber
	| start node |
	start := hereStart.
	self advance.
	node := LiteralNode value: hereValue negated start: start stop: hereStop.
	self advance.
	^node
!
parseLiteralArray
	| start value |
	start := hereStart.
	value := self parseLiteralArrayBody.
	^LiteralNode value: value start: start stop: prevStop
!
parseLiteralArrayBody
	"The current token is #( or a nested (."
	| elements |
	self advance.
	elements := OrderedCollection new.
	[hereType == #rightParen] whileFalse: [
		hereType == #eof ifTrue: [^self expected: ')'].
		elements add: self parseLiteralArrayElement].
	self advance.
	^elements asArray
!
parseLiteralArrayElement
	| value |
	(hereType == #number or: [hereType == #string or: [hereType == #symbol or: [hereType == #character]]])
		ifTrue: [
			value := hereValue.
			self advance.
			^value].
	hereType == #identifier ifTrue: [
		value := hereValue = 'true'
			ifTrue: [true]
			ifFalse: [
				hereValue = 'false'
					ifTrue: [false]
					ifFalse: [hereValue = 'nil' ifTrue: [nil] ifFalse: [hereValue asSymbol]]].
		self advance.
		^value].
	hereType == #keyword ifTrue: [
		value := hereValue.
		self advance.
		[(hereType == #keyword or: [hereType == #identifier]) and: [hereStart = (prevStop + 1)]] whileTrue: [
			value := value , hereValue.
			self advance].
		^value asSymbol].
	(hereType == #leftParen or: [hereType == #literalArrayStart]) ifTrue: [^self parseLiteralArrayBody].
	hereType == #byteArrayStart ifTrue: [^self parseByteArrayBody].
	self atNegativeNumber ifTrue: [
		self advance.
		value := hereValue negated.
		self advance.
		^value].
	self atBinaryOperator ifTrue: [
		value := hereValue asSymbol.
		self advance.
		^value].
	^self expected: 'Literal'
!
parseByteArray
	| start value |
	start := hereStart.
	value := self parseByteArrayBody.
	^LiteralNode value: value start: start stop: prevStop
!
parseByteArrayBody
	| values bytes |
	self advance.
	values := OrderedCollection new.
	[hereType == #rightBracket] whileFalse: [
		(hereType == #number and: [hereValue isInteger and: [hereValue >= 0 and: [hereValue <= 255]]])
			ifFalse: [^self expected: 'Byte value (0-255) or ]'].
		values add: hereValue.
		self advance].
	self advance.
	bytes := ByteArray new: values size.
	1 to: values size do: [:i | bytes at: i put: (values at: i)].
	^bytes
!
parseBlock
	| start arguments temporaries body |
	start := hereStart.
	self advance.
	arguments := OrderedCollection new.
	[hereType == #colon] whileTrue: [
		self advance.
		arguments do: [:each |
			each name = hereValue ifTrue: [^self syntaxError: 'Duplicate argument ' , hereValue at: hereStart]].
		arguments add: self parseArgumentName].
	arguments isEmpty ifFalse: [
		hereType == #bar
			ifTrue: [self advance]
			ifFalse: [hereType == #rightBracket ifFalse: [^self expected: 'Vertical bar']]].
	temporaries := hereType == #bar ifTrue: [self parseTemporaries] ifFalse: [#()].
	body := self parseStatementsUntil: #rightBracket.
	self advance.
	^BlockNode arguments: arguments asArray temporaries: temporaries body: body start: start stop: prevStop
!
parseBrace
	| start elements |
	start := hereStart.
	self advance.
	elements := OrderedCollection new.
	[hereType == #rightBrace] whileFalse: [
		hereType == #eof ifTrue: [^self expected: '}'].
		elements add: self parseExpressionNode.
		hereType == #period
			ifTrue: [self advance]
			ifFalse: [hereType == #rightBrace ifFalse: [^self expected: 'Period or }']]].
	self advance.
	^BraceNode elements: elements asArray start: start stop: prevStop
! !
