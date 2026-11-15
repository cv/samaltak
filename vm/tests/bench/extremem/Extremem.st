"
Extremem (https://github.com/corretto/heapothesys/tree/master/Extremem, Apache-2.0, see NOTICE):
Amazon's GC workload, an in-memory store whose simulated customers search products, ponder reviews and buy,
save for later or abandon, while server threads transact sales, expire browsing histories and replace customers
and products. Ported as a discrete-event simulation in virtual time: one Smalltalk process, every customer and
server thread an actor whose sleeps advance a virtual clock, so the same objects live across the same amount of
work as in Extremem, run as fast as the system allows. docs/benchmarks.md lists the differences.
Platform-specific: AwfyPlatform and ScriptConsole (awfy/Samaltak.st, awfy/Pharo.st, XmSamaltak.st, XmPharo.st).
"!

Object subclass: #XmRandom
	instanceVariableNames: 'seed multiplier'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #XmConfig
	instanceVariableNames: 'randomSeed dictionarySize numProducts productNameLength productDescriptionLength numCustomers customerThreads customerPeriod customerThinkTime keywordSearchCount allowAnyMatch productReviewLength selectionCriteriaCount buyThreshold saveForLaterThreshold serverThreads serverPeriod salesTransactionQueueCount browsingHistoryQueueCount browsingExpiration customerReplacementPeriod customerReplacementCount productReplacementPeriod productReplacementCount simulationMinutes warmupMinutes words'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #XmProduct
	instanceVariableNames: 'id name description available'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #XmCustomer
	instanceVariableNames: 'name id purchaseHash deceased fsfl csfl sflq'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #XmSalesTransaction
	instanceVariableNames: 'customer product review next'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #XmBrowsingHistory
	instanceVariableNames: 'customer product expiration queue next prev'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #XmSalesQueue
	instanceVariableNames: 'head tail'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #XmBrowsingQueue
	instanceVariableNames: 'head'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #XmCustomers
	instanceVariableNames: 'config names map nextCustomerNo'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #XmProducts
	instanceVariableNames: 'config productIds productMap nameIndex descriptionIndex nextProductId'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #XmActor
	instanceVariableNames: 'id time random config customers products browsingQueue salesQueue'
	classVariableNames: ''
	package: 'Extremem'!

XmActor subclass: #XmCustomerActor
	instanceVariableNames: 'release deciding customer prospects selectors'
	classVariableNames: ''
	package: 'Extremem'!

XmActor subclass: #XmServerActor
	instanceVariableNames: 'attention customerReplacementTime productReplacementTime'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #XmScheduler
	instanceVariableNames: 'heap size'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #XmLatencies
	instanceVariableNames: 'name samples count'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #XmTally
	instanceVariableNames: 'sessions candidates noChoices purchases saves abandons sales expirations customerReplacements productReplacements'
	classVariableNames: ''
	package: 'Extremem'!

Object subclass: #Extremem
	instanceVariableNames: 'config customers products scheduler tally latencies pauses'
	classVariableNames: ''
	package: 'Extremem'!

!XmRandom methodsFor: 'random'!
seed: anInteger multiplier: aMultiplier
	seed := anInteger.
	multiplier := aMultiplier
!
next
	"Park-Miller: 1 .. 2147483646; every product a SmallInteger."
	seed := seed * multiplier \\ 2147483647.
	^seed
!
nextInt: n
	"0 .. n - 1"
	^self next \\ n
!
nextFloat
	^self next / 2147483647.0
! !

!XmRandom class methodsFor: 'instance creation'!
seed: anInteger
	"A stream of random numbers, multiplier 48271."
	^self new seed: anInteger multiplier: 48271
!
seeder: anInteger
	"Seeds for streams, multiplier 16807: consecutive outputs of one stream as seeds would make shifted copies of it."
	^self new seed: anInteger multiplier: 16807
! !

!XmConfig methodsFor: 'initialization'!
initialize
	"Extremem's defaults. Times in microseconds of virtual time."
	randomSeed := 42.
	dictionarySize := 25000.
	numProducts := 20000.
	productNameLength := 5.
	productDescriptionLength := 24.
	numCustomers := 10000.
	customerThreads := 1440.
	customerPeriod := 240 * 1000000.
	customerThinkTime := 200 * 1000000.
	keywordSearchCount := 5.
	allowAnyMatch := true.
	productReviewLength := 32.
	selectionCriteriaCount := 8.
	buyThreshold := 0.4.
	saveForLaterThreshold := 0.4.
	serverThreads := 10.
	serverPeriod := 500 * 1000.
	salesTransactionQueueCount := 10.
	browsingHistoryQueueCount := 10.
	browsingExpiration := 600 * 1000000.
	customerReplacementPeriod := 60 * 1000000.
	customerReplacementCount := 16.
	productReplacementPeriod := 90 * 1000000.
	productReplacementCount := 64.
	simulationMinutes := 10.
	warmupMinutes := 2
!
set: aKey to: aString
	"aKey: an instance variable name above; its value an Integer (times in microseconds), or true/false."
	| value index |
	value := aString = 'true' ifTrue: [true] ifFalse: [aString = 'false' ifTrue: [false] ifFalse: [aString asNumber]].
	index := self class allInstVarNames findFirst: [:each | each asString = aKey].
	index = 0 ifTrue: [^self error: 'Unknown Extremem parameter: ', aKey].
	self instVarAt: index put: value
!
makeWords: aRandom
	"The dictionary: dictionarySize pseudo-English words (Extremem samples /usr/share/dict/words), letters by English frequency."
	| random letters |
	random := aRandom.
	letters := 'eeeeeeeeeeeeettttttttttaaaaaaaaaooooooooiiiiiiiinnnnnnnnsssssssshhhhhhrrrrrrrddddlllllcccuuummmwwffggyyppbbvkjxqz'.
	words := Array new: dictionarySize.
	1 to: dictionarySize do: [:i | | length word |
		length := 2 + (random nextInt: 5) + (random nextInt: 6).
		word := String new: length.
		1 to: length do: [:j | word at: j put: (letters at: (random nextInt: letters size) + 1)].
		words at: i put: word]
! !

!XmConfig methodsFor: 'accessing'!
randomSeed
	^randomSeed
!
numProducts
	^numProducts
!
productNameLength
	^productNameLength
!
productDescriptionLength
	^productDescriptionLength
!
numCustomers
	^numCustomers
!
customerThreads
	^customerThreads
!
customerPeriod
	^customerPeriod
!
customerThinkTime
	^customerThinkTime
!
keywordSearchCount
	^keywordSearchCount
!
allowAnyMatch
	^allowAnyMatch
!
productReviewLength
	^productReviewLength
!
selectionCriteriaCount
	^selectionCriteriaCount
!
buyThreshold
	^buyThreshold
!
saveForLaterThreshold
	^saveForLaterThreshold
!
serverThreads
	^serverThreads
!
serverPeriod
	^serverPeriod
!
salesTransactionQueueCount
	^salesTransactionQueueCount
!
browsingHistoryQueueCount
	^browsingHistoryQueueCount
!
browsingExpiration
	^browsingExpiration
!
customerReplacementPeriod
	^customerReplacementPeriod
!
customerReplacementCount
	^customerReplacementCount
!
productReplacementPeriod
	^productReplacementPeriod
!
productReplacementCount
	^productReplacementCount
!
simulationMinutes
	^simulationMinutes
!
warmupMinutes
	^warmupMinutes
! !

!XmConfig methodsFor: 'words'!
arbitraryWord: aRandom
	^words at: (aRandom nextInt: words size) + 1
!
randomString: length random: aRandom
	"Util.randomString: words catenated one at a time, as Java's String +=."
	| result |
	result := ''.
	1 to: length do: [:i |
		result size > 0 ifTrue: [result := result , ' '].
		result := result , (self arbitraryWord: aRandom)].
	^result
!
randomKeywords: count random: aRandom
	"count distinct words."
	| result |
	result := Array new: count.
	1 to: count do: [:i | | word |
		[word := self arbitraryWord: aRandom.
		 (1 to: i - 1) anySatisfy: [:j | (result at: j) = word]] whileTrue.
		result at: i put: word].
	^result
! !

!XmConfig class methodsFor: 'instance creation'!
new
	^super new initialize
! !

!XmProduct methodsFor: 'accessing'!
setId: anInteger name: aName description: aDescription
	id := anInteger.
	name := aName.
	description := aDescription.
	available := true
!
id
	^id
!
name
	^name
!
description
	^description
!
available
	^available
!
deactivate
	available := false
! !

!XmProduct class methodsFor: 'instance creation'!
id: anInteger name: aName description: aDescription
	^self new setId: anInteger name: aName description: aDescription
! !

!XmCustomer methodsFor: 'accessing'!
setName: aString id: anInteger
	name := aString.
	id := anInteger.
	purchaseHash := 0.
	deceased := false.
	fsfl := 0.
	csfl := 0.
	sflq := Array new: 8
!
name
	^name
!
id
	^id
!
purchaseHash
	^purchaseHash
!
transactSale: aSale at: releaseTime
	"SalesTransaction.hash: (seconds & nanoseconds) + product id."
	purchaseHash := purchaseHash + ((releaseTime // 1000000 bitAnd: releaseTime \\ 1000000 * 1000) + aSale product id)
! !

!XmCustomer methodsFor: 'saved for later'!
addSaveForLater: aHistory
	"sflq: a circular queue from index fsfl (0-based), csfl entries; doubled when full."
	deceased
		ifTrue: [aHistory queue dequeue: aHistory]
		ifFalse: [
			csfl >= sflq size ifTrue: [| expanded |
				expanded := Array new: 2 * sflq size.
				1 to: csfl do: [:i |
					expanded at: i put: (sflq at: fsfl + 1).
					fsfl := fsfl + 1.
					fsfl = sflq size ifTrue: [fsfl := 0]].
				sflq := expanded.
				fsfl := 0].
			sflq at: (fsfl + csfl) \\ sflq size + 1 put: aHistory.
			csfl := csfl + 1]
!
retireOneSaveForLater: aHistory
	| index |
	index := 0.
	0 to: csfl - 1 do: [:i |
		index := (fsfl + i) \\ sflq size.
		(sflq at: index + 1) == aHistory ifTrue: [^self retireAt: index]].
	self retireAt: index
!
retireAt: anIndex
	| index |
	index := anIndex.
	[index = fsfl] whileFalse: [| prior |
		prior := index - 1.
		prior < 0 ifTrue: [prior := sflq size - 1].
		sflq at: index + 1 put: (sflq at: prior + 1).
		index := prior].
	sflq at: fsfl + 1 put: nil.
	fsfl := fsfl + 1.
	csfl := csfl - 1.
	fsfl = sflq size ifTrue: [fsfl := 0]
!
allSavedForLater
	| result index |
	result := Array new: csfl.
	index := fsfl.
	1 to: csfl do: [:i |
		result at: i put: (sflq at: index + 1) product.
		index := index + 1.
		index = sflq size ifTrue: [index := 0]].
	^result
!
prepareForDemise
	| index |
	deceased := true.
	index := fsfl.
	1 to: csfl do: [:i | | h |
		h := sflq at: index + 1.
		h queue dequeue: h.
		sflq at: index + 1 put: nil.
		index := index + 1.
		index >= sflq size ifTrue: [index := 0]].
	fsfl := 0.
	csfl := 0
! !

!XmCustomer class methodsFor: 'instance creation'!
name: aString id: anInteger
	^self new setName: aString id: anInteger
! !

!XmSalesTransaction methodsFor: 'accessing'!
setCustomer: aCustomer product: aProduct review: aString
	customer := aCustomer.
	product := aProduct.
	review := aString
!
customer
	^customer
!
product
	^product
!
review
	^review
!
next
	^next
!
next: aSale
	next := aSale
! !

!XmSalesTransaction class methodsFor: 'instance creation'!
customer: aCustomer product: aProduct review: aString
	^self new setCustomer: aCustomer product: aProduct review: aString
! !

!XmBrowsingHistory methodsFor: 'accessing'!
setCustomer: aCustomer product: aProduct expiration: anInteger queue: aQueue
	customer := aCustomer.
	product := aProduct.
	expiration := anInteger.
	queue := aQueue
!
customer
	^customer
!
product
	^product
!
expiration
	^expiration
!
queue
	^queue
!
next
	^next
!
next: aHistory
	next := aHistory
!
prev
	^prev
!
prev: aHistory
	prev := aHistory
! !

!XmBrowsingHistory class methodsFor: 'instance creation'!
customer: aCustomer product: aProduct expiration: anInteger queue: aQueue
	^self new setCustomer: aCustomer product: aProduct expiration: anInteger queue: aQueue
! !

!XmSalesQueue methodsFor: 'queue'!
enqueue: aSale
	aSale next: nil.
	head isNil
		ifTrue: [head := tail := aSale]
		ifFalse: [tail next: aSale. tail := aSale]
!
dequeue
	| result |
	head isNil ifTrue: [^nil].
	result := head.
	head := head next.
	result next: nil.
	^result
! !

!XmBrowsingQueue methodsFor: 'queue'!
enqueue: aHistory
	"A circular doubly-linked list; head expires first."
	head isNil
		ifTrue: [aHistory next: aHistory; prev: aHistory. head := aHistory]
		ifFalse: [
			aHistory prev: head prev; next: head.
			aHistory prev next: aHistory.
			aHistory next prev: aHistory]
!
pullIfExpired: now
	| candidate |
	head isNil ifTrue: [^nil].
	candidate := head.
	candidate expiration > now ifTrue: [^nil].
	candidate next == candidate
		ifTrue: [head := nil. candidate next: nil; prev: nil]
		ifFalse: [
			head := head next.
			head prev: candidate prev.
			head prev next: head.
			head next prev: head].
	^candidate
!
dequeue: aHistory
	aHistory next == aHistory
		ifTrue: [head := nil]
		ifFalse: [
			aHistory next prev: aHistory prev.
			aHistory prev next: aHistory next.
			head == aHistory ifTrue: [head := aHistory next]].
	aHistory next: nil; prev: nil
! !

!XmCustomers methodsFor: 'initialization'!
setConfig: aConfig random: aRandom
	config := aConfig.
	names := Array new: config numCustomers.
	map := Dictionary new: config numCustomers * 4 // 3.
	nextCustomerNo := 0.
	1 to: config numCustomers do: [:i | | name |
		name := self randomDistinctName: aRandom.
		names at: i put: name.
		map at: name put: (XmCustomer name: name id: nextCustomerNo).
		nextCustomerNo := nextCustomerNo + 1]
!
randomDistinctName: aRandom
	[| first last fullName |
	 first := (config arbitraryWord: aRandom) capitalized.
	 last := (config arbitraryWord: aRandom) capitalized.
	 fullName := first , ' ' , last.
	 (map includesKey: fullName) ifFalse: [^fullName]] repeat
! !

!XmCustomers methodsFor: 'accessing'!
selectRandomCustomer: aRandom
	^map at: (names at: (aRandom nextInt: config numCustomers) + 1)
!
replaceRandomCustomer: aRandom
	| index newName obsolete |
	index := (aRandom nextInt: config numCustomers) + 1.
	newName := self randomDistinctName: aRandom.
	obsolete := map at: (names at: index).
	obsolete prepareForDemise.
	names at: index put: newName.
	map removeKey: obsolete name.
	map at: newName put: (XmCustomer name: newName id: nextCustomerNo).
	nextCustomerNo := nextCustomerNo + 1
!
purchaseHash
	| sum |
	sum := 0.
	map do: [:each | sum := sum + each purchaseHash].
	^sum
! !

!XmCustomers class methodsFor: 'instance creation'!
config: aConfig random: aRandom
	^self new setConfig: aConfig random: aRandom
! !

!XmProducts methodsFor: 'initialization'!
setConfig: aConfig random: aRandom
	config := aConfig.
	productIds := Array new: config numProducts.
	productMap := Dictionary new.
	nameIndex := Dictionary new.
	descriptionIndex := Dictionary new.
	nextProductId := 0.
	1 to: config numProducts do: [:i | | product |
		product := self newProduct: aRandom.
		productIds at: i put: product id.
		productMap at: product id put: product.
		self addToIndices: product]
!
newProduct: aRandom
	| name description id |
	name := config randomString: config productNameLength random: aRandom.
	description := config randomString: config productDescriptionLength random: aRandom.
	id := nextProductId.
	nextProductId := nextProductId + 1.
	^XmProduct id: id name: name description: description
! !

!XmProducts methodsFor: 'indices'!
words: aString do: aBlock
	"Each space-separated word of aString, a new String."
	| start size |
	size := aString size.
	start := 1.
	[start <= size] whileTrue: [| stop |
		stop := start.
		[stop <= size and: [(aString at: stop) ~= $ ]] whileTrue: [stop := stop + 1].
		aBlock value: (aString copyFrom: start to: stop - 1).
		start := stop.
		[start <= size and: [(aString at: start) = $ ]] whileTrue: [start := start + 1]]
!
addToIndices: aProduct
	self add: aProduct id words: aProduct name to: nameIndex.
	self add: aProduct id words: aProduct description to: descriptionIndex
!
add: anId words: aString to: anIndex
	self words: aString do: [:word |
		(anIndex at: word ifAbsent: [anIndex at: word put: Set new]) add: anId]
!
removeFromIndices: aProduct
	self remove: aProduct id words: aProduct name from: nameIndex.
	self remove: aProduct id words: aProduct description from: descriptionIndex
!
remove: anId words: aString from: anIndex
	self words: aString do: [:word |
		(anIndex at: word ifAbsent: [nil]) ifNotNil: [:set | set remove: anId ifAbsent: []]]
! !

!XmProducts methodsFor: 'searching'!
add: aWord matchesIn: anIndex to: aSet
	(anIndex at: aWord ifAbsent: [nil]) ifNotNil: [:ids |
		ids do: [:id | | product |
			product := productMap at: id ifAbsent: [nil].
			(product notNil and: [product available]) ifTrue: [aSet add: product]]]
!
matchesOf: aWord
	| matches |
	matches := IdentitySet new.
	self add: aWord matchesIn: nameIndex to: matches.
	self add: aWord matchesIn: descriptionIndex to: matches.
	^matches
!
lookupProductsMatchingAll: keywords
	| intersection |
	intersection := self matchesOf: keywords first.
	2 to: keywords size do: [:i | | newMatches removeSet |
		intersection isEmpty ifTrue: [^Array new: 0].
		newMatches := self matchesOf: (keywords at: i).
		removeSet := IdentitySet new.
		intersection do: [:p | (newMatches includes: p) ifFalse: [removeSet add: p]].
		removeSet do: [:p | intersection remove: p]].
	^self sortedById: intersection
!
lookupProductsMatchingAny: keywords
	| accumulator |
	accumulator := IdentitySet new.
	keywords do: [:keyword |
		self add: keyword matchesIn: nameIndex to: accumulator.
		self add: keyword matchesIn: descriptionIndex to: accumulator].
	^self sortedById: accumulator
!
sortedById: aSet
	"Hash order differs between systems; the order decides which product gets which random review."
	| result i |
	result := Array new: aSet size.
	i := 0.
	aSet do: [:p | result at: (i := i + 1) put: p].
	^result sort: [:a :b | a id <= b id]
! !

!XmProducts methodsFor: 'replacing'!
replaceRandomProduct: aRandom
	| product index removed |
	product := self newProduct: aRandom.
	index := (aRandom nextInt: productIds size) + 1.
	removed := productMap removeKey: (productIds at: index).
	productIds at: index put: product id.
	removed deactivate.
	productMap at: product id put: product.
	self removeFromIndices: removed.
	self addToIndices: product
! !

!XmProducts class methodsFor: 'instance creation'!
config: aConfig random: aRandom
	^self new setConfig: aConfig random: aRandom
! !

!XmActor methodsFor: 'initialization'!
setId: anInteger time: aTime random: aRandom config: aConfig customers: allCustomers products: allProducts browsingQueue: aBrowsingQueue salesQueue: aSalesQueue
	id := anInteger.
	time := aTime.
	random := aRandom.
	config := aConfig.
	customers := allCustomers.
	products := allProducts.
	browsingQueue := aBrowsingQueue.
	salesQueue := aSalesQueue
! !

!XmActor methodsFor: 'scheduling'!
id
	^id
!
time
	^time
!
before: anActor
	^time < anActor time or: [time = anActor time and: [id < anActor id]]
! !

!XmCustomerActor methodsFor: 'simulation'!
start
	release := time.
	deciding := false
!
fire: aTally
	"Answer the kind of event: 1 preparation, 2 decision."
	deciding
		ifTrue: [self decide: aTally. ^2]
		ifFalse: [self prepare: aTally. ^1]
!
prepare: aTally
	| keywords all any scrutinize saved candidates |
	customer := customers selectRandomCustomer: random.
	keywords := config randomKeywords: config keywordSearchCount random: random.
	all := products lookupProductsMatchingAll: keywords.
	any := config allowAnyMatch
		ifTrue: [products lookupProductsMatchingAny: keywords]
		ifFalse: [Array new: 0].
	scrutinize := all size > 0 ifTrue: [all] ifFalse: [any].
	saved := customer allSavedForLater.
	candidates := saved size > 0 ifTrue: [scrutinize , saved] ifFalse: [scrutinize].
	aTally session: candidates size.
	candidates isEmpty ifTrue: [
		aTally noChoice.
		customer := nil.
		^self nextSession].
	prospects := candidates collect: [:product |
		XmSalesTransaction
			customer: customer
			product: product
			review: (config randomString: config productReviewLength random: random)].
	selectors := config randomKeywords: config selectionCriteriaCount random: random.
	deciding := true.
	time := release + config customerThinkTime
!
decide: aTally
	| best bestMatch selected coin |
	best := 1.
	bestMatch := self rank: (prospects at: 1).
	2 to: prospects size do: [:i | | ranking |
		ranking := self rank: (prospects at: i).
		ranking > bestMatch ifTrue: [bestMatch := ranking. best := i]].
	selected := prospects at: best.
	prospects := selectors := nil.
	coin := random nextFloat.
	coin < config buyThreshold
		ifTrue: [
			salesQueue enqueue: selected.
			aTally purchase]
		ifFalse: [
			coin < (config saveForLaterThreshold + config buyThreshold)
				ifTrue: [| history |
					history := XmBrowsingHistory
						customer: selected customer
						product: selected product
						expiration: time + config browsingExpiration
						queue: browsingQueue.
					browsingQueue enqueue: history.
					selected customer addSaveForLater: history.
					aTally save]
				ifFalse: [aTally abandon]].
	customer := nil.
	self nextSession
!
nextSession
	deciding := false.
	release := release + config customerPeriod.
	time := release
!
rank: aProspect
	| review ranking |
	review := aProspect review.
	ranking := 1.0.
	selectors do: [:criterion | ranking := ranking * (self goodness: criterion in: review)].
	^ranking
!
goodness: keyword in: text
	"0.9375 for every substring of keyword not in text, from the longest down, until one is; squared per shorter length."
	| similarity scale penalize subLength |
	similarity := 1.0.
	scale := 0.9375.
	penalize := scale.
	subLength := keyword size.
	[subLength > 0] whileTrue: [
		1 to: keyword size - subLength + 1 do: [:start |
			(text includesSubstring: (keyword copyFrom: start to: start + subLength - 1))
				ifTrue: [^similarity].
			similarity := similarity * penalize].
		penalize := penalize * scale.
		subLength := subLength - 1].
	^similarity
! !

!XmServerActor methodsFor: 'simulation'!
attention: anInteger customerReplacementTime: aTime productReplacementTime: anotherTime
	attention := anInteger.
	customerReplacementTime := aTime.
	productReplacementTime := anotherTime
!
fire: aTally
	attention = 0 ifTrue: [self transactSales: aTally].
	attention = 1 ifTrue: [self expireHistories: aTally].
	attention = 2 ifTrue: [self replaceCustomers: aTally].
	attention = 3 ifTrue: [self replaceProducts: aTally].
	attention := attention = 0 ifTrue: [3] ifFalse: [attention - 1].
	time := time + config serverPeriod.
	^3
!
transactSales: aTally
	| sale |
	[(sale := salesQueue dequeue) notNil] whileTrue: [
		sale customer transactSale: sale at: time.
		aTally sale]
!
expireHistories: aTally
	| history |
	[(history := browsingQueue pullIfExpired: time) notNil] whileTrue: [
		history customer retireOneSaveForLater: history.
		aTally expiration]
!
replaceCustomers: aTally
	time >= customerReplacementTime ifFalse: [^self].
	config customerReplacementCount timesRepeat: [
		customers replaceRandomCustomer: random.
		aTally customerReplacement].
	customerReplacementTime := customerReplacementTime + config customerReplacementPeriod
!
replaceProducts: aTally
	time >= productReplacementTime ifFalse: [^self].
	config productReplacementCount timesRepeat: [
		products replaceRandomProduct: random.
		aTally productReplacement].
	productReplacementTime := productReplacementTime + config productReplacementPeriod
! !

!XmScheduler methodsFor: 'queue'!
initialize
	heap := Array new: 64.
	size := 0
!
isEmpty
	^size = 0
!
first
	^heap at: 1
!
add: anActor
	| i |
	size = heap size ifTrue: [| grown | grown := Array new: size * 2. grown replaceFrom: 1 to: size with: heap startingAt: 1. heap := grown].
	size := size + 1.
	i := size.
	[i > 1 and: [anActor before: (heap at: i // 2)]] whileTrue: [
		heap at: i put: (heap at: i // 2).
		i := i // 2].
	heap at: i put: anActor
!
removeFirst
	| result last i child |
	result := heap at: 1.
	last := heap at: size.
	heap at: size put: nil.
	size := size - 1.
	i := 1.
	[(child := 2 * i) <= size] whileTrue: [
		(child < size and: [(heap at: child + 1) before: (heap at: child)]) ifTrue: [child := child + 1].
		(last before: (heap at: child)) ifTrue: [^self put: last at: i answer: result].
		heap at: i put: (heap at: child).
		i := child].
	^self put: last at: i answer: result
!
put: anActor at: i answer: result
	size > 0 ifTrue: [heap at: i put: anActor].
	^result
! !

!XmScheduler class methodsFor: 'instance creation'!
new
	^super new initialize
! !

!XmLatencies methodsFor: 'recording'!
setName: aString
	name := aString.
	samples := Array new: 1024.
	count := 0
!
add: microseconds
	count = samples size ifTrue: [| grown | grown := Array new: count * 2. grown replaceFrom: 1 to: count with: samples startingAt: 1. samples := grown].
	count := count + 1.
	samples at: count put: microseconds
!
report
	"# latency NAME count mean p50 p90 p99 p99.9 p99.99 max (microseconds)"
	| sorted sum out |
	count = 0 ifTrue: [^ScriptConsole println: '# latency ', name, ' 0'].
	sorted := (samples copyFrom: 1 to: count) sort: [:a :b | a <= b].
	sum := 0.
	sorted do: [:each | sum := sum + each].
	out := WriteStream on: String new.
	out nextPutAll: '# latency '; nextPutAll: name; space; print: count; space; print: sum // count.
	#(500 900 990 999 9999) with: #(1000 1000 1000 1000 10000) do: [:k :n |
		out space; print: (sorted at: ((count * k + n - 1) // n max: 1))].
	out space; print: sorted last.
	ScriptConsole println: out contents
!
reportRaw
	"# NAME us: every sample, in order"
	| out |
	out := WriteStream on: String new.
	out nextPutAll: '# '; nextPutAll: name; nextPutAll: ' us:'.
	1 to: count do: [:i | out space; print: (samples at: i)].
	ScriptConsole println: out contents
! !

!XmLatencies class methodsFor: 'instance creation'!
name: aString
	^self new setName: aString
! !

!XmTally methodsFor: 'counting'!
initialize
	sessions := candidates := noChoices := purchases := saves := abandons := sales := expirations := customerReplacements := productReplacements := 0
!
session: candidateCount
	sessions := sessions + 1.
	candidates := candidates + candidateCount
!
noChoice
	noChoices := noChoices + 1
!
purchase
	purchases := purchases + 1
!
save
	saves := saves + 1
!
abandon
	abandons := abandons + 1
!
sale
	sales := sales + 1
!
expiration
	expirations := expirations + 1
!
customerReplacement
	customerReplacements := customerReplacements + 1
!
productReplacement
	productReplacements := productReplacements + 1
!
printOn: aStream
	#('sessions' 'candidates' 'noChoices' 'purchases' 'saves' 'abandons' 'sales' 'expirations' 'customerReplacements' 'productReplacements')
		with: {sessions. candidates. noChoices. purchases. saves. abandons. sales. expirations. customerReplacements. productReplacements}
		do: [:label :value | aStream space; nextPutAll: label; nextPut: $=; print: value]
! !

!XmTally class methodsFor: 'instance creation'!
new
	^super new initialize
! !

!Extremem methodsFor: 'running'!
run: args
	"args: 'name=value' Strings overriding XmConfig's defaults. Prints 'Extremem,minute,microseconds' per simulated minute, then '#' lines."
	| start before |
	config := XmConfig new.
	args do: [:each | | i |
		i := each indexOf: $=.
		config set: (each copyFrom: 1 to: i - 1) to: (each copyFrom: i + 1 to: each size)].
	before := AwfyPlatform statistics.
	start := Time microsecondClockValue.
	self setUp.
	ScriptConsole println: '# setup ', (Time microsecondClockValue - start) printString, ' us'.
	start := Time microsecondClockValue.
	self simulate.
	ScriptConsole println: '# simulation ', (Time microsecondClockValue - start) printString, ' us'.
	latencies do: [:each | each report].
	pauses report; reportRaw.
	ScriptConsole println: '# tally', tally printString, ' purchaseHash=', customers purchaseHash printString.
	ScriptConsole println: '# stats Extremem', (AwfyPlatform statisticsSince: before)
!
setUp
	| seeder random browsingQueues salesQueues bq sq customerStagger serverStagger |
	seeder := XmRandom seeder: config randomSeed.
	config makeWords: (XmRandom seed: seeder next).
	random := XmRandom seed: seeder next.
	products := XmProducts config: config random: random.
	customers := XmCustomers config: config random: random.
	browsingQueues := (1 to: config browsingHistoryQueueCount) collect: [:i | XmBrowsingQueue new].
	salesQueues := (1 to: config salesTransactionQueueCount) collect: [:i | XmSalesQueue new].
	scheduler := XmScheduler new.
	tally := XmTally new.
	latencies := {XmLatencies name: 'preparation'. XmLatencies name: 'decision'. XmLatencies name: 'server'}.
	pauses := XmLatencies name: 'pauses'.
	customerStagger := config customerPeriod // config customerThreads.
	bq := browsingQueues size.
	sq := salesQueues size.
	1 to: config customerThreads do: [:i | | actor |
		actor := XmCustomerActor new
			setId: i time: (i - 1) * customerStagger random: (XmRandom seed: seeder next) config: config
			customers: customers products: products browsingQueue: (browsingQueues at: bq) salesQueue: (salesQueues at: sq).
		actor start.
		scheduler add: actor.
		bq := bq = 1 ifTrue: [browsingQueues size] ifFalse: [bq - 1].
		sq := sq = 1 ifTrue: [salesQueues size] ifFalse: [sq - 1]].
	serverStagger := config serverPeriod // config serverThreads.
	bq := browsingQueues size.
	sq := salesQueues size.
	1 to: config serverThreads do: [:i | | actor |
		actor := XmServerActor new
			setId: config customerThreads + i time: (i - 1) * serverStagger random: (XmRandom seed: seeder next) config: config
			customers: customers products: products browsingQueue: (browsingQueues at: bq) salesQueue: (salesQueues at: sq).
		actor
			attention: i - 1 \\ 4
			customerReplacementTime: (i - 1) * (config customerReplacementPeriod // config serverThreads)
			productReplacementTime: (i - 1) * (config productReplacementPeriod // config serverThreads).
		scheduler add: actor.
		bq := bq = 1 ifTrue: [browsingQueues size] ifFalse: [bq - 1].
		sq := sq = 1 ifTrue: [salesQueues size] ifFalse: [sq - 1]]
!
simulate
	"Fire every actor due before the end, in virtual-time order. Latency: an event's wall time, after the warmup.
	A GC pause: the GC time the VM counted across an event with GCs (more than one in an event count as one)."
	| minute end warmupEnd mark lap gc |
	minute := 60 * 1000000.
	end := config simulationMinutes * minute.
	warmupEnd := config warmupMinutes * minute.
	mark := minute.
	lap := Time microsecondClockValue.
	gc := AwfyPlatform gcCountAndMicroseconds.
	[scheduler isEmpty not and: [scheduler first time < end]] whileTrue: [| actor eventTime t0 kind t1 now |
		actor := scheduler removeFirst.
		eventTime := actor time.
		[eventTime >= mark] whileTrue: [
			t0 := Time microsecondClockValue.
			ScriptConsole println: 'Extremem,', (mark // minute) printString, ',', (t0 - lap) printString.
			lap := t0.
			mark := mark + minute].
		t0 := Time microsecondClockValue.
		kind := actor fire: tally.
		t1 := Time microsecondClockValue.
		eventTime >= warmupEnd ifTrue: [(latencies at: kind) add: t1 - t0].
		now := AwfyPlatform gcCountAndMicroseconds.
		(now at: 1) = (gc at: 1) ifFalse: [
			eventTime >= warmupEnd ifTrue: [pauses add: (now at: 2) - (gc at: 2)].
			gc := now].
		scheduler add: actor].
	ScriptConsole println: 'Extremem,', (mark // minute) printString, ',', (Time microsecondClockValue - lap) printString
! !
