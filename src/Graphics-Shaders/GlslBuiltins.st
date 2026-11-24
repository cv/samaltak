Object subclass: #GlslBuiltins
	instanceVariableNames: ''
	classVariableNames: 'Table'
	package: 'Graphics-Shaders'!

GlslBuiltins comment: 'I know GLSL''s built-in functions (GLSL 4.50 chapter 8, but for textures, images, atomics, packing and noise): their signatures, from which resolve:arguments: picks the one a call means. A signature is (result parameter...): F a float scalar or vector, I an int one, U a uint one, B a bool one (the same size wherever it occurs in a signature), G J K C the same but vectors only, f i u b the scalars, M a matrix, T its transpose, S a square matrix, a type name that type; out: before a parameter makes it an out parameter. GlslCudaWriter''s header defines each in namespace gl.'!

!GlslBuiltins class methodsFor: 'table'!
specs
	"name -> signatures."
	| d one |
	d := Dictionary new.
	one := [:names :sig | names do: [:n | (d at: n ifAbsentPut: [OrderedCollection new]) add: sig]].
	one value: #('radians' 'degrees' 'sin' 'cos' 'tan' 'asin' 'acos' 'atan' 'sinh' 'cosh' 'tanh' 'asinh' 'acosh' 'atanh' 'exp' 'log' 'exp2' 'log2' 'sqrt' 'inversesqrt' 'floor' 'trunc' 'round' 'roundEven' 'ceil' 'fract' 'normalize' 'dFdx' 'dFdy' 'fwidth' 'dFdxFine' 'dFdyFine' 'dFdxCoarse' 'dFdyCoarse') value: #('F' 'F').
	one value: #('atan' 'pow') value: #('F' 'F' 'F').
	one value: #('abs' 'sign') value: #('F' 'F').
	one value: #('abs' 'sign') value: #('I' 'I').
	one value: #('mod') value: #('F' 'F' 'f').
	one value: #('mod') value: #('F' 'F' 'F').
	one value: #('modf') value: #('F' 'F' 'out:F').
	#('min' 'max') do: [:n |
		#(#('F' 'F' 'F') #('F' 'F' 'f') #('I' 'I' 'I') #('I' 'I' 'i') #('U' 'U' 'U') #('U' 'U' 'u')) do: [:s | one value: (Array with: n) value: s]].
	#(#('F' 'F' 'F' 'F') #('F' 'F' 'f' 'f') #('I' 'I' 'I' 'I') #('I' 'I' 'i' 'i') #('U' 'U' 'U' 'U') #('U' 'U' 'u' 'u')) do: [:s | one value: #('clamp') value: s].
	#(#('F' 'F' 'F' 'F') #('F' 'F' 'F' 'f') #('F' 'F' 'F' 'B')) do: [:s | one value: #('mix') value: s].
	one value: #('step') value: #('F' 'F' 'F').
	one value: #('step') value: #('F' 'f' 'F').
	one value: #('smoothstep') value: #('F' 'F' 'F' 'F').
	one value: #('smoothstep') value: #('F' 'f' 'f' 'F').
	one value: #('isnan' 'isinf') value: #('B' 'F').
	one value: #('floatBitsToInt') value: #('I' 'F').
	one value: #('floatBitsToUint') value: #('U' 'F').
	one value: #('intBitsToFloat') value: #('F' 'I').
	one value: #('uintBitsToFloat') value: #('F' 'U').
	one value: #('fma') value: #('F' 'F' 'F' 'F').
	one value: #('length') value: #('f' 'F').
	one value: #('distance' 'dot') value: #('f' 'F' 'F').
	one value: #('cross') value: #('vec3' 'vec3' 'vec3').
	one value: #('faceforward') value: #('F' 'F' 'F' 'F').
	one value: #('reflect') value: #('F' 'F' 'F').
	one value: #('refract') value: #('F' 'F' 'F' 'f').
	one value: #('matrixCompMult') value: #('M' 'M' 'M').
	one value: #('transpose') value: #('T' 'M').
	one value: #('determinant') value: #('f' 'S').
	one value: #('inverse') value: #('S' 'S').
	#('lessThan' 'lessThanEqual' 'greaterThan' 'greaterThanEqual' 'equal' 'notEqual') do: [:n |
		#(#('C' 'G' 'G') #('C' 'J' 'J') #('C' 'K' 'K')) do: [:s | one value: (Array with: n) value: s]].
	one value: #('equal' 'notEqual') value: #('C' 'C' 'C').
	one value: #('any' 'all') value: #('b' 'C').
	one value: #('not') value: #('C' 'C').
	^d
