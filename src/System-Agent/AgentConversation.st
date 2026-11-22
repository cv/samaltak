Object subclass: #AgentConversation
	instanceVariableNames: 'context items objects tools provider defaultProvider process done streaming usage turnUsage changeBlock initialInstructions staged applyNow contextWindow noticed responseStart'
	classVariableNames: ''
	package: 'System-Agent'!

AgentConversation comment: 'I am a conversation with the coding agent (docs/agent.md): my items (AgentItems, the transcript), my object table (objects by identity: the id ''o3'' is the third, kept strongly, an object keeps its id), my AgentContext and my tools. Pictures are the exception: only the newest keptPictures objects that are isAgentPicture (Forms larger than a thumbnail; a 1920x1080 screenshot takes 8 MB) are kept strongly, older ones weakly (AgentReleasedObject), and the items that showed them keep the thumbnail (releasePictures).

	(AgentConversation new ask: ''how many classes are in UI-Widgets?'') wait

Images (docs/agent.md, Images): what is sent stays within AgentImage''s limits. Before each request an image over the per-image budget is encoded again smaller, or replaced by a placeholder, in its item for good; images beyond the newest ten or 10 MB are sent as placeholders, and replaced by them in their items for good (they would only take memory). When the API still refuses a request for an image''s or the request''s size (AgentImageRefused), the images it names become placeholders and the request is sent once more.

ask: runs a turn in a Process of its own (''agent turn''): send the developer instructions and every item''s wire to the provider, show the streamed text, record the completed output items in order and run each tool call; while there were tool calls, send again. Any error ends the turn with an #error item. ask: while a turn runs is an error; I am busy (isBusy) from before the turn''s user message is among my items. stop ends a turn from another Process: the provider is cancelled, the turn''s Process and its running cell terminated, every tool call left without output answered ''error: stopped by the user'', so the next request is valid.

The provider (provider:, else a default one: an AnthropicProvider while ApiKeyAccount default isConfigured, else a CodexProvider, chosen again when that changes) answers send:tools:onText:onItem: (blocking; the usage Dictionary or nil; AgentError on failure), cancel and modelName. usage sums the usage of every response, turnUsage that of the running or last turn with its number of requests (''requests''); contextTokens is the last request''s input. My onChange: block is evaluated after every visible change: an item added, streaming text grown, a turn begun or ended.

The agent edits its context through me (docs/agent.md, Context editing): cells bind me as thisConversation; outline lists the items, elide:reason: and summarize:to:as: replace items'' wires (AgentItem replaceWire:edit:), note:put: appends working notes. Edits are staged (stagedEdits) and applied when the turn ends or, after applyNow, before the next request; with no turn running at once. noticePressure adds a #notice when the context first reaches half and three quarters of contextWindow.'!

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
	"o1 … oN, and thisConversation (me), as variables of a cell (Symbol -> Association)."
	| bindings |
	bindings := Dictionary new.
	objects doWithIndex: [:each :i | | name |
		name := ('o', i printString) asSymbol.
		bindings at: name put: name -> (self valueOf: each)].
	bindings at: #thisConversation put: #thisConversation -> self.
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
	self discardEdits.
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
	responseStart := nil.
	[self applyEdits] on: Error do: [:e | staged := nil. e return: nil].
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
	"Apply the staged edits if applyNow asked for it, send everything so far, then record the response's items, run its tool calls and notice how full the context is; answer whether there were calls. A refusal for images too large is answered by replacing them and sending once more."
	| received called answer refused |
	applyNow == true ifTrue: [self applyEdits].
	received := OrderedCollection new.
	refused := false.
	responseStart := items size.
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
	self noticePressure.
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

!AgentConversation methodsFor: 'context'!
stagedEdits
	"The edits waiting for the turn to end: {item. wire. edit} each, a note's with its new item."
	^staged ifNil: [staged := OrderedCollection new]
!
contextWindow
	"The model's context window in tokens, as the pressure notices assume it."
	^contextWindow ifNil: [200000]
!
contextWindow: tokens
	contextWindow := tokens
!
noteBudget
	"The most tokens a note, and the notes sent together before superseded ones are dropped, take."
	^4096 max: self contextWindow // 10
!
isRunning: anIndex
	"Whether the item at anIndex belongs to the response whose calls are running."
	^responseStart notNil and: [anIndex > responseStart]
!
isStaged: anItem
	^self stagedEdits anySatisfy: [:each | each first == anItem]
