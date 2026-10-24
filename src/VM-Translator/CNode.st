Object subclass: #CNode
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Translator'!

CNode comment: 'I am the abstract class of the C syntax tree the translator builds and prints. Expressions (CExpr) carry their CType; statements print themselves indented.'!

!CNode methodsFor: 'printing'!
printString
	| s |
	s := WriteStream on: String new.
	self printCOn: s indent: 0.
	^s contents
!
printCOn: aStream indent: anInteger
	self subclassResponsibility
!
tab: anInteger on: aStream
	anInteger timesRepeat: [aStream nextPutAll: '    ']
! !

!CNode methodsFor: 'testing'!
isConstant
	^false
!
isBlock
	^false
!
endsControlFlow
	"Whether control never falls through (return, goto)."
	^false
! !

CNode subclass: #CExpr
	instanceVariableNames: 'type'
	classVariableNames: ''
	package: 'VM-Translator'!

!CExpr methodsFor: 'accessing'!
type
	^type
!
type: aCType
	type := aCType
!
precedence
	"C precedence: 16 primary/postfix, 15 unary and casts, 13 multiplicative ... 2 assignment."
	^16
! !

!CExpr methodsFor: 'testing'!
isPure
	"No side effects and cheap to repeat."
	^false
!
isVariable
	^false
!
isLvalue
	^false
! !

!CExpr methodsFor: 'printing'!
printCOn: aStream indent: anInteger
	self printOn: aStream precedence: 0
!
printOn: aStream precedence: anInteger
	anInteger > self precedence
		ifTrue: [aStream nextPut: $(. self printExprOn: aStream. aStream nextPut: $)]
		ifFalse: [self printExprOn: aStream]
!
printExprOn: aStream
	self subclassResponsibility
!
cString
	| s |
	s := WriteStream on: String new.
	self printOn: s precedence: 0.
	^s contents
! !

CExpr subclass: #CConst
	instanceVariableNames: 'value hex symbol'
	classVariableNames: ''
	package: 'VM-Translator'!

CConst comment: 'I am a constant: an Integer, a Float, a Boolean, a String literal, or nil for NULL.'!

!CConst class methodsFor: 'instance creation'!
value: anObject type: aCType
	^self new setValue: anObject; type: aCType
!
value: anObject type: aCType hex: aBoolean
	^(self value: anObject type: aCType) hex: aBoolean
! !

!CConst methodsFor: 'accessing'!
setValue: anObject
	value := anObject
!
value
	^value
!
hex: aBoolean
	hex := aBoolean
!
symbol: aString
	"Print as the #define aString."
	symbol := aString
! !

!CConst methodsFor: 'testing'!
isConstant
	^true
!
isPure
	^true
! !

!CConst methodsFor: 'printing'!
printExprOn: aStream
	symbol notNil ifTrue: [^aStream nextPutAll: symbol].
	value isNil ifTrue: [^aStream nextPutAll: 'NULL'].
	value == true ifTrue: [^aStream nextPutAll: 'true'].
	value == false ifTrue: [^aStream nextPutAll: 'false'].
	value isString ifTrue: [^self printStringLiteral: value on: aStream].
	value isFloat ifTrue: [^self printFloatOn: aStream].
	self printIntegerOn: aStream
!
printIntegerOn: aStream
	| v suffix |
	v := value.
	suffix := ''.
	(type notNil and: [type isInteger and: [type size = 8]])
		ifTrue: [suffix := type isSigned ifTrue: ['LL'] ifFalse: ['ULL']]
		ifFalse: [
			(v > 16r7FFFFFFF or: [v < -16r80000000]) ifTrue: [
				suffix := v > 16r7FFFFFFFFFFFFFFF ifTrue: ['ULL'] ifFalse: ['LL']]].
	(type notNil and: [type isInteger and: [type isSigned not and: [suffix isEmpty]]]) ifTrue: [suffix := 'U'].
	v = -16r8000000000000000 ifTrue: [^aStream nextPutAll: '(-0x7FFFFFFFFFFFFFFFLL - 1)'].
	v < 0 ifTrue: [aStream nextPut: $-. v := v negated].
	hex == true
		ifTrue: [aStream nextPutAll: '0x'; nextPutAll: (v printStringBase: 16)]
		ifFalse: [aStream print: v].
	aStream nextPutAll: suffix
