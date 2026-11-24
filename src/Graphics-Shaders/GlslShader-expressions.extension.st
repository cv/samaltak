!GlslShader methodsFor: 'expressions'!
expression
	| e n parts |
	e := self assignment.
	(self peekIs: ',') ifFalse: [^e].
	parts := OrderedCollection with: e.
	[self accept: ','] whileTrue: [parts add: self assignment].
	n := GlslNode kind: #comma at: e.
	n children: parts asArray; type: parts last type.
	^n
!
assignment
	| l op t r n |
	l := self conditional.
	t := self peek.
	(t kind == #punct and: [#('=' '+=' '-=' '*=' '/=' '%=' '&=' '|=' '^=' '<<=' '>>=') includes: t text]) ifFalse: [^l].
	op := self next text.
	r := self assignment.
	self checkWritable: l.
	op = '='
		ifTrue: [r := self convert: r to: l type]
		ifFalse: [| b |
			b := self binary: (op copyFrom: 1 to: op size - 1) left: l right: r at: t.
			b type = l type ifFalse: [self error: l type name, ' ', op, ' ', r type name, ' does not give a ', l type name at: t].
			r := b second].
	n := GlslNode kind: #assign at: l.
	n op: op; children: (Array with: l with: r); type: l type.
	^n
!
conditional
	| c a b n t |
	c := self binaryLevel: 1.
	(self peekIs: '?') ifFalse: [^c].
	t := self next.
	c type isBool ifFalse: [self error: 'the condition of ?: is a bool, not ', c type name at: c].
	a := self expression.
	self expect: ':'.
	b := self assignment.
	t := self commonType: a type and: b type at: t.
	n := GlslNode kind: #ternary at: c.
	n children: (Array with: c with: (self convert: a to: t) with: (self convert: b to: t)); type: t.
	^n
!
binaryLevel: level
	| levels e |
	levels := #(#('||') #('^^') #('&&') #('|') #('^') #('&') #('==' '!!=') #('<' '>' '<=' '>=') #('<<' '>>') #('+' '-') #('*' '/' '%')).
	level > levels size ifTrue: [^self unary].
	e := self binaryLevel: level + 1.
	[self peek kind == #punct and: [(levels at: level) includes: self peek text]] whileTrue: [| t r |
		t := self next.
		r := self binaryLevel: level + 1.
		e := self binary: t text left: e right: r at: t].
	^e
!
unary
	| t e n |
	t := self peek.
	(t kind == #punct and: [#('++' '--') includes: t text]) ifTrue: [
		self next.
		e := self unary.
		self checkWritable: e.
		(e type isNumeric) ifFalse: [self error: t text, ' needs a number, not ', e type name at: t].
		n := GlslNode kind: #unary at: t.
		^n op: t text; children: (Array with: e); type: e type; yourself].
	(t kind == #punct and: [#('+' '-' '!!' '~') includes: t text]) ifTrue: [
		self next.
		e := self unary.
		(t text = '!!' and: [e type isBool not]) ifTrue: [self error: '!! needs a bool, not ', e type name, ' (not() takes bvecs)' at: t].
		(t text = '~' and: [e type isInteger not]) ifTrue: [self error: '~ needs an int or uint, not ', e type name at: t].
		((t text = '-' or: [t text = '+']) and: [e type isNumeric not]) ifTrue: [self error: t text, ' needs a number, not ', e type name at: t].
		(t text = '-' and: [e kind == #literal and: [e value first ~= $-]]) ifTrue: [
			^(self literal: '-', e value type: e type at: t) symbol: (e symbol isInteger ifTrue: [e symbol negated]); yourself].
		n := GlslNode kind: #unary at: t.
		^n op: t text; children: (Array with: e); type: e type; yourself].
	^self postfix
!
postfix
	| e |
	e := self primary.
	[| t |
	t := self peek.
	(t is: '[') ifTrue: [e := self index: e].
	(t is: '.') ifTrue: [e := self field: e].
	(t kind == #punct and: [#('++' '--') includes: t text]) ifTrue: [| n |
		self next.
		self checkWritable: e.
		e type isNumeric ifFalse: [self error: t text, ' needs a number, not ', e type name at: t].
		n := GlslNode kind: #postfix at: e.
		e := n op: t text; children: (Array with: e); type: e type; yourself].
	(t is: '[') | (t is: '.') | (t is: '++') | (t is: '--')] whileTrue.
	^e
!
primary
	| t v n |
	t := self peek.
	(#(#int #uint #float) includes: t kind) ifTrue: [
		self next.
		t kind == #float ifTrue: [^self literal: (self floatText: t text) type: GlslType float at: t].
		t kind == #uint ifTrue: [^(self literal: (t value printString, 'u') type: GlslType uint at: t) symbol: t value; yourself].
		^(self literal: (t value < 0 ifTrue: ['(int)', (t value + 16r100000000) printString, 'u'] ifFalse: [t value printString]) type: GlslType int at: t) symbol: t value; yourself].
	(t is: 'true') | (t is: 'false') ifTrue: [self next. ^self literal: t text type: GlslType bool at: t].
	(t is: '(') ifTrue: [
		self next.
		v := self expression.
		self expect: ')'.
		^v].
	t kind == #ident ifFalse: [self error: 'expected an expression, not ', self describePeek at: t].
	(self isTypeName: t) ifTrue: [^self constructor].
	((self peek: 1) is: '(') ifTrue: [^self call].
	(self class keywords includes: t text) ifTrue: [self error: 'expected an expression, not ', self describePeek at: t].
	self next.
	v := self lookup: t text.
	v isNil ifTrue: [self error: t text, ' is not declared', ((functions includesKey: t text) | (GlslBuiltins includes: t text) ifTrue: [' as a variable'] ifFalse: ['']) at: t].
	n := GlslNode kind: #ident at: t.
	^n symbol: v; type: v type; yourself
!
literal: aString type: aType at: aToken
	| n |
	n := GlslNode kind: #literal at: aToken.
	^n value: aString; type: aType; yourself
!
floatText: aString
	"A GLSL float literal as CUDA's float literal."
	| s |
	s := aString.
	(s includes: $.) | (s includes: $e) | (s includes: $E) ifFalse: [s := s, '.0'].
	s first = $. ifTrue: [s := '0', s].
	(s last = $.) ifTrue: [s := s, '0'].
	^s, 'f'
!
index: e
	| t i n type |
	t := self next.
	i := self expression.
	self expect: ']'.
	(i type = GlslType int or: [i type = GlslType uint]) ifFalse: [self error: 'an index is an int or a uint, not ', i type name at: i].
	type := e type isArray ifTrue: [e type element] ifFalse: [
		e type isVector ifTrue: [e type scalar] ifFalse: [
			e type isMatrix ifTrue: [e type column] ifFalse: [self error: e type name, ' cannot be indexed' at: t]]].
	(i kind == #literal and: [i symbol isInteger]) ifTrue: [| limit |
		limit := e type isArray ifTrue: [e type length] ifFalse: [e type isMatrix ifTrue: [e type cols] ifFalse: [e type size]].
		(i symbol between: 0 and: limit - 1) ifFalse: [self error: 'index ', i symbol printString, ' is out of range for ', e type name at: i]].
	n := GlslNode kind: #index at: e.
	^n children: (Array with: e with: i); type: type; yourself
!
field: e
	| t nameToken name type n |
	t := self next.
	nameToken := self expectIdentifier.
	name := nameToken text.
	(name = 'length' and: [self peekIs: '(']) ifTrue: [
		self next. self expect: ')'.
		(e type isArray or: [e type isVector or: [e type isMatrix]]) ifFalse: [self error: e type name, ' has no length()' at: nameToken].
		^(self literal: (e type isArray ifTrue: [e type length] ifFalse: [e type isMatrix ifTrue: [e type cols] ifFalse: [e type size]]) printString type: GlslType int at: e)
			symbol: (e type isArray ifTrue: [e type length] ifFalse: [e type isMatrix ifTrue: [e type cols] ifFalse: [e type size]]); yourself].
	e type isStruct ifTrue: [
		type := e type fieldNamed: name.
		type isNil ifTrue: [self error: e type name, ' has no field ', name at: nameToken].
		n := GlslNode kind: #member at: e.
		^n value: name; children: (Array with: e); type: type; yourself].
	e type isScalarOrVector ifFalse: [self error: e type name, ' has no field ', name at: nameToken].
	^self swizzle: e name: name at: nameToken
!
swizzle: e name: name at: aToken
	| sets set indices n base |
	sets := #('xyzw' 'rgba' 'stpq').
	set := sets detect: [:s | s includes: name first] ifNone: [nil].
	(set isNil or: [name size > 4 or: [(name allSatisfy: [:c | set includes: c]) not]]) ifTrue: [self error: name, ' is not a swizzle of ', e type name at: aToken].
	indices := name asArray collect: [:c | (set indexOf: c) - 1].
	(indices allSatisfy: [:i | i < e type size]) ifFalse: [self error: e type name, ' has no component ', name at: aToken].
	base := e.
	(e kind == #swizzle) ifTrue: [
		indices := indices collect: [:i | e value at: i + 1].
		base := e first].
	n := GlslNode kind: #swizzle at: e.
	^n value: indices; children: (Array with: base); type: (e type withSize: indices size); yourself
! !

!GlslShader methodsFor: 'calls'!
arguments
	| args |
	self expect: '('.
	args := OrderedCollection new.
	((self peekIs: 'void') and: [(self peek: 1) is: ')']) ifTrue: [self next].
	[self accept: ')'] whileFalse: [
		args isEmpty ifFalse: [self expect: ','].
		args add: self assignment].
	^args asArray
!
constructor
	| t type args n total |
	t := self peek.
	type := self typeSpecifier.
	(self peekIs: '(') ifFalse: [self error: 'expected ( after ', type name, ' (a constructor)' at: self peek].
	args := self arguments.
	n := GlslNode kind: #construct at: t.
	n type: type.
	(args anySatisfy: [:a | a type isVoid]) ifTrue: [self error: 'a constructor''s argument has no value' at: t].
	type isArray ifTrue: [
		(type length notNil and: [args size ~= type length]) ifTrue: [self error: type name, ' takes ', type length printString, ' elements, not ', args size printString at: t].
		args isEmpty ifTrue: [self error: 'an array needs at least one element' at: t].
		type length isNil ifTrue: [type := GlslType arrayOf: type element length: args size. n type: type].
		^n children: (args collect: [:a | self convert: a to: type element]); yourself].
	type isStruct ifTrue: [
		args size = type fields size ifFalse: [self error: type name, ' takes ', type fields size printString, ' values, not ', args size printString at: t].
		^n children: (args with: type fields collect: [:a :f | self convert: a to: f value]); yourself].
	type isVoid ifTrue: [self error: 'void has no constructor' at: t].
	args isEmpty ifTrue: [self error: type name, ' needs arguments' at: t].
	args do: [:a | (a type isScalarOrVector or: [a type isMatrix]) ifFalse: [self error: 'cannot make a ', type name, ' from a ', a type name at: a]].
	n children: args.
	type isScalar ifTrue: [
		args size = 1 ifFalse: [self error: type name, ' takes one value' at: t].
		^n].
	(args size = 1 and: [args first type isScalar]) ifTrue: [^n value: #splat; yourself].
	(type isMatrix and: [args size = 1 and: [args first type isMatrix]]) ifTrue: [^n value: #matrix; yourself].
	(args anySatisfy: [:a | a type isMatrix]) & type isVector ifTrue: [self error: 'cannot make a vector from a matrix' at: t].
	(args anySatisfy: [:a | a type isMatrix]) ifTrue: [self error: 'a matrix is made from one matrix, or from scalars and vectors' at: t].
	total := 0.
	args doWithIndex: [:a :i |
		total >= type size ifTrue: [self error: 'too many arguments for ', type name at: a].
		total := total + a type size].
	(type isMatrix and: [total ~= type size]) ifTrue: [self error: type name, ' takes ', type size printString, ' components, not ', total printString at: t].
	total < type size ifTrue: [self error: 'not enough components for ', type name, ': ', total printString at: t].
	^n value: #components; yourself
!
call
	| t name args n |
	t := self next.
	name := t text.
	(#('texture' 'texelFetch' 'textureLod' 'textureSize') includes: name) ifTrue: [self error: name, ': textures are not supported here' at: t].
	args := self arguments.
	(args anySatisfy: [:a | a type isVoid]) ifTrue: [self error: 'an argument of ', name, ' has no value' at: t].
	(GlslBuiltins includes: name) ifTrue: [^self builtin: name arguments: args at: t].
	(functions includesKey: name) ifFalse: [
		(self lookup: name) notNil ifTrue: [self error: name, ' is a variable, not a function' at: t].
		self error: 'no function ', name at: t].
	^self userCall: name arguments: args at: t
!
builtin: name arguments: args at: aToken
	| best n |
	best := self choose: (GlslBuiltins candidatesFor: name) params: [:c | c at: 2] outs: [:c | c at: 3] arguments: args name: name at: aToken.
	n := GlslNode kind: #builtin at: aToken.
	n value: (GlslBuiltins cudaName: name); type: best first; symbol: (best at: 3).
	n children: (self convert: args to: (best at: 2) outs: (best at: 3)).
	^n
!
userCall: name arguments: args at: aToken
	| f n |
	f := self choose: (functions at: name) params: [:g | g paramTypes] outs: [:g | g params collect: [:p | p mode ~~ #in]] arguments: args name: name at: aToken.
	f == current ifTrue: [self error: 'recursion is not allowed (', name, ')' at: aToken].
	called add: f.
	n := GlslNode kind: #call at: aToken.
	n symbol: f; type: f returnType.
	n children: (self convert: args to: f paramTypes outs: (f params collect: [:p | p mode ~~ #in])).
	^n
!
convert: args to: types outs: outs
	^(1 to: args size) collect: [:i |
		(outs at: i)
			ifTrue: [self checkWritable: (args at: i). args at: i]
			ifFalse: [self convert: (args at: i) to: (types at: i)]]
!
choose: candidates params: paramsBlock outs: outsBlock arguments: args name: name at: aToken
	"The candidate the arguments' types call: the one needing the fewest implicit conversions (out arguments need none)."
	| best bestCost tie |
	bestCost := nil. best := nil. tie := false.
	candidates do: [:c | | ps os cost |
		ps := paramsBlock value: c.
		os := outsBlock value: c.
		ps size = args size ifTrue: [
			cost := 0.
			1 to: ps size do: [:i | | p a |
				p := ps at: i.
				a := args at: i.
				cost notNil ifTrue: [
					a type = p
						ifFalse: [((os at: i) not and: [self canConvert: a type to: p]) ifTrue: [cost := cost + 1] ifFalse: [cost := nil]]]].
			cost notNil ifTrue: [
				(bestCost isNil or: [cost < bestCost]) ifTrue: [best := c. bestCost := cost. tie := false] ifFalse: [
					cost = bestCost ifTrue: [tie := true]]]]].
	best isNil ifTrue: [self error: 'no function ', name, '(', (args inject: '' into: [:s :a | s isEmpty ifTrue: [a type name] ifFalse: [s, ', ', a type name]]), ')', (self signaturesOf: candidates params: paramsBlock name: name) at: aToken].
	tie & (bestCost > 0) ifTrue: [self error: 'the call of ', name, ' is ambiguous' at: aToken].
	^best
!
signaturesOf: candidates params: paramsBlock name: name
	| shown |
	shown := candidates size > 6 ifTrue: [candidates first: 6] ifFalse: [candidates].
	shown isEmpty ifTrue: [^''].
	^'; there is ', (shown inject: '' into: [:s :c | (s isEmpty ifTrue: [''] ifFalse: [s, ', ']), name, '(', ((paramsBlock value: c) inject: '' into: [:x :p | x isEmpty ifTrue: [p name] ifFalse: [x, ', ', p name]]), ')']), (candidates size > 6 ifTrue: [', ...'] ifFalse: [''])
! !

!GlslShader methodsFor: 'typing'!
canConvert: from to: to
	"GLSL's implicit conversions: int to uint, int and uint to float, component-wise."
	from = to ifTrue: [^true].
	(from isScalarOrVector and: [to isScalarOrVector and: [from size = to size]]) ifFalse: [^false].
	from base == #int ifTrue: [^to base == #uint or: [to base == #float]].
	from base == #uint ifTrue: [^to base == #float].
	^false
!
convert: aNode to: aType
	"aNode as aType: itself, or converted implicitly; an error if GLSL does not convert it so."
	| n |
	aNode type = aType ifTrue: [^aNode].
	(self canConvert: aNode type to: aType) ifFalse: [self error: 'cannot convert ', aNode type name, ' to ', aType name at: aNode].
	^self cast: aNode to: aType
!
cast: aNode to: aType
	"aNode as aType (a scalar or vector of its size), converted explicitly."
	| n |
	aNode type = aType ifTrue: [^aNode].
	(aNode kind == #literal and: [aNode symbol isInteger and: [aType = GlslType float]]) ifTrue: [
		^self literal: aNode symbol printString, '.0f' type: aType at: aNode].
	(aNode kind == #literal and: [aNode symbol isInteger and: [aNode symbol >= 0 and: [aType = GlslType uint]]]) ifTrue: [
		^(self literal: aNode symbol printString, 'u' type: aType at: aNode) symbol: aNode symbol; yourself].
	n := GlslNode kind: #convert at: aNode.
	^n children: (Array with: aNode); type: aType; yourself
!
commonType: a and: b at: aToken
	a = b ifTrue: [^a].
	(self canConvert: a to: b) ifTrue: [^b].
	(self canConvert: b to: a) ifTrue: [^a].
	^self error: 'no common type of ', a name, ' and ', b name at: aToken
!
numericBase: a and: b
	"The base both convert to: float if either is, else uint if either is."
	(a base == #float or: [b base == #float]) ifTrue: [^#float].
	(a base == #uint or: [b base == #uint]) ifTrue: [^#uint].
	^#int
!
binary: op left: l right: r at: aToken
	| lt rt n type base cl cr |
	lt := l type. rt := r type.
	n := GlslNode kind: #binary at: l.
	n op: op.
	(#('&&' '||' '^^') includes: op) ifTrue: [
		(lt isBool and: [rt isBool]) ifFalse: [self error: op, ' needs bools, not ', lt name, ' and ', rt name at: aToken].
		^n children: (Array with: l with: r); type: GlslType bool; yourself].
	(lt isOpaque or: [rt isOpaque or: [lt isVoid or: [rt isVoid]]]) ifTrue: [
		(#('==' '!!=') includes: op) ifTrue: [self error: op, ' on structures and arrays is not supported here' at: aToken].
		self error: op, ' does not apply to ', lt name, ' and ', rt name at: aToken].
	(#('==' '!!=') includes: op) ifTrue: [
		type := self commonType: lt and: rt at: aToken.
		^n children: (Array with: (self convert: l to: type) with: (self convert: r to: type)); type: GlslType bool; yourself].
	(lt base == #bool or: [rt base == #bool]) ifTrue: [self error: op, ' does not apply to ', lt name, ' and ', rt name at: aToken].
	(#('<' '>' '<=' '>=') includes: op) ifTrue: [
		(lt isScalar and: [rt isScalar]) ifFalse: [self error: op, ' compares scalars, not ', lt name, ' and ', rt name, ' (lessThan() and the like compare vectors)' at: aToken].
		base := self numericBase: lt and: rt.
		^n children: (Array with: (self convert: l to: (lt withBase: base)) with: (self convert: r to: (rt withBase: base))); type: GlslType bool; yourself].
	(#('<<' '>>') includes: op) ifTrue: [
		(lt isInteger and: [rt isInteger]) ifFalse: [self error: op, ' needs ints or uints, not ', lt name, ' and ', rt name at: aToken].
		(lt isScalar and: [rt isVector]) ifTrue: [self error: 'cannot shift a scalar by a vector' at: aToken].
		(lt isVector and: [rt isVector and: [lt size ~= rt size]]) ifTrue: [self error: op, ' needs vectors of one size' at: aToken].
		^n children: (Array with: l with: (self cast: r to: (rt withBase: lt base))); type: lt; yourself].
	(#('%' '&' '|' '^') includes: op) & (lt isInteger not or: [rt isInteger not]) ifTrue: [
		self error: op, ' needs ints or uints, not ', lt name, ' and ', rt name at: aToken].
	base := self numericBase: lt and: rt.
	(lt isMatrix or: [rt isMatrix]) ifTrue: [
		cl := lt withBase: #float. cr := rt withBase: #float.
		lt isMatrix ifTrue: [cl := lt]. rt isMatrix ifTrue: [cr := rt].
		type := self matrixResult: op left: cl right: cr at: aToken.
		^n children: (Array with: (self convert: l to: cl) with: (self convert: r to: cr)); type: type; yourself].
	cl := lt withBase: base.
	cr := rt withBase: base.
	(lt isVector and: [rt isVector and: [lt size ~= rt size]]) ifTrue: [self error: op, ' needs vectors of one size, not ', lt name, ' and ', rt name at: aToken].
	type := lt isVector ifTrue: [cl] ifFalse: [cr].
	^n children: (Array with: (self convert: l to: cl) with: (self convert: r to: cr)); type: type; yourself
!
matrixResult: op left: lt right: rt at: aToken
	op = '*' ifTrue: [
		(lt isMatrix and: [rt isMatrix]) ifTrue: [
			lt cols = rt rows ifFalse: [self error: 'cannot multiply ', lt name, ' by ', rt name at: aToken].
			^GlslType matrixCols: rt cols rows: lt rows].
		(lt isMatrix and: [rt isVector]) ifTrue: [
			lt cols = rt size ifFalse: [self error: 'cannot multiply ', lt name, ' by ', rt name at: aToken].
			^lt column].
		(lt isVector and: [rt isMatrix]) ifTrue: [
			lt size = rt rows ifFalse: [self error: 'cannot multiply ', lt name, ' by ', rt name at: aToken].
			^GlslType base: #float size: rt cols].
		^lt isMatrix ifTrue: [lt] ifFalse: [rt]].
	(#('+' '-' '/') includes: op) ifFalse: [self error: op, ' does not apply to ', lt name, ' and ', rt name at: aToken].
	(lt isMatrix and: [rt isMatrix]) ifTrue: [
		lt = rt ifFalse: [self error: op, ' needs matrices of one size, not ', lt name, ' and ', rt name at: aToken].
		^lt].
	(lt isScalar or: [rt isScalar]) ifTrue: [^lt isMatrix ifTrue: [lt] ifFalse: [rt]].
	^self error: op, ' does not apply to ', lt name, ' and ', rt name at: aToken
!
checkWritable: aNode
	"Signal unless aNode is something a shader may assign to."
	| k |
	k := aNode kind.
	k == #ident ifTrue: [
		aNode symbol isWritable ifTrue: [^aNode symbol beWritten].
		^self error: 'cannot assign to ', aNode symbol name, (self whyNotWritable: aNode symbol) at: aNode].
	(k == #member or: [k == #index]) ifTrue: [^self checkWritable: aNode first].
	k == #swizzle ifTrue: [
		aNode value asSet size = aNode value size ifFalse: [self error: 'a swizzle with a component twice cannot be assigned to' at: aNode].
		^self checkWritable: aNode first].
	self error: 'cannot assign to this expression' at: aNode
!
whyNotWritable: aVariable
	aVariable isConst ifTrue: [^', a constant'].
	(#(#uniform #block) includes: aVariable storage) ifTrue: [^', a uniform'].
	aVariable storage == #input ifTrue: [^', an input'].
	^', a built-in'
!
constantValueOf: aNode
	"The Integer a constant integer expression has; an error if it is not one."
	| k a b |
	k := aNode kind.
	(k == #literal and: [aNode symbol isInteger]) ifTrue: [^aNode symbol].
	(k == #ident and: [aNode symbol constValue notNil]) ifTrue: [^aNode symbol constValue].
	(k == #convert and: [aNode type isInteger]) ifTrue: [^self constantValueOf: aNode first].
	(k == #unary and: [aNode op = '-']) ifTrue: [^(self constantValueOf: aNode first) negated].
	(k == #binary and: [#('+' '-' '*' '/' '%' '<<' '>>' '&' '|' '^') includes: aNode op]) ifTrue: [
		a := self constantValueOf: aNode first.
		b := self constantValueOf: aNode second.
		aNode op = '+' ifTrue: [^a + b].
		aNode op = '-' ifTrue: [^a - b].
		aNode op = '*' ifTrue: [^a * b].
		aNode op = '<<' ifTrue: [^a bitShift: b].
		aNode op = '>>' ifTrue: [^a bitShift: b negated].
		aNode op = '&' ifTrue: [^a bitAnd: b].
		aNode op = '|' ifTrue: [^a bitOr: b].
		aNode op = '^' ifTrue: [^a bitXor: b].
		b = 0 ifTrue: [self error: 'division by zero' at: aNode].
		aNode op = '/' ifTrue: [^a quo: b].
		^a rem: b].
	^self error: 'expected a constant integer expression' at: aNode
! !

!GlslShader class methodsFor: 'parsing'!
parse: aString
	"aString's shader, parsed and checked; a ShaderError if it does not compile."
	^self new parse: aString; yourself
! !

!GlslShader class methodsFor: 'names'!
keywords
	^#('if' 'else' 'for' 'while' 'do' 'switch' 'case' 'default' 'return' 'break' 'continue' 'discard' 'struct' 'true' 'false' 'const' 'uniform' 'in' 'out' 'inout' 'layout' 'precision' 'void')
!
cudaName: aString
	"aString as a name in CUDA C++: itself, unless C++ or CUDA has it (GLSL names have no __, so name__u is free)."
	Reserved isNil ifTrue: [
		Reserved := Set withAll: #('alignas' 'alignof' 'and' 'and_eq' 'asm' 'auto' 'bitand' 'bitor' 'catch' 'char' 'char8_t' 'char16_t' 'char32_t' 'class' 'compl' 'concept' 'consteval' 'constexpr' 'constinit' 'const_cast' 'co_await' 'co_return' 'co_yield' 'decltype' 'delete' 'double' 'dynamic_cast' 'enum' 'explicit' 'export' 'extern' 'friend' 'goto' 'inline' 'long' 'mutable' 'namespace' 'new' 'noexcept' 'not' 'not_eq' 'nullptr' 'operator' 'or' 'or_eq' 'private' 'protected' 'public' 'register' 'reinterpret_cast' 'requires' 'short' 'signed' 'sizeof' 'static' 'static_assert' 'static_cast' 'template' 'this' 'thread_local' 'throw' 'try' 'typedef' 'typeid' 'typename' 'union' 'unsigned' 'using' 'virtual' 'volatile' 'wchar_t' 'xor' 'xor_eq' 'threadIdx' 'blockIdx' 'blockDim' 'gridDim' 'warpSize' 'gl' 'gl_s' 'NULL' 'INFINITY' 'NAN' 'assert' 'offsetof' 'printf' 'main' 'std' 'cuda' 'int2' 'int3' 'int4' 'float2' 'float3' 'float4' 'uint2' 'uint3' 'uint4' 'dim3' 'size_t' 'uint')].
	^(Reserved includes: aString) ifTrue: [aString, '__u'] ifFalse: [aString]
! !
