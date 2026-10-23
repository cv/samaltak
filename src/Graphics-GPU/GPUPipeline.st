GPUResource subclass: #GPUPipeline
	instanceVariableNames: 'vertexShader fragmentShader stride attributes primitive blend format'
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPUPipeline comment: 'I am a graphics pipeline: two shaders, a vertex layout (stride and {format. offset} attributes; attribute i is location i of vertex buffer slot 0), a primitive type, a blend mode and the target texture format.'!

!GPUPipeline methodsFor: 'private'!
setDevice: aDevice vertex: vs fragment: fs stride: anInteger attributes: anArray primitive: primitiveSymbol blend: blendSymbol format: formatSymbol
	self setDevice: aDevice.
	vertexShader := vs.
	fragmentShader := fs.
	stride := anInteger.
	attributes := anArray.
	primitive := primitiveSymbol.
	blend := blendSymbol.
	format := formatSymbol
!
createHandle
	| flat |
	flat := Array new: attributes size * 2.
	attributes doWithIndex: [:pair :i |
		flat at: i * 2 - 1 put: (self attributeCode: pair first).
		flat at: i * 2 put: pair last].
	^GPUPlatform createPipeline: device handle vertex: vertexShader handle fragment: fragmentShader handle
		stride: stride attributes: flat
		primitive: (#(#triangles #triangleStrip #lines #lineStrip #points) indexOf: primitive) - 1
		blend: (#(#none #alpha #premultiplied) indexOf: blend) - 1
		format: (GPUDevice textureFormatCode: format)
!
attributeCode: aSymbol
	| code |
	code := #(#float #float2 #float3 #float4 #ubyte4norm #ubyte4 #uint #int) indexOf: aSymbol.
	code = 0 ifTrue: [^self error: 'Unknown vertex attribute format ', aSymbol printString].
	^code
! !

!GPUPipeline methodsFor: 'accessing'!
stride
	^stride
!
format
	^format
! !