!
printFloatOn: aStream
	value isNaN ifTrue: [^aStream nextPutAll: '(0.0 / 0.0)'].
	value isInfinite ifTrue: [^aStream nextPutAll: (value > 0 ifTrue: ['(1.0 / 0.0)'] ifFalse: ['(-1.0 / 0.0)'])].
	value = value truncated
		ifTrue: [aStream print: value truncated; nextPutAll: '.0']
		ifFalse: [aStream print: value]
!
printStringLiteral: aString on: aStream
	aStream nextPut: $".
	aString utf8Encoded do: [:b |
		b = 34 ifTrue: [aStream nextPutAll: '\"'] ifFalse: [
		b = 92 ifTrue: [aStream nextPutAll: '\\'] ifFalse: [
		b = 10 ifTrue: [aStream nextPutAll: '\n'] ifFalse: [
		b = 9 ifTrue: [aStream nextPutAll: '\t'] ifFalse: [
		(b < 32 or: [b > 126])
			ifTrue: [aStream nextPut: $\; nextPutAll: ((b printStringBase: 8) padLeftTo: 3 with: $0)]
			ifFalse: [aStream nextPut: (Character value: b)]]]]]].
	aStream nextPut: $"
! !

CExpr subclass: #CVarRef
	instanceVariableNames: 'name'
	classVariableNames: ''
	package: 'VM-Translator'!

!CVarRef class methodsFor: 'instance creation'!
name: aString type: aCType
	^self new setName: aString; type: aCType
! !

!CVarRef methodsFor: 'accessing'!
setName: aString
	name := aString
!
name
	^name
! !

!CVarRef methodsFor: 'testing'!
isPure
	^true
!
isVariable
	^true
!
isLvalue
	^true
! !

!CVarRef methodsFor: 'printing'!
printExprOn: aStream
	aStream nextPutAll: name
! !

CExpr subclass: #CRaw
	instanceVariableNames: 'text pure'
	classVariableNames: ''
	package: 'VM-Translator'!

!CRaw class methodsFor: 'instance creation'!
text: aString type: aCType
	^self new setText: aString pure: false; type: aCType
!
pureText: aString type: aCType
	^self new setText: aString pure: true; type: aCType
! !

!CRaw methodsFor: 'accessing'!
setText: aString pure: aBoolean
	text := aString.
	pure := aBoolean
!
text
	^text
! !

!CRaw methodsFor: 'testing'!
isPure
	^pure
! !

!CRaw methodsFor: 'printing'!
printExprOn: aStream
	aStream nextPutAll: text
! !

CExpr subclass: #CBinary
	instanceVariableNames: 'operator left right'
	classVariableNames: 'Precedences'
	package: 'VM-Translator'!

!CBinary class methodsFor: 'instance creation'!
operator: aString left: aCExpr right: bCExpr type: aCType
	^self new setOperator: aString left: aCExpr right: bCExpr; type: aCType