!
isUserMessage: anIndex
	"Whether the item at anIndex is the user's: a #user item that is not the picture a show-object call sent."
	^(items at: anIndex) kind == #user and: [anIndex = 1 or: [(items at: anIndex - 1) kind ~~ #show]]
!
lastUserIndex
	"The index of the user's last message, or 0."
	items size to: 1 by: -1 do: [:i | (self isUserMessage: i) ifTrue: [^i]].
	^0
!
outline
	"A line per item (outlineFrom:to:)."
	^self outlineFrom: 1 to: items size
!
outlineFrom: first to: last
	"A line per item: its index (what elide:reason: and summarize:to:as: take), kind, the tokens it is estimated to take, its edit, and the start of its text and result; then the total."
	| total |
	total := 0.
	^String new: items size * 120 streamContents: [:s |
		((first max: 1) to: (last min: items size)) do: [:i | | each tokens |
			each := items at: i.
			tokens := each tokens.
			total := total + tokens.
			s print: i; space; nextPutAll: each kind; nextPutAll: ' ~'; print: tokens.
			each isEdited ifTrue: [s nextPutAll: ' ['; nextPutAll: each edit; nextPut: $]].
			(self isStaged: each) ifTrue: [s nextPutAll: ' [staged]'].
			(self isRunning: i) ifTrue: [s nextPutAll: ' [running]'].
			s space; nextPutAll: each preview; nextPut: Character lf].
		s nextPutAll: 'these items ~'; print: total; nextPutAll: ' tokens'.
		self contextTokens ifNotNil: [:tokens |
			s nextPutAll: '; the last request '; print: tokens; nextPutAll: ' of a '; print: self contextWindow; nextPutAll: '-token window']]
!
editableItemAt: anIndex
	"The finished tool call at anIndex, which elide:reason: may stage; an error says why not."
	| item |
	(anIndex isInteger and: [anIndex between: 1 and: items size]) ifFalse: [^self error: 'no item ', anIndex printString, ': thisConversation outline lists them'].
	item := items at: anIndex.
	(self isRunning: anIndex) ifTrue: [^self error: 'item ', anIndex printString, ' belongs to the response being run'].
	(item call isNil or: [item isOpen]) ifTrue: [^self error: 'item ', anIndex printString, ' is not a finished tool call: elide:reason: takes those, summarize:to:as: the rest'].
	item isEdited ifTrue: [^self error: 'item ', anIndex printString, ' is ', item edit, ' already'].
	(self isStaged: item) ifTrue: [^self error: 'item ', anIndex printString, ' has an edit staged already'].
	^item
!
elided: anItem at: anIndex reason: aString
	"anItem's wire with the call's input (code-mode's source) and its output replaced by stubs saying where they are."
	| call output where |
	where := '(thisConversation items at: ', anIndex printString, ')'.
	call := anItem call copy.
	call removeKey: 'anthropic' ifAbsent: [nil].
	(call at: 'type' ifAbsent: [nil]) = 'custom_tool_call' ifTrue: [
		call at: 'input' put: '"elided: the source is ', where, ' text"'].
	output := (anItem wire at: 2) copy.
	output at: 'output' put: (String new: 200 streamContents: [:s |
		s nextPutAll: '[elided'.
		(aString isString and: [aString notEmpty]) ifTrue: [
			s nextPutAll: ' ('; nextPutAll: (aString first: (aString size min: 200)); nextPut: $)].
		s nextPutAll: ' · ~'; print: anItem tokens; nextPutAll: ' tokens · the output was '; nextPutAll: where; nextPutAll: ' result'.
		anItem objectId ifNotNil: [:id | s nextPutAll: '; '; nextPutAll: id; nextPutAll: ' is still bound'].
		s nextPut: $]]).
	^Array with: call with: output
