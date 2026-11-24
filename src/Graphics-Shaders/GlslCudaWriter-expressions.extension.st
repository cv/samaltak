!GlslCudaWriter methodsFor: 'expressions'!
expr: aNode
	"aNode as a CUDA C++ expression."
	| k path |
	k := aNode kind.
	path := self uniformPath: aNode.
	path notNil ifTrue: [
		(aNode kind == #ident and: [aNode symbol storage == #block]) ifTrue: [self fail: 'the uniform block is no value; use its members' at: aNode].
		^self load: aNode type base: 'gl_c.u' at: path].
	k == #literal ifTrue: [^aNode value].
	k == #ident ifTrue: [^aNode symbol cuda].
	k == #binary ifTrue: [
		aNode op = '^^' ifTrue: [^'(', (self expr: aNode first), ' !!= ', (self expr: aNode second), ')'].
		^'(', (self expr: aNode first), ' ', aNode op, ' ', (self expr: aNode second), ')'].
	k == #unary ifTrue: [
		(aNode op = '++' or: [aNode op = '--']) ifTrue: [^'(', aNode op, (self scalarLvalue: aNode first), ')'].
		^'(', aNode op, (self expr: aNode first), ')'].
	k == #postfix ifTrue: [^'(', (self scalarLvalue: aNode first), aNode op, ')'].
	k == #assign ifTrue: [^self assignment: aNode].
	k == #ternary ifTrue: [^'(', (self expr: aNode first), ' ? ', (self expr: aNode second), ' : ', (self expr: (aNode children at: 3)), ')'].
	k == #comma ifTrue: [^'(', (aNode children inject: '' into: [:s :c | s isEmpty ifTrue: [self expr: c] ifFalse: [s, ', ', (self expr: c)]]), ')'].
	k == #convert ifTrue: [
		aNode type isScalar ifTrue: [^'((', aNode type cuda, ')(', (self expr: aNode first), '))'].
		^'gl::mk<', aNode type cuda, '>(', (self expr: aNode first), ')'].
	k == #construct ifTrue: [^self construct: aNode].
	k == #builtin ifTrue: [^aNode value, '(', (self arguments: aNode children outs: aNode symbol), ')'].
	k == #call ifTrue: [
		^aNode symbol cuda, '(gl_c', (aNode children isEmpty ifTrue: [''] ifFalse: [', ', (self arguments: aNode children outs: (aNode symbol params collect: [:p | p mode ~~ #in]))]), ')'].
	k == #swizzle ifTrue: [^self swizzle: aNode].
	k == #member ifTrue: [^'(', (self expr: aNode first), ').', (GlslShader cudaName: aNode value)].
	k == #index ifTrue: [^(self expr: aNode first), '[', (self expr: aNode second), ']'].
	^self error: 'no expression ', k
!
arguments: nodes outs: outs
	| s |
	s := WriteStream on: String new.
	nodes doWithIndex: [:a :i |
		i > 1 ifTrue: [s nextPutAll: ', '].
		s nextPutAll: ((outs notNil and: [outs at: i])
			ifTrue: [self outArgument: a]
			ifFalse: [self expr: a])].
	^s contents
!
outArgument: aNode
	(aNode kind == #swizzle and: [aNode value size > 1]) ifTrue: [self fail: 'a swizzle of several components cannot be an out argument here' at: aNode].
	^self lvalue: aNode
!
assignment: aNode
	| l |
	l := aNode first.
	(l kind == #swizzle and: [l value size > 1 and: [(#('=' '+=' '-=' '*=' '/=') includes: aNode op) not]]) ifTrue: [
		self fail: aNode op, ' on a swizzle is not supported here' at: aNode].
	^'(', (self lvalue: l), ' ', aNode op, ' ', (self expr: aNode second), ')'
!
scalarLvalue: aNode
	(aNode kind == #swizzle and: [aNode value size > 1]) ifTrue: [self fail: '++ and -- on a swizzle are not supported here' at: aNode].
	^self lvalue: aNode
!
lvalue: aNode
	"aNode as something CUDA can assign to (a swizzle of several components is a gl::swref)."
	| k |
	k := aNode kind.
	k == #ident ifTrue: [^aNode symbol cuda].
	k == #member ifTrue: [^(self lvalue: aNode first), '.', (GlslShader cudaName: aNode value)].
	k == #index ifTrue: [^(self lvalue: aNode first), '[', (self expr: aNode second), ']'].
	k == #swizzle ifTrue: [
		aNode value size = 1 ifTrue: [^(self lvalue: aNode first), '.', (self component: aNode value first)].
		^'gl::swz<', (self indices: aNode value), '>(', (self lvalue: aNode first), ')'].
	^self fail: 'cannot assign to this' at: aNode
!
component: i
	^#('x' 'y' 'z' 'w') at: i + 1
!
indices: anArray
	^anArray inject: '' into: [:s :i | s isEmpty ifTrue: [i printString] ifFalse: [s, ', ', i printString]]
!
swizzle: aNode
	| base |
	base := self expr: aNode first.
	aNode first type isScalar ifTrue: [
		aNode value size = 1 ifTrue: [^base].
		^'gl::splat<', aNode type cuda, '>(', base, ')'].
	aNode value size = 1 ifTrue: [^'(', base, ').', (self component: aNode value first)].
	^'gl::sw<', (self indices: aNode value), '>(', base, ')'
!
construct: aNode
	| t args |
	t := aNode type.
	args := aNode children collect: [:c | self expr: c].
	t isArray ifTrue: [^t cuda, '{{', (self join: args), '}}'].
	t isStruct ifTrue: [^t cuda, '{', (self join: args), '}'].
	t isScalar ifTrue: [| a |
		a := aNode first type isScalar ifTrue: [args first] ifFalse: [
			aNode first type isMatrix ifTrue: ['(', args first, ').c[0].x'] ifFalse: ['(', args first, ').x']].
		^'((', t cuda, ')(', a, '))'].
	aNode value == #splat ifTrue: [
		^(t isMatrix ifTrue: ['gl::diag<'] ifFalse: ['gl::splat<']), t cuda, '>(', args first, ')'].
	aNode value == #matrix ifTrue: [^'gl::mconv<', t cuda, '>(', args first, ')'].
	^(t isMatrix ifTrue: ['gl::mkm<'] ifFalse: ['gl::mk<']), t cuda, '>(', (self join: args), ')'
!
join: strings
	^strings inject: '' into: [:s :x | s isEmpty ifTrue: [x] ifFalse: [s, ', ', x]]
!
fail: aString at: aNode
	^ShaderError line: aNode line column: aNode column detail: aString
! !

!GlslCudaWriter methodsFor: 'uniforms'!
uniformPath: aNode
	"The byte offset (a CUDA expression) of what aNode reads in the uniform block, nil if it reads none."
	| k base |
	k := aNode kind.
	k == #ident ifTrue: [
		aNode symbol storage == #uniform ifTrue: [^aNode symbol offset printString].
		aNode symbol storage == #block ifTrue: [^'0'].
		^nil].
	k == #member ifTrue: [
		base := self uniformPath: aNode first.
		base isNil ifTrue: [^nil].
		^self add: base and: (aNode first type std140OffsetOf: aNode value) printString].
	(k == #index and: [aNode first type isArray]) ifTrue: [
		base := self uniformPath: aNode first.
		base isNil ifTrue: [^nil].
		^self add: base and: '(', (self expr: aNode second), ') * ', aNode first type element std140Stride printString].
	^nil
!
add: a and: b
	a = '0' ifTrue: [^b].
	b = '0' ifTrue: [^a].
	^a, ' + ', b
!
load: aType base: b at: offset
	"A CUDA expression reading aType at offset (a CUDA expression) from the uniforms at b (a const char*)."
	aType isMatrix ifTrue: [^'gl::uloadm<', aType cuda, '>(', b, ', ', offset, ')'].
	(aType isVector and: [aType base == #bool]) ifTrue: [^'gl::uloadb<', aType cuda, '>(', b, ', ', offset, ')'].
	aType isScalarOrVector ifTrue: [^'gl::uload<', aType cuda, '>(', b, ', ', offset, ')'].
	^(self loaderFor: aType), '(', b, ', ', offset, ')'
!
loaderFor: aType
	"The name of a function loading aType (a structure or array) from uniforms, written on first use."
	^loaders at: aType ifAbsent: [| name body |
		name := 'gl_ul', loaders size printString.
		loaders at: aType put: name.
		"The loaders this one calls are written first."
		body := String streamContents: [:s |
			aType isArray
				ifTrue: [
					s nextPutAll: ' for (int i = 0; i < '; print: aType length; nextPutAll: '; i++) r[i] = ';
						nextPutAll: (self load: aType element base: 'b' at: 'o + i * ', aType element std140Stride printString); nextPut: $;]
				ifFalse: [
					aType fields do: [:f |
						s nextPutAll: ' r.'; nextPutAll: (GlslShader cudaName: f key); nextPutAll: ' = ';
							nextPutAll: (self load: f value base: 'b' at: 'o + ', (aType std140OffsetOf: f key) printString); nextPut: $;]]].
		loaderOut nextPutAll: 'static __device__ __forceinline__ '; nextPutAll: aType cuda; space; nextPutAll: name;
			nextPutAll: '(const char* b, int o) { '; nextPutAll: aType cuda; nextPutAll: ' r;'; nextPutAll: body; nextPutAll: ' return r; }'; nextPut: Character lf.
		name]
! !

!GlslCudaWriter class methodsFor: 'writing'!
cudaFor: aGlslShader
	"The CUDA C++ source of aGlslShader, the kernel gl_fragment."
	^self new write: aGlslShader
! !
