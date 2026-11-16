Object subclass: #Form
	instanceVariableNames: 'width height bits version texture uploadedVersion uploadedGeneration'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

Form comment: 'I am a 32-bit RGBA image: a Bitmap of width * height words, rows top to bottom, each word one premultiplied pixel with red in the low byte (the memory layout of an RGBA8 texture). Every change bumps my version; Canvas>>image:in: uploads me to a texture when my version changed since the last upload.'!

!Form methodsFor: 'initialization'!
setWidth: w height: h bits: aBitmap
	width := w.
	height := h.
	bits := aBitmap.
	version := 0
! !

!Form methodsFor: 'accessing'!
width
	^width
!
height
	^height
!
extent
	^width @ height
!
bits
	^bits
!
version
	^version
!
changed
	"Note that bits were modified directly."
	version := version + 1
! !

!Form methodsFor: 'pixels'!
pixelValueAt: aPoint
	"Answer the packed premultiplied RGBA8 word at aPoint (0-based)."
	^bits at: aPoint y * width + aPoint x + 1
!
pixelValueAt: aPoint put: anInteger
	bits at: aPoint y * width + aPoint x + 1 put: anInteger.
	version := version + 1.
	^anInteger
!
at: aPoint
	"Answer the Color at aPoint (0-based)."
	^self colorFromPixelValue: (self pixelValueAt: aPoint)
!
at: aPoint put: aColor
	self pixelValueAt: aPoint put: aColor premultipliedRGBA8.
	^aColor
!
fill: aColor
	| v |
	v := aColor premultipliedRGBA8.
	1 to: bits size do: [:i | bits at: i put: v].
	version := version + 1
!
colorFromPixelValue: v
	| a |
	a := (v bitShift: -24) bitAnd: 255.
	a = 0 ifTrue: [^Color transparent].
	^Color
		r: (v bitAnd: 255) / a
		g: ((v bitShift: -8) bitAnd: 255) / a
		b: ((v bitShift: -16) bitAnd: 255) / a
		a: a / 255.0
!
pixelComponentNames
	^#('r' 'g' 'b' 'a')
!
pixelComponentsAt: aPoint
	"The bytes of the pixel at aPoint (0-based) as stored: premultiplied r g b a."
	| v |
	v := self pixelValueAt: aPoint.
	^(0 to: 3) collect: [:i | (v bitShift: i * -8) bitAnd: 255]
!
asByteArray
	"Answer my pixels as RGBA bytes."
	| bytes |
	bytes := ByteArray new: width * height * 4.
	1 to: bits size do: [:i | bytes uint32At: i * 4 - 3 put: (bits at: i)].
	^bytes
! !

!Form methodsFor: 'rendering'!
textureOn: aDevice
	"Answer my GPU texture, uploading my bits if they changed."
	| generation |
	(texture isNil or: [texture device ~~ aDevice]) ifTrue: [
		texture := aDevice textureWidth: width height: height format: #rgba8 usage: #(#sampler).
		uploadedGeneration := nil].
	generation := texture generation.
	(uploadedGeneration = generation and: [uploadedVersion = version]) ifFalse: [
		texture upload: bits.
		uploadedGeneration := generation.
		uploadedVersion := version].
	^texture
!
isLinearFiltered
	^true
! !

!Form methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a Form('; print: width; nextPut: $x; print: height; nextPut: $)
! !

!Form class methodsFor: 'instance creation'!
width: w height: h
	^self new setWidth: w height: h bits: (Bitmap new: w * h)
!
extent: aPoint
	^self width: aPoint x height: aPoint y
!
width: w height: h bits: aBitmap
	^self new setWidth: w height: h bits: aBitmap
! !

!Form methodsFor: 'copying'!
croppedTo: aRectangle
	"Copy the enclosing pixel rectangle, clipped to my bounds."
	| rect result left top right bottom |
	left := aRectangle left floor max: 0.
	top := aRectangle top floor max: 0.
	right := aRectangle right ceiling min: width.
	bottom := aRectangle bottom ceiling min: height.
	(right <= left or: [bottom <= top]) ifTrue: [self error: 'Empty screenshot region'].
	rect := left @ top corner: right @ bottom.
	result := Form extent: rect extent.
	0 to: result height - 1 do: [:y |
		0 to: result width - 1 do: [:x |
			result pixelValueAt: x @ y put: (self pixelValueAt: (x + left) @ (y + top))]].
	^result
! !

!Form methodsFor: 'converting'!
pngBytes
	^PNGWriter bytesForForm: self
! !
