Object subclass: #TStencilContext
	instanceVariableNames: 'compiler holes continuations'
	classVariableNames: ''
	package: 'VM-Translator'!

TStencilContext comment: 'What the translation of one stencil (JitStencils) collects: the holes and continuations it uses; compiler is the class whose HOLE_ and CONT_ constants name them (JitStencilCompiler).'!

!TStencilContext class methodsFor: 'instance creation'!
compiler: aClass
	^self new setCompiler: aClass
! !

!TStencilContext methodsFor: 'initialization'!
setCompiler: aClass
	compiler := aClass.
	holes := Set new.
	continuations := Set new
! !

!TStencilContext methodsFor: 'accessing'!
compiler
	^compiler
!
noteHole: aString
	(compiler classPool includesKey: ('HOLE_' , aString) asSymbol) ifFalse: [^false].
	holes add: aString.
	^true
!
noteContinuation: aString
	(compiler classPool includesKey: ('CONT_' , aString) asSymbol) ifFalse: [^false].
	continuations add: aString.
	^true
!
holeId: aString
	^compiler classPool at: ('HOLE_' , aString) asSymbol
!
continuationCode: aString
	^compiler classPool at: ('CONT_' , aString) asSymbol
!
holes
	"The holes used, in the order of their ids (the parameters of a threaded stencil)."
	^(holes asSortedCollection: [:a :b | (self holeId: a) <= (self holeId: b)]) asArray
!
holeMask
	^holes inject: 0 into: [:m :h | m bitOr: (1 bitShift: (self holeId: h))]
!
continuationMask
	^continuations inject: 0 into: [:m :c | m bitOr: (1 bitShift: (self continuationCode: c))]
! !

TCFunction subclass: #TCStencil
	instanceVariableNames: 'case context threaded'
	classVariableNames: ''
	package: 'VM-Translator'!

TCStencil comment: 'I am a translated stencil: copy case of a JitStencils method. Printed for copy-and-patch (threaded: false) a preserve_none function of the state: its holes are extern symbols, its continuations musttail calls of extern functions; printed for call threading a function of its holes that returns its continuation, the state in fixed registers. The body is the same: the macros JIT_SET, JIT_HOLE, JIT_TAIL and JIT_CALL differ.'!

!TCStencil methodsFor: 'initialization'!
setFunction: aTFunction case: anInteger context: aTStencilContext locals: aCollection body: aCBlock
	self setFunction: aTFunction locals: aCollection body: aCBlock.
	case := anInteger.
	context := aTStencilContext.
	threaded := false
! !

!TCStencil methodsFor: 'accessing'!
case
	^case
!
context
	^context
!
threaded: aBoolean
	"Print as the threaded function from now on (or as the copy-and-patch one)."
	threaded := aBoolean
!
stencilName
	"pushTemp, or pushTemp 3 for a stencil with cases"
	^function hasCases
		ifTrue: [function selector , ' ' , case printString]
		ifFalse: [function selector asString]
!
cName
	^(threaded ifTrue: ['thr_'] ifFalse: ['stencil_']) , function cName , (function hasCases ifTrue: ['_' , case printString] ifFalse: [''])
!
prototype
	"A threaded stencil takes its holes but SITE (the return address), in the order of their ids, and returns its continuation."
	threaded ifFalse: [^'JIT_STENCIL_FN void ' , self cName , '(JIT_ARGS)'].
	^String new: 100 streamContents: [:s |
		| holes |
		holes := context holes reject: [:h | h = 'SITE'].
		s nextPutAll: 'static uint64_t '; nextPutAll: self cName; nextPut: $(.
		holes isEmpty ifTrue: [s nextPutAll: 'void'].
		holes do: [:h | s nextPutAll: 'uint64_t hole_'; nextPutAll: h] separatedBy: [s nextPutAll: ', '].
		s nextPut: $)]
! !

!TCStencil methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: '/* '; print: function.
	function hasCases ifTrue: [aStream nextPutAll: ' case '; print: case].
	aStream nextPutAll: ' */'; lf.
	aStream nextPutAll: self prototype; lf; nextPut: ${.
	locals do: [:d | aStream lf; nextPutAll: '    '. d printCOn: aStream indent: 1].
	body printStatementsOn: aStream indent: 1.
	aStream lf; nextPut: $}; lf
