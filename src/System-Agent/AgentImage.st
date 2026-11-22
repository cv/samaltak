Object subclass: #AgentImage
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Agent'!

AgentImage comment: 'I keep the images the agent sends within what the models use and the APIs accept (docs/agent.md, Images). An image is a Responses-API input_image part with a data: URL; a placeholder is an input_text part ''[image omitted: why]''.

	AgentImage partFor: aForm      "an input_image part, or nil for an object without a picture"
	AgentImage fit: aPart          "aPart, or the same picture encoded again within my limits, or a placeholder"
	AgentImage limit: inputItems   "the request''s input, the images beyond the newest maxImages or maxRequestSize as placeholders (in copies)"

partFor: asks the object for PNG bytes scaled down to maxEdge pixels on the longer side (Anthropic''s recommendation; larger images are downscaled by the API anyway) and maxPixels in area (pngBytesScaledToFit:pixels:, which Form implements), and while the data URL is longer than maxURLSize it shortens the edge and halves the area. fit: decodes an oversized PNG with PNGReader (when the image has it, from a higher layer) and encodes it again; anything else becomes a placeholder. The Forms themselves, the conversation''s objects and what the transcript shows do not change, only what is sent.

isSizeRefusal:status: and indicesIn:after: help the providers turn an HTTP error about an image''s or the request''s size into an AgentImageRefused.'!

!AgentImage class methodsFor: 'limits'!
maxEdge
	"Pixels on the longer side."
	^1568
!
maxPixels
	"Pixels in area: about 1.15 megapixels."
	^1150000
!
maxURLSize
	"Characters of one image's data URL (base64): well under the 5 MB (Anthropic) and 10 MB limits."
	^3500000
!
maxRequestSize
	"Characters of all the images' data URLs in one request."
	^10000000
!
maxImages
	"Images in one request: the newest; older ones are sent as placeholders."
	^10
! !

!AgentImage class methodsFor: 'encoding'!
partFor: anObject
	"An input_image part showing anObject within my limits, a placeholder when it cannot be made small enough, or nil when anObject has no picture."
	| edge pixels bytes url |
	edge := self maxEdge.
	pixels := self maxPixels.
	[bytes := anObject pngBytesScaledToFit: edge pixels: pixels.
	 bytes isNil ifTrue: [^nil].
	 url := 'data:image/png;base64,', (Base64 encode: bytes).
	 url size > self maxURLSize] whileTrue: [
		edge <= 64 ifTrue: [^self omitted: 'too large to send'].
		edge := edge * 7 // 10.
		pixels := pixels // 2].
	^self imagePart: url
!
fit: aPart
	"aPart when it is no image or within my limits; else its picture encoded again within them, or a placeholder."
	| form |
	((self isImage: aPart) and: [(self sizeOf: aPart) > self maxURLSize]) ifFalse: [^aPart].
	form := self formIn: (aPart at: 'image_url').
	form isNil ifTrue: [^self omitted: 'too large to send (', (self sizeOf: aPart) printString, ' bytes)'].
	^self partFor: form
!
limit: inputItems
	"inputItems with the images beyond the newest maxImages, or beyond maxRequestSize in all, replaced by placeholders in copies of their messages."
	| count total result |
	count := 0.
	total := 0.
	result := inputItems copy.
	result size to: 1 by: -1 do: [:i | | item content copied |
		item := result at: i.
		content := (item isKindOf: Dictionary) ifTrue: [item at: 'content' ifAbsent: [nil]].
		(content isKindOf: Array) ifTrue: [
			content size to: 1 by: -1 do: [:k | | part |
				part := content at: k.
				(self isImage: part) ifTrue: [
					(count < self maxImages and: [total + (self sizeOf: part) <= self maxRequestSize])
						ifTrue: [
							count := count + 1.
							total := total + (self sizeOf: part)]
						ifFalse: [
							copied isNil ifTrue: [copied := content copy].
							copied at: k put: (self omitted: 'an older image, no longer sent; show it again to see it')]]].
			copied isNil ifFalse: [result at: i put: (item copy at: 'content' put: copied; yourself)]]].
	^result
!
imagePart: aURL
	^Dictionary new at: 'type' put: 'input_image'; at: 'image_url' put: aURL; yourself
!
omitted: aString
	"A placeholder for an image."
	^Dictionary new at: 'type' put: 'input_text'; at: 'text' put: '[image omitted: ', aString, ']'; yourself
!
formIn: aURL
	"The Form of a data:image/png;base64 URL, or nil."
	| reader |
	(aURL isString and: [aURL beginsWith: 'data:image/png;base64,']) ifFalse: [^nil].
	reader := Smalltalk at: #PNGReader ifAbsent: [^nil].
	^[reader formFrom: (Base64 decode: (aURL copyFrom: 23 to: aURL size))] on: Error do: [:e | e return: nil]
! !

!AgentImage class methodsFor: 'testing'!
isImage: aPart
	^(aPart isKindOf: Dictionary) and: [(aPart at: 'type' ifAbsent: [nil]) = 'input_image']
!
sizeOf: anImagePart
	^(anImagePart at: 'image_url' ifAbsent: ['']) size
!
imagesIn: inputItems
	"Every input_image part of the input items' messages."
	| images |
	images := OrderedCollection new.
	inputItems do: [:item |
		(item isKindOf: Dictionary) ifTrue: [
			((item at: 'content' ifAbsent: [nil]) isKindOf: Array) ifTrue: [
				(item at: 'content') do: [:part | (self isImage: part) ifTrue: [images add: part]]]]].
	^images asArray
! !

!AgentImage class methodsFor: 'refusals'!
isSizeRefusal: aString status: anInteger
	"Whether an HTTP error (its status and body) says that an image, or the whole request, is too large."
	| text |
	anInteger = 413 ifTrue: [^true].
	(#(400 422) includes: anInteger) ifFalse: [^false].
	text := aString asLowercase.
	((text includesSubstring: 'request_too_large') or: [text includesSubstring: 'request too large']) ifTrue: [^true].
	^(text includesSubstring: 'image') and: [#('exceed' 'too large' 'too big' 'maximum' 'dimensions') anySatisfy: [:each | text includesSubstring: each]]
!
indicesIn: aString after: aPrefix
	"The two numbers that follow aPrefix in aString (messages.58.content.2 after 'messages.', input[5].content[1] after 'input['), or nil."
	| i first second |
	i := aString indexOfSubCollection: aPrefix.
	i = 0 ifTrue: [^nil].
	i := i + aPrefix size.
	first := 0.
	(i <= aString size and: [(aString at: i) isDigit]) ifFalse: [^nil].
	[i <= aString size and: [(aString at: i) isDigit]] whileTrue: [first := first * 10 + (aString at: i) digitValue. i := i + 1].
	[i <= aString size and: [(aString at: i) isDigit not]] whileTrue: [i := i + 1].
	i > aString size ifTrue: [^nil].
	second := 0.
	[i <= aString size and: [(aString at: i) isDigit]] whileTrue: [second := second * 10 + (aString at: i) digitValue. i := i + 1].
	^Array with: first with: second
! !
