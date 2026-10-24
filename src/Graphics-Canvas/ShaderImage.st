Object subclass: #ShaderImage
	instanceVariableNames: 'shader width height source uniforms'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

ShaderImage comment: 'I am one frame of a FragmentShader: my pixel extent, the source and the uniforms it renders me from. Canvas>>image:in: draws me like a Form; the Renderer asks me for my texture (textureOn:), and my shader renders me into it then. I never change: a DisplayList holding me shows the same picture whenever it is rendered again, after an image restart too.'!

!ShaderImage methodsFor: 'initialization'!
setShader: aFragmentShader extent: aPoint source: mslString uniforms: aByteArray
	shader := aFragmentShader.
	width := aPoint x.
	height := aPoint y.
	source := mslString.
	uniforms := aByteArray
! !

!ShaderImage methodsFor: 'accessing'!
shader
	^shader
!
width
	^width
!
height
	^height
!
extent
	^width @ height
!
source
	^source
!
uniforms
	^uniforms
! !

!ShaderImage methodsFor: 'rendering'!
textureOn: aDevice
	^shader textureFor: self
!
isLinearFiltered
	^true
! !

!ShaderImage methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a ShaderImage('; print: width; nextPut: $x; print: height; nextPut: $)
! !
