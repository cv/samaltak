Widget subclass: #ShaderView
	instanceVariableNames: 'shader'
	classVariableNames: ''
	package: 'UI-Widgets'!

ShaderView comment: 'I show a picture computed on the GPU by a fragment shader (FragmentShader: the source after its prelude, a function fmain), at device resolution, in my bounds. Subclasses answer shaderSource (MSL) and uniforms, an Array of rows, each one float4 of the shader''s uniform struct: up to four Numbers, Points (two) and Colors (r g b a, premultiplied by the shader if it wants). Each drawing renders a new frame from them (at renderScale); invalidate when they change (every frame, for an animation). A changed shaderSource takes effect at the next drawing.'!

!ShaderView methodsFor: 'shader'!
shaderSource
	^self subclassResponsibility
!
uniforms
	^#()
!
renderScale
	"The fraction of device pixels I render: less is cheaper, scaled up when drawn."
	^1
! !

!ShaderView methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| s |
	s := aCanvas scale * self renderScale.
	(self width * s) rounded < 1 | ((self height * s) rounded < 1) ifTrue: [^self].
	shader isNil ifTrue: [shader := FragmentShader new].
	aCanvas
		image: (shader
			imageExtent: (self width * s) rounded @ (self height * s) rounded
			source: self shaderSource
			uniforms: self packedUniforms)
		in: self localBounds
!
packedUniforms
	| rows bytes |
	rows := self uniforms.
	bytes := ByteArray new: (rows size max: 1) * 16.
	rows doWithIndex: [:row :i |
		| at |
		at := i * 16 - 15.
		(row isArray ifTrue: [row] ifFalse: [Array with: row]) do: [:each |
			(each isNumber ifTrue: [Array with: each] ifFalse: [
				each isPoint ifTrue: [Array with: each x with: each y] ifFalse: [each asArray]]) do: [:f |
					bytes float32At: at put: f asFloat.
					at := at + 4]]].
	^bytes
! !