!
table
	^Table ifNil: [Table := self specs]
!
includes: aString
	^(self table includesKey: aString) or: [aString = 'outerProduct']
!
cudaName: aString
	^aString = 'not' ifTrue: ['gl::not_'] ifFalse: ['gl::', aString]
! !

!GlslBuiltins class methodsFor: 'resolving'!
instances: aSignature
	"Each instantiation of aSignature: (result paramTypes outFlags)."
	| letters generic sizes out |
	letters := aSignature inject: Set new into: [:s :p | | q | q := (p beginsWith: 'out:') ifTrue: [p copyFrom: 5 to: p size] ifFalse: [p]. q size = 1 ifTrue: [s add: q first]. s].
	out := OrderedCollection new.
	generic := letters detect: [:c | 'FIUBGJKC' includes: c] ifNone: [nil].
	(letters includes: $M) ifTrue: [
		2 to: 4 do: [:c | 2 to: 4 do: [:r | out add: (self instance: aSignature size: nil matrix: (GlslType matrixCols: c rows: r))]].
		^out].
	(letters includes: $S) ifTrue: [
		2 to: 4 do: [:n | out add: (self instance: aSignature size: nil matrix: (GlslType matrixCols: n rows: n))].
		^out].
	generic isNil ifTrue: [^Array with: (self instance: aSignature size: 1 matrix: nil)].
	sizes := ('GJKC' includes: generic) ifTrue: [2 to: 4] ifFalse: [1 to: 4].
	sizes do: [:n | out add: (self instance: aSignature size: n matrix: nil)].
	^out
!
instance: aSignature size: n matrix: aMatrix
	| types outs |
	outs := OrderedCollection new.
	types := aSignature collect: [:p | | q |
		q := p.
		(p beginsWith: 'out:') ifTrue: [q := p copyFrom: 5 to: p size. outs add: true] ifFalse: [outs add: false].
		self type: q size: n matrix: aMatrix].
	^Array with: types first with: types allButFirst with: outs allButFirst asArray
!
type: aString size: n matrix: aMatrix
	| c i |
	aString size > 1 ifTrue: [^GlslType named: aString].
	c := aString first.
	('MS' includes: c) ifTrue: [^aMatrix].
	c = $T ifTrue: [^aMatrix transposed].
	i := 'fiub' indexOf: c.
	i > 0 ifTrue: [^GlslType named: (#('float' 'int' 'uint' 'bool') at: i)].
	i := 'FIUBGJKC' indexOf: c.
	^GlslType base: (#(#float #int #uint #bool) at: i - 1 \\ 4 + 1) size: n
!
candidatesFor: aString
	"(result paramTypes outFlags) of each instantiation of the built-in aString."
	| all |
	aString = 'outerProduct' ifTrue: [
		all := OrderedCollection new.
		2 to: 4 do: [:c | 2 to: 4 do: [:r |
			all add: (Array with: (GlslType matrixCols: c rows: r) with: (Array with: (GlslType base: #float size: r) with: (GlslType base: #float size: c)) with: #(false false))]].
		^all].
	all := OrderedCollection new.
	(self table at: aString ifAbsent: [#()]) do: [:sig |
		(self instances: sig) do: [:inst | (all anySatisfy: [:a | (a at: 2) = (inst at: 2)]) ifFalse: [all add: inst]]].
	^all
! !
