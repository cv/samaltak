Object subclass: #GlslNode
	instanceVariableNames: 'kind line column type op children symbol value'
	classVariableNames: ''
	package: 'Graphics-Shaders'!

GlslNode comment: 'I am a node of a GLSL shader''s syntax tree, typed as GlslShader parses it. kind says what: expressions #literal (value: its CUDA text), #ident (symbol: a GlslVariable), #binary #unary #postfix #assign (op), #ternary, #comma, #convert (to type), #construct (type), #builtin (value: the CUDA function), #call (symbol: a GlslFunction), #swizzle (value: the component indices), #member (value: the field name), #index; statements #block #decl #var (symbol, its initializer as child) #expr #if #for #while #do #return #break #continue #discard #switch #case #empty. children are the operands or parts in order (nil where a part is left out); line and column are where the node starts.'!

!GlslNode methodsFor: 'accessing'!
kind
	^kind
!
line
	^line
!
column
	^column
!
type
	^type
!
type: aType
	type := aType
!
op
	^op
!
op: aString
	op := aString
!
children
	^children
!
children: anArray
	children := anArray
!
first
	^children first
!
second
	^children at: 2
!
symbol
	^symbol
!
symbol: anObject
	symbol := anObject
!
value
	^value
!
value: anObject
	value := anObject
!
setKind: aSymbol line: l column: c
	kind := aSymbol. line := l. column := c. children := #()
!
printOn: aStream
	aStream nextPutAll: 'GlslNode('; print: kind; space; print: type; nextPut: $)
! !

!GlslNode class methodsFor: 'instance creation'!
kind: aSymbol at: aTokenOrNode
	^self new setKind: aSymbol line: aTokenOrNode line column: aTokenOrNode column
! !
