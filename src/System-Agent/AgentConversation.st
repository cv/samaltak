Object subclass: #AgentConversation
	instanceVariableNames: 'context items objects tools provider defaultProvider process done streaming usage turnUsage changeBlock initialInstructions'
	classVariableNames: ''
	package: 'System-Agent'!

AgentConversation comment: 'I am a conversation with the coding agent (docs/agent.md): my items (AgentItems, the transcript), my object table (objects by identity: the id ''o3'' is the third, kept strongly, an object keeps its id), my AgentContext and my tools. Pictures are the exception: only the newest keptPictures objects that are isAgentPicture (Forms larger than a thumbnail; a 1920x1080 screenshot takes 8 MB) are kept strongly, older ones weakly (AgentReleasedObject), and the items that showed them keep the thumbnail (releasePictures).

	(AgentConversation new ask: ''how many classes are in UI-Widgets?'') wait

Images (docs/agent.md, Images): what is sent stays within AgentImage''s limits. Before each request an image over the per-image budget is encoded again smaller, or replaced by a placeholder, in its item for good; images beyond the newest ten or 10 MB are sent as placeholders, and replaced by them in their items for good (they would only take memory). When the API still refuses a request for an image''s or the request''s size (AgentImageRefused), the images it names become placeholders and the request is sent once more.

ask: runs a turn in a Process of its own (''agent turn''): send the developer instructions and every item''s wire to the provider, show the streamed text, record the completed output items in order and run each tool call; while there were tool calls, send again. Any error ends the turn with an #error item. ask: while a turn runs is an error; I am busy (isBusy) from before the turn''s user message is among my items. stop ends a turn from another Process: the provider is cancelled, the turn''s Process and its running cell terminated, every tool call left without output answered ''error: stopped by the user'', so the next request is valid.

The provider (provider:, else a default one: an AnthropicProvider while ApiKeyAccount default isConfigured, else a CodexProvider, chosen again when that changes) answers send:tools:onText:onItem: (blocking; the usage Dictionary or nil; AgentError on failure), cancel and modelName. usage sums the usage of every response, turnUsage that of the running or last turn with its number of requests (''requests''); contextTokens is the last request''s input. My onChange: block is evaluated after every visible change: an item added, streaming text grown, a turn begun or ended.'!

!AgentConversation class methodsFor: 'limits'!
keptPictures
	"Pictures (isAgentPicture) the object table keeps strongly: the newest."
	^4
! !

!AgentConversation methodsFor: 'initialization'!
initialize
	context := AgentContext new.
	items := OrderedCollection new.
	objects := OrderedCollection new.
	tools := AgentTool all
! !

!AgentConversation methodsFor: 'accessing'!
context
	^context
!
context: anAgentContext
	context := anAgentContext
!
items
	^items
!
tools
	^tools
!
toolNamed: aString
	^tools detect: [:each | each name = aString] ifNone: [nil]