!
precedenceOf: aString
	Precedences isNil ifTrue: [
		Precedences := Dictionary new.
		#('*' '/' '%') do: [:o | Precedences at: o put: 13].
		#('+' '-') do: [:o | Precedences at: o put: 12].
		#('<<' '>>') do: [:o | Precedences at: o put: 11].
		#('<' '<=' '>' '>=') do: [:o | Precedences at: o put: 10].
		#('==' '!!=') do: [:o | Precedences at: o put: 9].
		Precedences at: '&' put: 8; at: '^' put: 7; at: '|' put: 6; at: '&&' put: 5; at: '||' put: 4.
		#('=' '+=' '-=') do: [:o | Precedences at: o put: 2]].
	^Precedences at: aString
! !

!CBinary methodsFor: 'accessing'!
setOperator: aString left: aCExpr right: bCExpr
	operator := aString.
	left := aCExpr.
	right := bCExpr
!
operator
	^operator
!
left
	^left
!
right
	^right
!
precedence
	^self class precedenceOf: operator
! !

!CBinary methodsFor: 'testing'!
isPure
	^(#('=' '+=' '-=') includes: operator) not and: [left isPure and: [right isPure]]
! !

!CBinary methodsFor: 'printing'!
printExprOn: aStream
	| p |
	p := self precedence.
	p = 2
		ifTrue: [
			left printOn: aStream precedence: 15.
			aStream space; nextPutAll: operator; space.
			right printOn: aStream precedence: 2]
		ifFalse: [
			left printOn: aStream precedence: (self operandPrecedenceFor: left).
			aStream space; nextPutAll: operator; space.
			right printOn: aStream precedence: (self operandPrecedenceFor: right) + 1]
!
operandPrecedenceFor: anOperand
	"Parenthesize mixed bitwise, shift and logical operators even where C would not need it (and clang would warn)."
	| p q |
	p := self precedence.
	q := anOperand precedence.
	(q < 16 and: [q ~= p and: [(#(4 5 6 7 8 11) includes: p) or: [#(4 5 6 7 8 11) includes: q]]]) ifTrue: [^17].
	^p
! !

CExpr subclass: #CUnary
	instanceVariableNames: 'operator operand'
	classVariableNames: ''
	package: 'VM-Translator'!

!CUnary class methodsFor: 'instance creation'!
operator: aString operand: aCExpr type: aCType
	^self new setOperator: aString operand: aCExpr; type: aCType
! !

!CUnary methodsFor: 'accessing'!
setOperator: aString operand: aCExpr
	operator := aString.
	operand := aCExpr
!
operator
	^operator
!
operand
	^operand
!
precedence
	^15
! !

!CUnary methodsFor: 'testing'!
isPure
	^operand isPure
!
isLvalue
	^operator = '*'
! !

!CUnary methodsFor: 'printing'!
printExprOn: aStream
	aStream nextPutAll: operator.
	(operator = '-' and: [operand precedence = 15]) ifTrue: [aStream space].
	operand printOn: aStream precedence: 15
! !

CExpr subclass: #CCast
	instanceVariableNames: 'operand'
	classVariableNames: ''
	package: 'VM-Translator'!

!CCast class methodsFor: 'instance creation'!
to: aCType operand: aCExpr
	^self new setOperand: aCExpr; type: aCType
! !

!CCast methodsFor: 'accessing'!
setOperand: aCExpr
	operand := aCExpr
!
operand
	^operand
!
precedence
	^15
! !

!CCast methodsFor: 'testing'!
isPure
	^operand isPure
! !

!CCast methodsFor: 'printing'!
printExprOn: aStream
	aStream nextPut: $(; nextPutAll: (type declarator: ''); nextPut: $).
	operand printOn: aStream precedence: 15
! !

CExpr subclass: #CCall
	instanceVariableNames: 'function arguments noReturn'
	classVariableNames: ''
	package: 'VM-Translator'!

CCall comment: 'function is a C name (a String) or an expression yielding a function pointer.'!

!CCall class methodsFor: 'instance creation'!
function: aStringOrCExpr arguments: aCollection type: aCType
	^self new setFunction: aStringOrCExpr arguments: aCollection; type: aCType
! !

!CCall methodsFor: 'accessing'!
setFunction: aStringOrCExpr arguments: aCollection
	function := aStringOrCExpr.
	arguments := aCollection asArray.
	noReturn := false
!
noReturn: aBoolean
	noReturn := aBoolean
!
isNoReturn
	^noReturn
!
function
	^function
!
arguments
	^arguments
! !

!CCall methodsFor: 'printing'!
printExprOn: aStream
	function isString
		ifTrue: [aStream nextPutAll: function]
		ifFalse: [function printOn: aStream precedence: 16].
	aStream nextPut: $(.
	arguments do: [:a | a printOn: aStream precedence: 3] separatedBy: [aStream nextPutAll: ', '].
	aStream nextPut: $)
! !

CExpr subclass: #CIndex
	instanceVariableNames: 'base index'
	classVariableNames: ''
	package: 'VM-Translator'!

!CIndex class methodsFor: 'instance creation'!
base: aCExpr index: bCExpr type: aCType
	^self new setBase: aCExpr index: bCExpr; type: aCType
! !

!CIndex methodsFor: 'accessing'!
setBase: aCExpr index: bCExpr
	base := aCExpr.
	index := bCExpr
! !

!CIndex methodsFor: 'testing'!
isPure
	^base isPure and: [index isPure]
!
isLvalue
	^true
! !

!CIndex methodsFor: 'printing'!
printExprOn: aStream
	base printOn: aStream precedence: 16.
	aStream nextPut: $[.
	index printOn: aStream precedence: 0.
	aStream nextPut: $]
! !

CExpr subclass: #CMember
	instanceVariableNames: 'base field arrow'
	classVariableNames: ''
	package: 'VM-Translator'!

!CMember class methodsFor: 'instance creation'!
base: aCExpr field: aString arrow: aBoolean type: aCType
	^self new setBase: aCExpr field: aString arrow: aBoolean; type: aCType
! !

!CMember methodsFor: 'accessing'!
setBase: aCExpr field: aString arrow: aBoolean
	base := aCExpr.
	field := aString.
	arrow := aBoolean
! !

!CMember methodsFor: 'testing'!
isPure
	^base isPure
!
isLvalue
	^true
! !

!CMember methodsFor: 'printing'!
printExprOn: aStream
	base printOn: aStream precedence: 16.
	aStream nextPutAll: (arrow ifTrue: ['->'] ifFalse: ['.']); nextPutAll: field
! !

CExpr subclass: #CConditional
	instanceVariableNames: 'condition ifTrue ifFalse'
	classVariableNames: ''
	package: 'VM-Translator'!

!CConditional class methodsFor: 'instance creation'!
condition: c ifTrue: t ifFalse: f type: aCType
	^self new setCondition: c ifTrue: t ifFalse: f; type: aCType
! !

!CConditional methodsFor: 'accessing'!
setCondition: c ifTrue: t ifFalse: f
	condition := c.
	ifTrue := t.
	ifFalse := f
!
precedence
	^3
! !

!CConditional methodsFor: 'testing'!
isPure
	^condition isPure and: [ifTrue isPure and: [ifFalse isPure]]
! !

!CConditional methodsFor: 'printing'!
printExprOn: aStream
	condition printOn: aStream precedence: 4.
	aStream nextPutAll: ' ? '.
	ifTrue printOn: aStream precedence: 3.
	aStream nextPutAll: ' : '.
	ifFalse printOn: aStream precedence: 3
! !

CExpr subclass: #CStatementExpr
	instanceVariableNames: 'block result'
	classVariableNames: ''
	package: 'VM-Translator'!

CStatementExpr comment: 'A GNU C statement expression: ({ statements; result; }).'!

!CStatementExpr class methodsFor: 'instance creation'!
block: aCBlock result: aCExprOrNil type: aCType
	^self new setBlock: aCBlock result: aCExprOrNil; type: aCType
! !

!CStatementExpr methodsFor: 'accessing'!
setBlock: aCBlock result: aCExprOrNil
	block := aCBlock.
	result := aCExprOrNil
! !

!CStatementExpr methodsFor: 'printing'!
printExprOn: aStream
	| indent |
	indent := 1.
	aStream nextPutAll: '({'.
	block printStatementsOn: aStream indent: indent.
	result isNil ifFalse: [
		aStream lf.
		self tab: indent on: aStream.
		result printOn: aStream precedence: 0.
		aStream nextPut: $;].
	aStream nextPutAll: ' })'
! !

CExpr subclass: #CLabelAddress
	instanceVariableNames: 'label'
	classVariableNames: ''
	package: 'VM-Translator'!

!CLabelAddress class methodsFor: 'instance creation'!
label: aString
	^self new setLabel: aString
! !

!CLabelAddress methodsFor: 'accessing'!
setLabel: aString
	label := aString
! !

!CLabelAddress methodsFor: 'testing'!
isPure
	^true
! !

!CLabelAddress methodsFor: 'printing'!
printExprOn: aStream
	aStream nextPutAll: '&&'; nextPutAll: label
! !

CNode subclass: #CStatement
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Translator'!

CStatement subclass: #CBlock
	instanceVariableNames: 'statements'
	classVariableNames: ''
	package: 'VM-Translator'!

!CBlock class methodsFor: 'instance creation'!
new
	^self basicNew setStatements: OrderedCollection new
!
with: aStatement
	^self new add: aStatement; yourself
! !

!CBlock methodsFor: 'accessing'!
setStatements: aCollection
	statements := aCollection
!
statements
	^statements
!
add: aStatement
	aStatement isBlock
		ifTrue: [statements addAll: aStatement statements]
		ifFalse: [statements add: aStatement].
	^aStatement
!
addAll: aCollection
	aCollection do: [:s | self add: s]
!
isEmpty
	^statements isEmpty
! !

!CBlock methodsFor: 'testing'!
isBlock
	^true
!
endsControlFlow
	^statements notEmpty and: [statements last endsControlFlow]
! !

!CBlock methodsFor: 'printing'!
printCOn: aStream indent: anInteger
	aStream nextPut: ${.
	self printStatementsOn: aStream indent: anInteger + 1.
	aStream lf.
	self tab: anInteger on: aStream.
	aStream nextPut: $}
!
printStatementsOn: aStream indent: anInteger
	statements do: [:s |
		(s isKindOf: CLabel)
			ifTrue: [aStream lf. self tab: (anInteger - 1 max: 0) on: aStream]
			ifFalse: [aStream lf. self tab: anInteger on: aStream].
		s printCOn: aStream indent: anInteger]
! !

CStatement subclass: #CExprStatement
	instanceVariableNames: 'expression'
	classVariableNames: ''
	package: 'VM-Translator'!

!CExprStatement class methodsFor: 'instance creation'!
expression: aCExpr
	^self new setExpression: aCExpr
! !

!CExprStatement methodsFor: 'accessing'!
setExpression: aCExpr
	expression := aCExpr
!
expression
	^expression
! !

!CExprStatement methodsFor: 'testing'!
endsControlFlow
	^(expression isKindOf: CCall) and: [expression isNoReturn]
! !

!CExprStatement methodsFor: 'printing'!
printCOn: aStream indent: anInteger
	(expression isKindOf: CStatementExpr)
		ifTrue: [expression printOn: aStream precedence: 0]
		ifFalse: [expression printOn: aStream precedence: 0].
	aStream nextPut: $;
! !

CStatement subclass: #CDeclaration
	instanceVariableNames: 'name type initializer isStatic'
	classVariableNames: ''
	package: 'VM-Translator'!

!CDeclaration class methodsFor: 'instance creation'!
name: aString type: aCType initializer: aStringOrNil
	^self new setName: aString type: aCType initializer: aStringOrNil
! !

!CDeclaration methodsFor: 'accessing'!
setName: aString type: aCType initializer: aStringOrNil
	name := aString.
	type := aCType.
	initializer := aStringOrNil.
	isStatic := false
!
beStatic
	isStatic := true
!
name
	^name
!
type
	^type
!
initializer: aString
	initializer := aString
! !

!CDeclaration methodsFor: 'printing'!
printCOn: aStream indent: anInteger
	isStatic ifTrue: [aStream nextPutAll: 'static '].
	aStream nextPutAll: (type declare: name).
	initializer isNil ifFalse: [aStream nextPutAll: ' = '; nextPutAll: initializer].
	aStream nextPut: $;
! !

CStatement subclass: #CIf
	instanceVariableNames: 'condition thenBlock elseBlock'
	classVariableNames: ''
	package: 'VM-Translator'!

!CIf class methodsFor: 'instance creation'!
condition: aCExpr then: aCBlock else: bCBlockOrNil
	^self new setCondition: aCExpr then: aCBlock else: bCBlockOrNil
! !

!CIf methodsFor: 'accessing'!
setCondition: aCExpr then: aCBlock else: bCBlockOrNil
	condition := aCExpr.
	thenBlock := aCBlock.
	elseBlock := bCBlockOrNil
! !

!CIf methodsFor: 'testing'!
endsControlFlow
	^elseBlock notNil and: [thenBlock endsControlFlow and: [elseBlock endsControlFlow]]
! !

!CIf methodsFor: 'printing'!
printCOn: aStream indent: anInteger
	aStream nextPutAll: 'if ('.
	condition printOn: aStream precedence: 0.
	aStream nextPutAll: ') '.
	thenBlock printCOn: aStream indent: anInteger.
	(elseBlock isNil or: [elseBlock isEmpty]) ifTrue: [^self].
	aStream nextPutAll: ' else '.
	(elseBlock statements size = 1 and: [elseBlock statements first isKindOf: CIf])
		ifTrue: [elseBlock statements first printCOn: aStream indent: anInteger]
		ifFalse: [elseBlock printCOn: aStream indent: anInteger]
! !

CStatement subclass: #CWhile
	instanceVariableNames: 'condition body'
	classVariableNames: ''
	package: 'VM-Translator'!

!CWhile class methodsFor: 'instance creation'!
condition: aCExprOrNil body: aCBlock
	^self new setCondition: aCExprOrNil body: aCBlock
! !

!CWhile methodsFor: 'accessing'!
setCondition: aCExprOrNil body: aCBlock
	condition := aCExprOrNil.
	body := aCBlock
! !

!CWhile methodsFor: 'testing'!
endsControlFlow
	"for (;;) without a break"
	^condition isNil and: [(self containsBreak: body) not]
!
containsBreak: aBlock
	^aBlock statements anySatisfy: [:s |
		(s isKindOf: CBreak) or: [(s isKindOf: CIf) and: [s hasBreak]]]
! !

!CWhile methodsFor: 'printing'!
printCOn: aStream indent: anInteger
	condition isNil
		ifTrue: [aStream nextPutAll: 'for (;;) ']
		ifFalse: [
			aStream nextPutAll: 'while ('.
			condition printOn: aStream precedence: 0.
			aStream nextPutAll: ') '].
	body printCOn: aStream indent: anInteger
! !

!CIf methodsFor: 'testing'!
hasBreak
	^(thenBlock statements anySatisfy: [:s | s isKindOf: CBreak]) or: [
		elseBlock notNil and: [elseBlock statements anySatisfy: [:s | s isKindOf: CBreak]]]
! !

CStatement subclass: #CFor
	instanceVariableNames: 'init condition step body'
	classVariableNames: ''
	package: 'VM-Translator'!

!CFor class methodsFor: 'instance creation'!
init: aCExpr condition: bCExpr step: cCExpr body: aCBlock
	^self new setInit: aCExpr condition: bCExpr step: cCExpr body: aCBlock
! !

!CFor methodsFor: 'accessing'!
setInit: aCExpr condition: bCExpr step: cCExpr body: aCBlock
	init := aCExpr.
	condition := bCExpr.
	step := cCExpr.
	body := aCBlock
! !

!CFor methodsFor: 'printing'!
printStep: aStream
	"i++ for += 1"
	((step isKindOf: CBinary) and: [(step operator = '+=' or: [step operator = '-=']) and: [step right isConstant and: [step right value = 1]]])
		ifTrue: [
			step left printOn: aStream precedence: 16.
			^aStream nextPutAll: (step operator = '+=' ifTrue: ['++'] ifFalse: ['--'])].
	step printOn: aStream precedence: 0
!
printCOn: aStream indent: anInteger
	aStream nextPutAll: 'for ('.
	init printOn: aStream precedence: 0.
	aStream nextPutAll: '; '.
	condition printOn: aStream precedence: 0.
	aStream nextPutAll: '; '.
	self printStep: aStream.
	aStream nextPutAll: ') '.
	body printCOn: aStream indent: anInteger
! !

CStatement subclass: #CSwitch
	instanceVariableNames: 'expression cases defaultBlock'
	classVariableNames: ''
	package: 'VM-Translator'!

!CSwitch class methodsFor: 'instance creation'!
expression: aCExpr cases: anArrayOfAssociations default: aCBlockOrNil
	"cases: {values} -> CBlock"
	^self new setExpression: aCExpr cases: anArrayOfAssociations default: aCBlockOrNil
! !

!CSwitch methodsFor: 'accessing'!
setExpression: aCExpr cases: anArray default: aCBlockOrNil
	expression := aCExpr.
	cases := anArray.
	defaultBlock := aCBlockOrNil
! !

!CSwitch methodsFor: 'testing'!
endsControlFlow
	^defaultBlock notNil and: [defaultBlock endsControlFlow and: [cases allSatisfy: [:c | c value endsControlFlow]]]
! !

!CSwitch methodsFor: 'printing'!
printCOn: aStream indent: anInteger
	aStream nextPutAll: 'switch ('.
	expression printOn: aStream precedence: 0.
	aStream nextPutAll: ') {'.
	cases do: [:c |
		c key do: [:v |
			aStream lf. self tab: anInteger on: aStream.
			aStream nextPutAll: 'case '.
			v printOn: aStream precedence: 0.
			aStream nextPut: $:].
		self printCase: c value on: aStream indent: anInteger].
	defaultBlock isNil ifFalse: [
		aStream lf. self tab: anInteger on: aStream.
		aStream nextPutAll: 'default:'.
		self printCase: defaultBlock on: aStream indent: anInteger].
	aStream lf. self tab: anInteger on: aStream.
	aStream nextPut: $}
!
printCase: aCBlock on: aStream indent: anInteger
	aCBlock printStatementsOn: aStream indent: anInteger + 1.
	aCBlock endsControlFlow ifFalse: [
		aStream lf. self tab: anInteger + 1 on: aStream.
		aStream nextPutAll: 'break;']
! !

CStatement subclass: #CReturn
	instanceVariableNames: 'expression'
	classVariableNames: ''
	package: 'VM-Translator'!

!CReturn class methodsFor: 'instance creation'!
expression: aCExprOrNil
	^self new setExpression: aCExprOrNil
! !

!CReturn methodsFor: 'accessing'!
setExpression: aCExprOrNil
	expression := aCExprOrNil
! !

!CReturn methodsFor: 'testing'!
endsControlFlow
	^true
! !

!CReturn methodsFor: 'printing'!
printCOn: aStream indent: anInteger
	expression isNil ifTrue: [^aStream nextPutAll: 'return;'].
	aStream nextPutAll: 'return '.
	expression printOn: aStream precedence: 0.
	aStream nextPut: $;
! !

CStatement subclass: #CGoto
	instanceVariableNames: 'label computed'
	classVariableNames: ''
	package: 'VM-Translator'!

CGoto comment: 'goto label; or, if computed is an expression, goto *computed;'!

!CGoto class methodsFor: 'instance creation'!
label: aString
	^self new setLabel: aString computed: nil
!
computed: aCExpr
	^self new setLabel: nil computed: aCExpr
! !

!CGoto methodsFor: 'accessing'!
setLabel: aString computed: aCExpr
	label := aString.
	computed := aCExpr
!
label
	^label
! !

!CGoto methodsFor: 'testing'!
endsControlFlow
	^true
! !

!CGoto methodsFor: 'printing'!
printCOn: aStream indent: anInteger
	computed isNil
		ifTrue: [aStream nextPutAll: 'goto '; nextPutAll: label; nextPut: $;]
		ifFalse: [
			aStream nextPutAll: 'goto *'.
			computed printOn: aStream precedence: 15.
			aStream nextPut: $;]
! !

CStatement subclass: #CLabel
	instanceVariableNames: 'name'
	classVariableNames: ''
	package: 'VM-Translator'!

!CLabel class methodsFor: 'instance creation'!
name: aString
	^self new setName: aString
! !

!CLabel methodsFor: 'accessing'!
setName: aString
	name := aString
!
name
	^name
! !

!CLabel methodsFor: 'printing'!
printCOn: aStream indent: anInteger
	aStream nextPutAll: name; nextPutAll: ':;'
! !

CStatement subclass: #CBreak
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Translator'!

!CBreak methodsFor: 'printing'!
printCOn: aStream indent: anInteger
	aStream nextPutAll: 'break;'
! !

CStatement subclass: #CComment
	instanceVariableNames: 'text'
	classVariableNames: ''
	package: 'VM-Translator'!

!CComment class methodsFor: 'instance creation'!
text: aString
	^self new setText: aString
! !

!CComment methodsFor: 'accessing'!
setText: aString
	text := aString
! !

!CComment methodsFor: 'printing'!
printCOn: aStream indent: anInteger
	aStream nextPutAll: '/* '; nextPutAll: (text copyReplaceAll: '*/' with: '* /'); nextPutAll: ' */'
! !
