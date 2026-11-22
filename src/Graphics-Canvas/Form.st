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
!
contentVersion
	"What changes whenever the pixels I show do (DisplayListDiff's stamp for my quads): my version; a Form showing another's pixels answers that one's."
	^version
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
	(bytes replaceFrom: 1 to: bytes size withRawBytesOf: bits startingAt: 1) isNil ifFalse: [^bytes].
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
!
pngBytesScaledToFit: maxEdge pixels: maxPixels
	"PNG bytes of me, scaled down to at most maxEdge pixels on the longer side and maxPixels in area (scaledToFit:pixels:)."
	^(self scaledToFit: maxEdge pixels: maxPixels) pngBytes
!
isAgentPicture
	"Larger than my agentThumbnail."
	^(width max: height) > 480
!
agentThumbnail
	"A copy of me at most 480 pixels on the longer side, for the agent's transcript once its conversation no longer keeps me (AgentConversation>>releasePictures)."
	^self scaledToFit: 480 pixels: 480 * 480
! !

!Form methodsFor: 'scaling'!
scaledToFit: maxEdge pixels: maxPixels
	"A copy of me scaled down (aspect kept, scaledTo:) so that my longer side is at most maxEdge pixels and my area at most maxPixels; myself when I fit already."
	| scale |
	(width max: height) <= maxEdge & (width * height <= maxPixels) ifTrue: [^self].
	scale := (maxEdge / (width max: height)) asFloat min: (maxPixels / (width * height)) asFloat sqrt.
	^self scaledTo: ((width * scale) floor max: 1) @ ((height * scale) floor max: 1)
!
scaledTo: anExtent
	"A copy of me of anExtent, each new pixel the area-weighted average of the pixels it covers (a box filter: legible text when shrinking). Two passes, each scaling rows and transposing."
	| once twice result |
	once := self class boxScale: self asByteArray width: width height: height to: anExtent x.
	twice := self class boxScale: once width: height height: anExtent x to: anExtent y.
	result := Form extent: anExtent.
	1 to: anExtent x * anExtent y do: [:i | result bits at: i put: (twice uint32At: i * 4 - 3)].
	^result
! !

!Form class methodsFor: 'scaling'!
boxScale: rgba width: w height: h to: newWidth
	"Scale every row of an RGBA image w x h to newWidth pixels by area averaging (integer weights: a new pixel covers w units, each old one newWidth units); answer the result transposed (width h, height newWidth)."
	| spans out half |
	spans := (0 to: newWidth - 1) asArray collect: [:d | | lo hi first last |
		lo := d * w.
		hi := lo + w.
		first := lo // newWidth.
		last := hi - 1 // newWidth.
		Array with: first with: ((first to: last) asArray collect: [:i | (hi min: i + 1 * newWidth) - (lo max: i * newWidth)])].
	out := ByteArray new: rgba size // w * newWidth.
	half := w // 2.
	0 to: h - 1 do: [:y | | row |
		row := y * w * 4.
		1 to: newWidth do: [:x | | span s r g b a o |
			span := spans at: x.
			s := row + ((span at: 1) * 4).
			r := g := b := a := 0.
			(span at: 2) do: [:weight |
				r := r + ((rgba at: s + 1) * weight).
				g := g + ((rgba at: s + 2) * weight).
				b := b + ((rgba at: s + 3) * weight).
				a := a + ((rgba at: s + 4) * weight).
				s := s + 4].
			o := (x - 1 * h + y) * 4.
			out at: o + 1 put: r + half // w.
			out at: o + 2 put: g + half // w.
			out at: o + 3 put: b + half // w.
			out at: o + 4 put: a + half // w]].
	^out
! !
