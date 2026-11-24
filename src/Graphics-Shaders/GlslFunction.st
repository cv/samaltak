Object subclass: #GlslFunction
	instanceVariableNames: 'name returnType params body cuda line column'
	classVariableNames: ''
	package: 'Graphics-Shaders'!

GlslFunction comment: 'I am a function a GLSL shader defines (or declares: body nil): name, returnType, params (GlslVariables, storage #param, their mode #in #out #inout), body (a #block GlslNode), cuda (my name in CUDA C++: main is gl_main).'!

!GlslFunction methodsFor: 'accessing'!
name
	^name
!
returnType
	^returnType
!
params
	^params
!
paramTypes
	^params collect: [:p | p type]
!
body
	^body
!
body: aNode
	body := aNode
!
cuda
	^cuda
!
line
	^line
!
column
	^column
!
signature
	"name(types), as an error message says it."
	^String streamContents: [:s |
		s nextPutAll: name; nextPut: $(.
		params do: [:p | p mode == #in ifFalse: [s nextPutAll: p mode; space]. s print: p type] separatedBy: [s nextPutAll: ', '].
		s nextPut: $)]
!
setName: aString returnType: aType params: anArray at: aToken
	name := aString. returnType := aType. params := anArray.
	line := aToken line. column := aToken column.
	cuda := aString = 'main' ifTrue: ['gl_main'] ifFalse: [GlslShader cudaName: aString]
! !

!GlslFunction class methodsFor: 'instance creation'!
name: aString returnType: aType params: anArray at: aToken
	^self new setName: aString returnType: aType params: anArray at: aToken
! !
