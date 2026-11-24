Object subclass: #GlslVariable
	instanceVariableNames: 'name type storage mode cuda init constValue offset line column isConst isWritten'
	classVariableNames: ''
	package: 'Graphics-Shaders'!

GlslVariable comment: 'I am a variable of a GLSL shader: name and type; storage #local, #param (mode #in #out #inout), #const (a constant at the top level: init its initializer), #global (a variable at the top level), #uniform (a member of the uniform block without an instance name: offset its std140 offset), #block (the uniform block''s instance), #input (uv, size), #output (the colour), #builtin (gl_FragCoord); cuda is what names me in CUDA C++; constValue my Integer value when I am a constant integer.'!

!GlslVariable methodsFor: 'accessing'!
name
	^name
!
type
	^type
!
storage
	^storage
!
type: aType
	type := aType
!
mode
	^mode
!
mode: aSymbol
	mode := aSymbol
!
cuda
	^cuda
!
cuda: aString
	cuda := aString
!
init
	^init
!
init: aNode
	init := aNode
!
constValue
	^constValue
!
constValue: anInteger
	constValue := anInteger
!
offset
	^offset
!
offset: anInteger
	offset := anInteger
!
line
	^line
!
column
	^column
!
isConst
	^isConst == true
!
beConst
	isConst := true
!
isWritten
	"Whether the shader assigns to me (or passes me as an out argument)."
	^isWritten == true
!
beWritten
	isWritten := true
!
isPassedByReference
	"An in parameter the function never writes, of a type worth not copying: CUDA takes it as a const reference."
	^storage == #param and: [mode == #in and: [self isWritten not and: [type isOpaque or: [type isMatrix]]]]
!
isWritable
	"Whether a shader may assign to me."
	self isConst ifTrue: [^false].
	(#(#local #global #output) includes: storage) ifTrue: [^true].
	^storage == #param
!
setName: aString type: aType storage: aSymbol at: aToken
	name := aString. type := aType. storage := aSymbol. mode := #in.
	line := aToken line. column := aToken column.
	cuda := GlslShader cudaName: aString
!
printOn: aStream
	aStream nextPutAll: 'GlslVariable('; nextPutAll: name; space; print: type; space; print: storage; nextPut: $)
! !

!GlslVariable class methodsFor: 'instance creation'!
name: aString type: aType storage: aSymbol at: aToken
	^self new setName: aString type: aType storage: aSymbol at: aToken
! !
