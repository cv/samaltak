Object subclass: #GlslType
	instanceVariableNames: 'name kind base rows cols fields element length isBlock'
	classVariableNames: 'Named'
	package: 'Graphics-Shaders'!

GlslType comment: 'I am a GLSL type: void, a scalar (base #float #int #uint #bool), a vector (rows components of base), a matrix (cols columns of rows floats), a structure (fields: name -> type Associations; isBlock for a uniform block''s members), or an array (length elements of element). The built-in ones are unique (named:); structures are equal only to themselves, arrays by element and length. cuda is my type in CUDA C++ (GlslCudaWriter''s header, namespace gl); std140Alignment and std140Size lay me out in a uniform block.'!

!GlslType methodsFor: 'initialization'!
setName: aString kind: aSymbol base: baseSymbol rows: r cols: c
	name := aString. kind := aSymbol. base := baseSymbol. rows := r. cols := c. isBlock := false
!
setStruct: aString fields: anArray
	name := aString. kind := #struct. fields := anArray. isBlock := false
!
setElement: aType length: n
	kind := #array. element := aType. length := n. isBlock := false.
	name := aType name, '[', n printString, ']'
!
beBlock
	isBlock := true
! !

!GlslType methodsFor: 'accessing'!
name
	^name
!
kind
	^kind
!
base
	^base
!
rows
	^rows
!
cols
	^cols
!
fields
	^fields
!
element
	^element
!
length
	^length
!
isBlock
	^isBlock
!
fieldNamed: aString
	^(fields detect: [:f | f key = aString] ifNone: [nil]) ifNotNil: [:f | f value]
! !

!GlslType methodsFor: 'testing'!
isVoid
	^kind == #void
!
isScalar
	^kind == #scalar
!
isVector
	^kind == #vector
!
isMatrix
	^kind == #matrix
!
isStruct
	^kind == #struct
!
isArray
	^kind == #array
!
isScalarOrVector
	^kind == #scalar or: [kind == #vector]
!
isNumeric
	"A scalar, vector or matrix of numbers (not bool)."
	^(kind == #scalar or: [kind == #vector or: [kind == #matrix]]) and: [base ~~ #bool]
!
isBool
	^kind == #scalar and: [base == #bool]
!
isFloat
	^base == #float
!
isInteger
	"int or uint, a scalar or vector."
	^(base == #int or: [base == #uint]) and: [self isScalarOrVector]
!
isOpaque
	"Something no operator applies to: a structure or an array."
	^kind == #struct or: [kind == #array]
!
size
	"Components: 1 for a scalar."
	kind == #scalar ifTrue: [^1].
	kind == #vector ifTrue: [^rows].
	kind == #matrix ifTrue: [^rows * cols].
	^0
! !

!GlslType methodsFor: 'deriving'!
scalar
	^self class base: base size: 1
!
withBase: aSymbol
	"The scalar or vector of my size with components aSymbol."
	^self class base: aSymbol size: self size
!
withSize: n
	^self class base: base size: n
!
column
	"A matrix's column type."
	^self class base: #float size: rows
!
transposed
	^self class matrixCols: rows rows: cols
! !

!GlslType methodsFor: 'comparing'!
= other
	self == other ifTrue: [^true].
	(other isKindOf: GlslType) ifFalse: [^false].
	kind == #array ifTrue: [^other kind == #array and: [length = other length and: [element = other element]]].
	^false
!
hash
	kind == #array ifTrue: [^element hash + length].
	^name hash
! !

!GlslType methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: name
! !

!GlslType methodsFor: 'cuda'!
cuda
	"My type in CUDA C++."
	kind == #void ifTrue: [^'void'].
	kind == #scalar ifTrue: [^base == #uint ifTrue: ['unsigned'] ifFalse: [base asString]].
	(kind == #vector or: [kind == #matrix]) ifTrue: [^'gl::', name].
	kind == #struct ifTrue: [^GlslShader cudaName: name].
	^'gl::arr<', element cuda, ', ', length printString, '>'
! !

!GlslType methodsFor: 'std140'!
std140Alignment
	kind == #scalar ifTrue: [^4].
	kind == #vector ifTrue: [^rows = 2 ifTrue: [8] ifFalse: [16]].
	kind == #matrix ifTrue: [^16].
	kind == #array ifTrue: [^element std140Alignment max: 16].
	^fields inject: 16 into: [:a :f | a max: f value std140Alignment]
!
std140Stride
	"An array element's stride."
	^self std140Size + 15 // 16 * 16
!
std140Size
	| at |
	kind == #scalar ifTrue: [^4].
	kind == #vector ifTrue: [^rows * 4].
	kind == #matrix ifTrue: [^cols * 16].
	kind == #array ifTrue: [^element std140Stride * length].
	at := 0.
	fields do: [:f | at := (self class align: at to: f value std140Alignment) + f value std140Size].
	^self class align: at to: 16
!
std140OffsetOf: aFieldName
	| at |
	at := 0.
	fields do: [:f |
		at := self class align: at to: f value std140Alignment.
		f key = aFieldName ifTrue: [^at].
		at := at + f value std140Size].
	^nil
! !

!GlslType class methodsFor: 'types'!
named: aString
	"The built-in type aString (float, vec3, mat4x3, ...), nil if there is none."
	Named isNil ifTrue: [self makeNamed].
	^Named at: aString ifAbsent: [nil]
!
void
	^self named: 'void'
!
float
	^self named: 'float'
!
int
	^self named: 'int'
!
uint
	^self named: 'uint'
!
bool
	^self named: 'bool'
!
base: aSymbol size: n
	"The scalar (n = 1) or vector of n components aSymbol."
	n = 1 ifTrue: [^self named: aSymbol asString].
	^self named: (#('' 'i' 'u' 'b') at: (#(#float #int #uint #bool) indexOf: aSymbol)), 'vec', n printString
!
matrixCols: c rows: r
	^self named: (c = r ifTrue: ['mat', c printString] ifFalse: ['mat', c printString, 'x', r printString])
!
struct: aString fields: anArray
	^self new setStruct: aString fields: anArray
!
arrayOf: aType length: n
	^self new setElement: aType length: n
!
align: n to: a
	^n + a - 1 // a * a
!
makeNamed
	| d |
	d := Dictionary new.
	d at: 'void' put: (self new setName: 'void' kind: #void base: nil rows: 0 cols: 0).
	#(#float #int #uint #bool) doWithIndex: [:b :i |
		d at: b asString put: (self new setName: b asString kind: #scalar base: b rows: 1 cols: 1).
		2 to: 4 do: [:n | | nm |
			nm := (#('' 'i' 'u' 'b') at: i), 'vec', n printString.
			d at: nm put: (self new setName: nm kind: #vector base: b rows: n cols: 1)]].
	2 to: 4 do: [:c |
		2 to: 4 do: [:r | | nm |
			nm := 'mat', c printString, 'x', r printString.
			d at: nm put: (self new setName: (c = r ifTrue: ['mat', c printString] ifFalse: [nm]) kind: #matrix base: #float rows: r cols: c)].
		d at: 'mat', c printString put: (d at: 'mat', c printString, 'x', c printString)].
	Named := d
! !