!
elide: indexes reason: aString
	"Stage replacing the tool calls at indexes (an Integer or a collection; thisConversation outline lists them) and their outputs by stubs saying where the originals are; a show-object's picture goes with it. Answer a receipt."
	| list edits |
	list := indexes isInteger ifTrue: [Array with: indexes] ifFalse: [indexes asArray].
	list isEmpty ifTrue: [^self error: 'nothing to elide'].
	list asSet size = list size ifFalse: [^self error: 'an index is given twice'].
	edits := OrderedCollection new.
	list do: [:i | | item stub next |
		item := self editableItemAt: i.
		stub := self elided: item at: i reason: aString.
		(AgentItem tokensIn: stub) < item tokens ifFalse: [^self error: 'item ', i printString, ' is no larger than its stub'].
		edits add: (Array with: item with: stub with: 'elided').
		(item kind == #show and: [i < items size and: [(items at: i + 1) kind == #user and: [(self isUserMessage: i + 1) not]]]) ifTrue: [
			next := items at: i + 1.
			(next isEdited or: [self isStaged: next]) ifFalse: [edits add: (Array with: next with: #() with: 'elided')]]].
	^self stage: edits asArray doing: 'elide ', list size printString, (list size = 1 ifTrue: [' item'] ifFalse: [' items'])
!
summarize: first to: last as: aString
	"Stage replacing the items first to last (and the reasoning just before), the agent's of a finished turn, by aString: an assistant message saying it is a summary and where the originals are. Answer a receipt."
	| from range before message edits |
	(first isInteger and: [last isInteger and: [1 <= first and: [first <= last and: [last <= items size]]]])
		ifFalse: [^self error: 'no range ', first printString, ' to ', last printString, ' in items 1 to ', items size printString].
	(aString isString and: [aString notEmpty]) ifFalse: [^self error: 'the summary is empty'].
	from := first.
	[from > 1 and: [(items at: from - 1) kind == #reasoning]] whileTrue: [from := from - 1].
	(from to: last) do: [:i | | each |
		each := items at: i.
		((self isUserMessage: i) or: [#(#note #notice) includes: each kind]) ifTrue: [
			^self error: 'item ', i printString, ' is a ', each kind, ' message: a summary replaces the agent''s items of one turn, between user messages'].
		each isOpen ifTrue: [^self error: 'item ', i printString, ' is a call still running'].
		(self isStaged: each) ifTrue: [^self error: 'item ', i printString, ' has an edit staged already']].
	(self isBusy and: [last > self lastUserIndex]) ifTrue: [
		^self error: 'item ', last printString, ' belongs to the running turn: summarize finished turns'].
	range := (from to: last) collect: [:i | items at: i].
	before := range inject: 0 into: [:sum :each | sum + each tokens].
	message := AgentItem assistant: '[Summary of items ', from printString, '–', last printString, ', which you wrote to replace them; the originals are thisConversation items at: ', from printString, ' to ', last printString, ']', String lf, aString.
	(AgentItem tokensIn: (Array with: message)) < before ifFalse: [
		^self error: 'the summary takes ~', (AgentItem tokensIn: (Array with: message)) printString, ' tokens, not fewer than the ~', before printString, ' of the items it replaces'].
	edits := range collect: [:each |
		each == range first
			ifTrue: [Array with: each with: (Array with: message) with: 'summary of ', from printString, '–', last printString]
			ifFalse: [Array with: each with: #() with: 'summarized']].
	^self stage: edits doing: 'summarize items ', from printString, ' to ', last printString
!
stage: edits doing: aString
	"Stage edits ({item. wire. edit} each), or apply them now when no turn runs; answer a receipt."
	| before after |
	before := edits inject: 0 into: [:sum :each | sum + each first tokens].
	after := edits inject: 0 into: [:sum :each | sum + (AgentItem tokensIn: (each at: 2))].
	self stagedEdits addAll: edits.
	self isBusy ifTrue: [
		^aString, ': ~', before printString, ' → ~', after printString, ' tokens, staged: applies when the turn ends (thisConversation applyNow: before the next request)'].
	self applyEdits.
	^aString, ': ~', before printString, ' → ~', after printString, ' tokens, applied'
!
note: aKey put: aStringOrNil
	"Stage a working note under aKey, sent at the end of the context as <note key=…>; a later one under the same key replaces it, nil removes it. Answer a receipt."
	| key version text item |
	key := aKey asString.
	(key notEmpty and: [key size <= 64 and: [key allSatisfy: [:ch | ch isLetter or: [ch isDigit or: ['._-' includes: ch]]]]])
		ifFalse: [^self error: 'a note key is 1 to 64 letters, digits, ., _ or -'].
	(aStringOrNil isNil or: [aStringOrNil isString]) ifFalse: [^self error: 'a note is a String, or nil to remove it'].
	(aStringOrNil notNil and: [(self notes includesKey: key) not and: [self notes size >= 32]])
		ifTrue: [^self error: 'there are 32 notes: remove one first'].
	version := (items select: [:each | each kind == #note and: [each key = key]]) size
		+ (self stagedEdits select: [:each | each first kind == #note and: [each first key = key]]) size + 1.
	text := aStringOrNil isNil
		ifTrue: ['<note key="', key, '" removed="true"/>']
		ifFalse: ['<note key="', key, '"', (version > 1 ifTrue: [' version="', version printString, '" replaces="earlier"'] ifFalse: ['']), '>', String lf, aStringOrNil, String lf, '</note>'].
	item := (AgentItem kind: #note text: 'Note ', key, ': ', (aStringOrNil ifNil: ['removed']))
		wire: (Array with: (AgentItem message: 'user' text: text)); yourself.
	item key: key; object: aStringOrNil.
	item tokens > self noteBudget ifTrue: [^self error: 'the note takes ~', item tokens printString, ' tokens, over the budget of ', self noteBudget printString].
	self stagedEdits add: (Array with: item with: item wire with: nil).
	self isBusy ifTrue: [^'note ', key, ': staged: added at the end of the context when the turn ends (thisConversation applyNow: before the next request)'].
	self applyEdits.
	^'note ', key, ': added'
!
latestNotes
	"The newest note item of each key, in order."
	| latest |
	latest := Dictionary new.
	items do: [:each | each kind == #note ifTrue: [latest at: each key put: each]].
	^(items select: [:each | (latest at: each key ifAbsent: [nil]) == each and: [each kind == #note]]) asArray
!
notes
	"The live notes: key -> text."
	| notes |
	notes := Dictionary new.
	self latestNotes do: [:each | each object ifNotNil: [:text | notes at: each key put: text]].
	^notes
!
addNote: aNoteItem
	"Add aNoteItem; the earlier ones under its key are superseded (still sent until dropNotes: drops them)."
	items do: [:each | (each kind == #note and: [each key = aNoteItem key and: [each isEdited not]]) ifTrue: [each edit: 'superseded']].
	self add: aNoteItem
!
dropNotes: rewrote
	"Stop sending superseded notes and removed keys' notes when rewrote (the context changes before them anyway) or when the notes sent take more than noteBudget."
	| notes removed |
	notes := items select: [:each | each kind == #note and: [each wire notEmpty]].
	(rewrote or: [(notes inject: 0 into: [:sum :each | sum + each tokens]) > self noteBudget]) ifFalse: [^self].
	removed := (self latestNotes select: [:each | each object isNil]) collect: [:each | each key].
	notes do: [:each |
		(each edit = 'superseded' or: [removed includes: each key]) ifTrue: [each replaceWire: #() edit: 'dropped']]
!
applyEdits
	"Apply the staged edits: replace the items' wires (each keeps its original), add the notes; drop superseded notes when the context was rewritten anyway."
	| edits rewrote |
	edits := self stagedEdits copy.
	staged := nil.
	applyNow := false.
	edits isEmpty ifTrue: [^self].
	rewrote := false.
	edits do: [:each | | item |
		item := each first.
		item kind == #note
			ifTrue: [self addNote: item]
			ifFalse: [
				(items includes: item) ifTrue: [
					item replaceWire: (each at: 2) edit: (each at: 3).
					rewrote := true]]].
	self dropNotes: rewrote.
	self changed
!
applyNow
	"Apply the staged edits before the next request instead of when the turn ends."
	self isBusy ifFalse: [self applyEdits. ^'applied'].
	applyNow := true.
	^'the staged edits apply before the next request'
!
discardEdits
	"Forget the staged edits."
	staged := nil.
	applyNow := false.
	^'discarded'
!
noticePressure
	"Add a notice when the context first reaches half, then three quarters, of the window; again after it shrank below half."
	| tokens window threshold text |
	tokens := self contextTokens.
	tokens isNil ifTrue: [^self].
	window := self contextWindow.
	tokens < (window // 2) ifTrue: [^noticed := nil].
	threshold := tokens * 4 >= (window * 3) ifTrue: [75] ifFalse: [50].
	(noticed notNil and: [noticed >= threshold]) ifTrue: [^self].
	noticed := threshold.
	text := 'Context: ', (tokens * 100 // window) printString, '% of the ', (window // 1000) printString, 'K-token window (', tokens printString, ' tokens). thisConversation outline lists the items by size; elide:reason:, summarize:to:as: and note:put: shrink what is sent.'.
	self add: ((AgentItem kind: #notice text: text) wire: (Array with: (AgentItem message: 'user' text: '[', text, ']')); yourself)
! !
