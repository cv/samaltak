Object subclass: #GlslToken
	instanceVariableNames: 'kind text line column value'
	classVariableNames: ''
	package: 'Graphics-Shaders'!

GlslToken comment: 'I am a token of GLSL source: kind (#ident, #int, #uint, #float, #punct or #eof), its text, where it starts (line, column; a macro''s tokens are where the macro was used) and, for integers, value.'!

!GlslToken methodsFor: 'accessing'!
kind
	^kind
!
text
	^text
!
line
	^line
!
column
	^column
!
value
	^value
!
is: aString
	"Whether I am the punctuator or keyword aString."
	^text = aString and: [kind == #punct or: [kind == #ident]]
!
printOn: aStream
	aStream nextPutAll: 'GlslToken('; print: kind; space; nextPutAll: text; nextPutAll: ' @'; print: line; nextPut: $:; print: column; nextPut: $)
! !

!GlslToken methodsFor: 'initialization'!
setKind: aSymbol text: aString line: l column: c value: v
	kind := aSymbol. text := aString. line := l. column := c. value := v
!
at: aToken
	"A copy of me where aToken is."
	^self copy setKind: kind text: text line: aToken line column: aToken column value: value
! !

!GlslToken class methodsFor: 'instance creation'!
kind: aSymbol text: aString line: l column: c value: v
	^self new setKind: aSymbol text: aString line: l column: c value: v
! !
