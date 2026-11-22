TestCase subclass: #AgentImageTest
	instanceVariableNames: 'provider conversation'
	classVariableNames: ''
	package: 'Tests-Agent'!

AgentImageTest comment: 'I check AgentImage and the conversation''s handling of images (against a ScriptedProvider; the providers'' own refusals are in AnthropicProviderTest and CodexProviderTest): a screen-sized Form sent scaled within the budget while the Form stays whole, an incompressible picture shrunk until it fits, an oversized PNG encoded again (an undecodable one replaced), only the newest images sent, size refusals recognized, an oversized image in the history fitted before it is sent, and a refusal answered by one retry without the image. Form and PNGWriter are reached late-bound (a higher layer).'!

!AgentImageTest methodsFor: 'running'!
setUp
	provider := ScriptedProvider new.
	conversation := AgentConversation new provider: provider; yourself
!
tearDown
	conversation stop
! !

!AgentImageTest methodsFor: 'tests'!
testScreenSizedForm
	| form part |
	form := self screenForm.
	part := AgentImage partFor: form.
	self assert: (part at: 'type') equals: 'input_image'.
	self assert: (part at: 'image_url') size <= AgentImage maxURLSize.
	self assert: (AgentImage formIn: (part at: 'image_url')) extent equals: 1429 @ 804.
	self assert: form extent equals: 1920 @ 1080
!
testSmallFormIsSentWhole
	| form |
	form := (Smalltalk at: #Form) width: 2 height: 3.
	self assert: ((AgentImage partFor: form) at: 'image_url') equals: 'data:image/png;base64,', (Base64 encode: form pngBytes).
	self assert: (AgentImage partFor: 3) isNil
!
testIncompressiblePictureShrinks
	| picture part |
	picture := ScriptedPicture new.
	part := AgentImage partFor: picture.
	self assert: (part at: 'image_url') size <= AgentImage maxURLSize.
	self assert: picture requests asArray equals: {1568 -> 1150000. 1097 -> 575000}
!
testFitEncodesAnOversizedPNGAgain
	| url part |
	url := self storedURLFor: self screenForm.
	self assert: url size > 10000000.
	part := AgentImage fit: (AgentImage imagePart: url).
	self assert: (part at: 'type') equals: 'input_image'.
	self assert: (part at: 'image_url') size <= AgentImage maxURLSize.
	self assert: (AgentImage formIn: (part at: 'image_url')) extent equals: 1429 @ 804
!
testFitKeepsSmallImagesAndReplacesUndecodableOnes
	| part |
	part := AgentImage imagePart: 'data:image/png;base64,AQID'.
	self assert: (AgentImage fit: part) == part.
	part := AgentImage fit: (AgentImage imagePart: 'data:image/jpeg;base64,', (String new: 3600000 withAll: $A)).
	self assert: (part at: 'type') equals: 'input_text'.
	self assert: ((part at: 'text') beginsWith: '[image omitted: too large to send')
!
testLimitSendsTheNewestImages
	| input limited |
	input := (1 to: 12) asArray collect: [:i |
		(AgentItem user: 'shot ', i printString images: {AgentImage imagePart: 'data:image/png;base64,AQID'}) wire first].
	limited := AgentImage limit: input.
	self assert: (((limited at: 2) at: 'content') last at: 'type') equals: 'input_text'.
	self assert: (((limited at: 3) at: 'content') last at: 'type') equals: 'input_image'.
	self assert: (limited at: 3) == (input at: 3).
	self assert: (((input at: 1) at: 'content') last at: 'type') equals: 'input_image'
!
testSizeRefusals
	self assert: (AgentImage isSizeRefusal: self refusalBody status: 400).
	self assert: (AgentImage isSizeRefusal: '' status: 413).
	self deny: (AgentImage isSizeRefusal: '{"error":{"message":"max_tokens is too large"}}' status: 400).
	self deny: (AgentImage isSizeRefusal: self refusalBody status: 500).
	self assert: (AgentImage indicesIn: self refusalBody after: 'messages.') equals: #(58 2).
	self assert: (AgentImage indicesIn: 'Invalid input[5].content[1].image_url' after: 'input[') equals: #(5 1).
	self assert: (AgentImage indicesIn: 'no index' after: 'messages.') isNil
!
testOversizedImageInTheHistoryIsFittedBeforeSending
	| old sent |
	old := conversation add: (AgentItem user: 'Image shown from object o1' images: {AgentImage imagePart: (self storedURLFor: self screenForm)}).
	provider reply: {ScriptedProvider message: 'a desktop'}.
	self assert: (conversation ask: 'what was it?'; wait) equals: 'a desktop'.
	sent := AgentImage imagesIn: provider requests first.
	self assert: sent size equals: 1.
	self assert: (sent first at: 'image_url') size <= AgentImage maxURLSize.
	self assert: ((old wire first at: 'content') last at: 'image_url') == (sent first at: 'image_url')
!
testRefusedImageIsOmittedAndSentOnceMore
	provider refuseImages.
	provider reply: {ScriptedProvider message: 'seen'}.
	self assert: (conversation ask: 'look' images: {AgentImage imagePart: 'data:image/png;base64,AQID'}; wait) equals: 'seen'.
	self assert: provider requests size equals: 2.
	self assert: (AgentImage imagesIn: provider requests last) isEmpty.
	self assert: (((provider requests last at: 2) at: 'content') last at: 'text') equals: '[image omitted: the model''s API refused it as too large]'
!
testRefusedTwiceIsAnError
	provider refuseImages; refuseImages.
	conversation ask: 'look' images: {AgentImage imagePart: 'data:image/png;base64,AQID'}; wait.
	self assert: provider requests size equals: 2.
	self assert: conversation items last kind equals: #error.
	self assert: conversation canRetry
! !

!AgentImageTest methodsFor: 'support'!
screenForm
	"A 1920x1080 stand-in for a screenshot: a dithered desktop, a window of text-like strokes, a gradient panel."
	| form |
	form := (Smalltalk at: #Form) width: 1920 height: 1080.
	0 to: 1079 do: [:y | 0 to: 1919 do: [:x | | v |
		v := (x + y) odd ifTrue: [16rFF808080] ifFalse: [16rFFFFFFFF].
		((x between: 100 and: 900) and: [y between: 100 and: 700]) ifTrue: [
			v := ((x // 3 + (y // 7) * 31) \\ 11 < 3 and: [y \\ 14 < 10]) ifTrue: [16rFF000000] ifFalse: [16rFFFFFFFF]].
		((x between: 1000 and: 1800) and: [y between: 50 and: 300]) ifTrue: [v := 16rFF000000 + ((x \\ 256) bitShift: 8) + (y \\ 256)].
		form bits at: y * 1920 + x + 1 put: v]].
	^form
!
storedURLFor: aForm
	"A data URL of aForm as PNGWriter wrote it before it compressed (RGBA in stored deflate blocks), as in conversations from then."
	^'data:image/png;base64,', (Base64 encode: ((Smalltalk at: #PNGWriter) storedBytesFor: aForm asByteArray width: aForm width height: aForm height))
!
refusalBody
	"The body of the operator's refusal (HTTP 400 through LiteLLM)."
	^'{"error":{"message":"litellm.BadRequestError: Azure_aiException - {\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"messages.58.content.2.image.source.base64: image exceeds 10 MB maximum: 11061572 bytes > 10485760 bytes\"}}","type":null,"param":null,"code":"400"}}'
! !