!
provider
	"The provider set, else the default one for ApiKeyAccount default (see my comment)."
	| class |
	provider isNil ifFalse: [^provider].
	class := ApiKeyAccount default isConfigured
		ifTrue: [AnthropicProvider]
		ifFalse: [Smalltalk at: #CodexProvider ifAbsent: [AgentError signal: 'No provider: CodexProvider is not in this image']].
	defaultProvider class == class ifFalse: [defaultProvider := class new].
	^defaultProvider
!
provider: aProvider
	provider := aProvider
!
usage
	"The cumulative token usage of all completed responses in this conversation, or nil."
	^usage
!
add: anAgentItem
	items add: anAgentItem.
	self changed.
	^anAgentItem
!
onChange: aBlock
	"Set the default subscriber, or remove it with nil."
	self onChange: aBlock for: self
!
onChange: aBlock for: anOwner
	"Subscribe an owner to visible changes; nil removes its subscription."
	changeBlock ifNil: [changeBlock := IdentityDictionary new].
	aBlock
		ifNil: [changeBlock removeKey: anOwner ifAbsent: []]
		ifNotNil: [changeBlock at: anOwner put: aBlock]
!
contextTokens
	"Latest measured context size, as reported for the last completed request."
	^usage ifNotNil: [usage at: 'context_tokens' ifAbsent: [nil]]
!
canRetry
	^self isBusy not and: [items notEmpty and: [items last kind = #error and: [items last failed and: [items last call isNil]]]]
!
turnUsage
	"The token usage of the running or last turn's responses with their number ('requests'), or nil before its first response."
	^turnUsage
! !

!AgentConversation methodsFor: 'objects'!
idFor: anObject
	"anObject's id, registering it if it has none."
	objects doWithIndex: [:each :i | (each == anObject or: [(self valueOf: each) == anObject and: [anObject notNil]]) ifTrue: [^'o', i printString]].
	objects add: anObject.
	self releasePictures.
	^'o', objects size printString
!
objectAt: anId ifAbsent: aBlock
	"The object of id anId, or aBlock's value if there is none or it was a picture released and collected since (releasePictures)."
	| index object |
	(anId isString and: [anId size > 1 and: [anId first = $o]]) ifFalse: [^aBlock value].
	index := Integer readFrom: anId allButFirst ifFail: [^aBlock value].
	(index between: 1 and: objects size) ifFalse: [^aBlock value].
	object := self valueOf: (objects at: index).
	(object isNil and: [(objects at: index) isKindOf: AgentReleasedObject]) ifTrue: [^aBlock value].
	^object
!
isReleased: anId
	"Whether anId is a picture this conversation no longer keeps (releasePictures)."
	| index |
	(anId isString and: [anId size > 1 and: [anId first = $o]]) ifFalse: [^false].
	index := Integer readFrom: anId allButFirst ifFail: [^false].
	^(index between: 1 and: objects size) and: [(objects at: index) isKindOf: AgentReleasedObject]
!
valueOf: anEntry
	^(anEntry isKindOf: AgentReleasedObject) ifTrue: [anEntry value] ifFalse: [anEntry]
!
releasePictures
	"Keep the newest keptPictures pictures (objects with an agentThumbnail) strongly; hold older ones weakly, and let the items that show them keep their thumbnail instead."
	| count |
	count := 0.
	objects size to: 1 by: -1 do: [:i | | each thumbnail |
		each := objects at: i.
		((each isKindOf: AgentReleasedObject) not and: [each isAgentPicture]) ifTrue: [
			count := count + 1.
			count > self class keptPictures ifTrue: [
				thumbnail := each agentThumbnail.
				objects at: i put: (AgentReleasedObject on: each).
				items do: [:item | item object == each ifTrue: [item object: thumbnail]]]]]
!
describeMissing: anId
	"Why there is no object anId."
	^(self isReleased: anId)
		ifTrue: ['no object ', anId, ': a picture older than the newest ', self class keptPictures printString, ', which are all this conversation keeps; capture it again']
		ifFalse: ['no object ', anId]
!
objectAt: anId
	^self objectAt: anId ifAbsent: [nil]
!
objectBindings
	"o1 … oN as variables of a cell (Symbol -> Association)."
	| bindings |
	bindings := Dictionary new.
	objects doWithIndex: [:each :i | | name |
		name := ('o', i printString) asSymbol.
		bindings at: name put: name -> (self valueOf: each)].
	^bindings
! !

!AgentConversation methodsFor: 'asking'!
ask: aString
	^self ask: aString images: #()
!
wait
	"Block until the turn ends; answer the last assistant text, or the error that ended the turn."
	| semaphore |
	semaphore := done.
	(self isBusy and: [semaphore notNil]) ifTrue: [semaphore wait. semaphore signal].
	^self lastText
!
isBusy
	^process notNil
!
stop
	"End the running turn (from another Process)."
	| turn |
	turn := process.
	turn isNil ifTrue: [^self].
	process := nil.
	turn terminate.
	(provider ifNil: [defaultProvider]) ifNotNil: [:p | p cancel].
	items do: [:each | each isOpen ifTrue: [each failed: true; output: 'error: stopped by the user']].
	items add: (AgentItem kind: #error text: 'Stopped.').
	self endTurn
!
lastText
	items reverseDo: [:each |
		(each kind == #assistant or: [each kind == #error and: [each wire isEmpty]]) ifTrue: [^each text]].
	^nil
! !

!AgentConversation methodsFor: 'turn'!
runTurn
	[[self request] whileTrue]
		on: Error do: [:e |
			items add: ((AgentItem kind: #error text: ((e isKindOf: AgentError)
				ifTrue: [e messageText asString]
				ifFalse: [e class name asString, ': ', e messageText asString])) failed: true; yourself).
			e return: nil]
!
grow: aString
	streaming isNil ifTrue: [streaming := self add: (AgentItem kind: #assistant text: '')].
	streaming text: streaming text, aString.
	self changed
!
record: anItem
	"Add the completed output item anItem; if it is a tool call, run it and answer true."
	| type item tool |
	type := anItem at: 'type' ifAbsent: [nil].
	type = 'message' ifTrue: [
		item := streaming ifNil: [self add: (AgentItem kind: #assistant text: '')].
		streaming := nil.
		item text: (AgentItem textOf: anItem); wire: (Array with: anItem).
		self changed.
		^false].
	type = 'reasoning' ifTrue: [
		self add: ((AgentItem kind: #reasoning text: '') wire: (Array with: anItem); yourself).
		^false].
	(AgentItem isCall: anItem) ifFalse: [^false].
	tool := self toolNamed: (anItem at: 'name' ifAbsent: [nil]).
	tool isNil
		ifTrue: [
			item := AgentItem call: anItem kind: #error text: 'no such tool: ', (anItem at: 'name' ifAbsent: ['']) asString.
			item failed: true; output: 'error: no such tool'.
			self add: item]
		ifFalse: [tool run: anItem in: self].
	^true
!
endTurn
	process := nil.
	done signal.
	self changed
! !

!AgentConversation class methodsFor: 'instance creation'!
on: anAgentContext
	^self new context: anAgentContext; yourself
! !

!AgentConversation methodsFor: 'running'!
ask: aString images: images
	"Add a user message with image content and start a turn. I am busy before the message is there: another Process that sees it and sees me not busy sees a turn that is over."
	| message |
	self isBusy ifTrue: [^self error: 'The agent is busy: wait for it or stop it first'].
	message := AgentItem user: aString images: (images collect: [:each | AgentImage fit: each]).
	done := Semaphore new.
	turnUsage := nil.
	process := [self runTurn. self endTurn] newProcess.
	process priority: Processor userSchedulingPriority; name: 'agent turn'.
	self add: message.
	process resume
! !

!AgentConversation methodsFor: 'private'!
changed
	changeBlock ifNotNil: [
		changeBlock values copy do: [:block | block value: self]]
!
accumulateUsage: answer
	"Add a response's token usage to the conversation's and the turn's sums; count the turn's requests."
	usage := self sum: answer into: usage.
	(answer includesKey: 'input_tokens') ifTrue: [usage at: 'context_tokens' put: (answer at: 'input_tokens')].
	turnUsage := self sum: answer into: turnUsage.
	turnUsage at: 'requests' put: (turnUsage at: 'requests' ifAbsent: [0]) + 1


!
request
	"Send everything so far, then record the response's items and run its tool calls; answer whether there were any. A refusal for images too large is answered by replacing them and sending once more."
	| received called answer refused |
	received := OrderedCollection new.
	refused := false.
	answer := [self send: received] on: AgentImageRefused do: [:e |
		refused := true.
		self omitImages: e parts.
		e return: nil].
	refused ifTrue: [
		received := OrderedCollection new.
		answer := self send: received].
	self accumulateUsage: (answer ifNil: [Dictionary new]).
	called := false.
	received do: [:item | (self record: item) ifTrue: [called := true]].
	^called
!
send: received
	"One request to the provider; the completed output items go to received."
	streaming := nil.
	^self provider
		send: self input
		tools: (tools collect: [:each | each spec])
		onText: [:delta | self grow: delta]
		onItem: [:item | received add: item]
!
omitImages: parts
	"Replace the image parts the API refused by placeholders, in their items for good."
	| changed |
	changed := false.
	items do: [:each |
		(each mapImages: [:part |
			(parts anySatisfy: [:refused | refused == part])
				ifTrue: [AgentImage omitted: 'the model''s API refused it as too large']
				ifFalse: [part]]) ifTrue: [changed := true]].
	changed ifTrue: [self changed]
!
input
	"Snapshot initial instructions once. Never rewrite the prefix from live context. Images over budget are fitted in their items; the newest within AgentImage's limits are sent."
	| input |
	initialInstructions ifNil: [
		initialInstructions := AgentItem message: 'developer' text: (AgentInstructions textFor: context)].
	input := OrderedCollection new.
	input add: initialInstructions.
	items do: [:each |
		each mapImages: [:part | AgentImage fit: part].
		input addAll: each wire].
	input := AgentImage limit: input asArray.
	self releaseImagesNotIn: input.
	^input
!
releaseImagesNotIn: inputItems
	"Replace the images inputItems no longer send (AgentImage limit:) in their items, for good, by the placeholder sent instead: once beyond the newest, an image stays so, and it would only take memory."
	| sent |
	sent := AgentImage imagesIn: inputItems.
	items do: [:each |
		each mapImages: [:part | (sent anySatisfy: [:s | s == part]) ifTrue: [part] ifFalse: [AgentImage olderImage]]]
!
sum: answer into: aDictionaryOrNil
	"aDictionaryOrNil, or a new Dictionary, with answer's token counts added."
	| sums details previous |
	sums := aDictionaryOrNil ifNil: [Dictionary new].
	#('input_tokens' 'output_tokens' 'total_tokens') do: [:key |
		sums at: key put: (sums at: key ifAbsent: [0]) + (answer at: key ifAbsent: [0])].
	details := answer at: 'input_tokens_details' ifAbsent: [nil].
	details ifNotNil: [
		previous := sums at: 'input_tokens_details' ifAbsentPut: [Dictionary new].
		previous at: 'cached_tokens' put: (previous at: 'cached_tokens' ifAbsent: [0]) + (details at: 'cached_tokens' ifAbsent: [0])].
	^sums
! !

!AgentConversation methodsFor: 'actions'!
retry
	"Resume the failed turn without adding another user message."
	self canRetry ifFalse: [^self].
	streaming := nil.
	done := Semaphore new.
	process := [self runTurn. self endTurn] newProcess.
	process priority: Processor userSchedulingPriority; name: 'agent turn'.
	self changed.
	process resume
! !