! !

!TCodeGenerator methodsFor: 'stencils'!
generateStencil: aTFunction case: anInteger
	"Answer the TCStencil of copy anInteger of stencil aTFunction."
	| body |
	function := aTFunction.
	cModule := aTFunction module.
	locals := OrderedCollection new.
	usedNames := Set new.
	labelCounter := 0.
	labelParameters := Dictionary new.
	interpreterLoop := false.
	stencil := TStencilContext compiler: cModule moduleClass stencilCompiler.
	cModule registers do: [:r | usedNames add: (cModule globalNamed: r) cName].
	frame := TFrame kind: #stencil function: aTFunction module: cModule parent: nil.
	frame bytecode: anInteger.
	env := frame env.
	body := CBlock new.
	block := body.
	self declareTemporariesOf: aTFunction in: frame.
	aTFunction statements do: [:s | self statement: s].
	body endsControlFlow ifFalse: [self error: 'every path of a stencil ends with a continuation (^self continue, ...)' node: nil].
	^TCStencil new setFunction: aTFunction case: anInteger context: stencil locals: locals body: body
!
stencilReturn: aNode
	"In a stencil: ^self aContinuation, or ^self anInlineMethod whose returns are the stencil's."
	| f |
	(aNode isMessage and: [aNode receiver isVariable and: [aNode receiver isSelf]]) ifTrue: [
		f := translator lookup: aNode selector in: frame module.
		(f notNil and: [f kind == #continuation]) ifTrue: [^self statement: aNode].
		(self inlineTailCall: aNode) ifTrue: [^self]].
	self error: 'a stencil returns by a continuation (^self continue, ...) or an inline method that does' node: aNode
!
stencilLanguage: aTFunction arguments: argNodes node: aNode
	"The stencils' own sends: continuations (JIT_TAIL), holes (JIT_HOLE), the case, calls of compiled code (JIT_CALL)."
	| k uint64 name |
	stencil isNil ifTrue: [^self error: aTFunction selector , ' is only for stencils' node: aNode].
	k := aTFunction kind.
	uint64 := translator registry at: 'uint64_t'.
	k == #stencilCase ifTrue: [^self integerConstant: frame bytecode hex: false].
	k == #hole ifTrue: [
		(argNodes first isLiteral and: [argNodes first value isSymbol]) ifFalse: [^self error: 'a hole is named by a symbol' node: aNode].
		name := argNodes first value asString.
		(stencil noteHole: name) ifFalse: [^self error: 'no hole HOLE_' , name , ' in ' , stencil compiler name node: aNode].
		^CRaw pureText: 'JIT_HOLE(' , name , ')' type: uint64].
	k == #callCompiled ifTrue: [
		| e |
		e := self expression: argNodes first.
		self requireInteger: e node: aNode.
		block add: (CExprStatement expression: (CCall function: 'JIT_CALL' arguments: (Array with: (self cast: e to: uint64)) type: (translator registry at: 'void'))).
		^nil].
	name := (aTFunction pragmaAt: #continuation:) first asString.
	(stencil noteContinuation: name) ifFalse: [^self error: 'no continuation CONT_' , name , ' in ' , stencil compiler name node: aNode].
	block add: (CExprStatement expression: ((CCall function: 'JIT_TAIL' arguments: (Array with: (CRaw pureText: name type: uint64)) type: (translator registry at: 'void')) noReturn: true; yourself)).
	^nil
!
stencilRegister: target set: value node: aNode valueWanted: aBoolean
	"A stencil's register is written by JIT_SET (threaded: a move the compiler keeps where it is)."
	aBoolean ifTrue: [^self error: 'a stencil''s register is assigned in a statement' node: aNode].
	self checkAssignable: value to: target type node: aNode.
	block add: (CExprStatement expression: (CCall function: 'JIT_SET' arguments: (Array with: target with: (self coerce: value to: target type node: aNode)) type: (translator registry at: 'void'))).
	^nil
! !
