Error subclass: #ShaderError
	instanceVariableNames: 'line column detail'
	classVariableNames: ''
	package: 'Graphics-Shaders'!

ShaderError comment: 'I am a shader that does not compile: where (line and column in its source, 1-based; nil if not known) and what (detail). messageText reads like a compiler''s: "12:7: error: no function noise(vec3)". The GLSL front end (GlslShader) signals me for its errors, and a device''s compiler for the ones it finds after it (NVRTC''s log).'!

!ShaderError methodsFor: 'accessing'!
line
	^line
!
column
	^column
!
detail
	^detail
!
messageText
	^String streamContents: [:s |
		line isNil ifFalse: [s print: line; nextPut: $:. column isNil ifFalse: [s print: column; nextPut: $:]. s space].
		s nextPutAll: 'error: '; nextPutAll: (detail ifNil: ['the shader does not compile'])]
!
line: aLine column: aColumn detail: aString
	line := aLine.
	column := aColumn.
	detail := aString
! !

!ShaderError class methodsFor: 'signalling'!
line: aLine column: aColumn detail: aString
	^self new line: aLine column: aColumn detail: aString; signal
! !
