Object subclass: #RemoteSnapshot
	instanceVariableNames: 'root header nodes byRef'
	classVariableNames: ''
	package: 'System-Remote'!

RemoteSnapshot comment: 'I am the widget tree at one moment, read through the remote protocol (see RemoteControl), with refs assigned by a RemoteRefTable. I render it as indented text, one widget per line:

	screen "1440x900" theme=blue-book
	window @w6 "System Browser: Window" [18,44 866x468] focused process=#1495 waiting
	  list @w6.packages "Packages" sel="Kernel-Numbers" n=12
	    item @w6.packages.kernel-numbers "Kernel-Numbers" selected

role, @ref, quoted label, bounds (windows always, others with bounds: true), state words. I also find, resolve refs (@w6.packages, and @w6.packages#3 for the fourth child) and collect the text for wait text.'!

!RemoteSnapshot methodsFor: 'building'!
setRoot: anObject refTable: aRefTable
	root := anObject.
	header := (anObject respondsTo: #remoteRole) ifTrue: [self nodeFor: anObject parent: nil depth: 0 children: false].
	nodes := self childrenOf: anObject parent: nil depth: 1.
	aRefTable assignTopLevel: nodes.
	byRef := Dictionary new.
	self allNodesDo: [:node | byRef at: node ref put: node]
!
childrenOf: aWidget parent: aNode depth: depth
	| kids |
	depth > 64 ifTrue: [^#()].
	kids := self ask: aWidget for: #remoteChildren ifNone: [#()].
	kids isNil ifTrue: [^#()].
	^(kids asArray collect: [:kid |
		kid isString
			ifTrue: [kid]
			ifFalse: [self nodeFor: kid parent: aNode depth: depth children: true]]) asArray
!
nodeFor: aWidget parent: aNode depth: depth children: aBoolean
	| node value |
	node := RemoteNode new widget: aWidget; parent: aNode; yourself.
	value := self ask: aWidget for: #remoteRole ifNone: [nil].
	node role: (value isNil ifTrue: ['widget'] ifFalse: [value asString]).
	value := self ask: aWidget for: #remoteLabel ifNone: [nil].
	node label: (value isNil ifTrue: [''] ifFalse: [value asString]).
	value := self ask: aWidget for: #remoteState ifNone: [nil].
	node state: (value isNil ifTrue: [#()] ifFalse: [(value asArray reject: [:w | w isNil]) collect: [:w | w asString]]).
	node bounds: (self ask: aWidget for: #remoteBounds ifNone: [nil]).
	value := self ask: aWidget for: #remoteText ifNone: [nil].
	node text: (value isNil ifFalse: [value asString]).
	value := self ask: aWidget for: #remoteName ifNone: [nil].
	value := value isNil ifTrue: [''] ifFalse: [RemoteRefTable slug: value asString].
	value isEmpty ifTrue: [value := RemoteRefTable slug: node label].
	value isEmpty ifTrue: [value := RemoteRefTable slug: node role].
	value isEmpty ifTrue: [value := 'widget'].
	node name: value.
	node children: (aBoolean ifTrue: [self childrenOf: aWidget parent: node depth: depth + 1] ifFalse: [#()]).
	^node
!
ask: aWidget for: aSelector ifNone: default
	"Answer what aWidget answers to the unary aSelector, or default if it does not understand it or fails."
	(aWidget respondsTo: aSelector) ifFalse: [^default value].
	^[aWidget perform: aSelector] on: Error do: [:e | e return: default value]
! !

!RemoteSnapshot methodsFor: 'accessing'!
root
	^root
!
header
	"The root's node (role, label and state only), or nil."
	^header
!
nodes
	"The top-level nodes (and raw Strings)."
	^nodes
!
allNodes
	| all |
	all := OrderedCollection new.
	self allNodesDo: [:node | all add: node].
	^all
!
allNodesDo: aBlock
	self nodes: nodes do: aBlock
!
nodes: aCollection do: aBlock
	aCollection do: [:each |
		each isString ifFalse: [
			aBlock value: each.
			self nodes: each children do: aBlock]]
!
at: aRef
	^byRef at: aRef ifAbsent: [nil]
!
resolve: aRefString
	"Answer the node for aRefString (@ optional; ref#n is the n-th child of ref, from 0), or nil."
	| ref hash node index kids |
	aRefString isNil ifTrue: [^nil].
	ref := aRefString asString trimBoth.
	(ref notEmpty and: [ref first = $@]) ifTrue: [ref := ref allButFirst].
	node := byRef at: ref ifAbsent: [nil].
	node isNil ifFalse: [^node].
	hash := ref lastIndexOf: $#.
	hash < 2 ifTrue: [^nil].
	node := byRef at: (ref copyFrom: 1 to: hash - 1) ifAbsent: [^nil].
	index := Number readFrom: (ref copyFrom: hash + 1 to: ref size) ifFail: [^nil].
	index isInteger ifFalse: [^nil].
	kids := node childNodes.
	(index between: 0 and: kids size - 1) ifFalse: [^nil].
	^kids at: index + 1
!
resolveOrFail: aRefString
	^(self resolve: aRefString) ifNil: [
		RemoteError notFound: 'no widget @', (self class stripAt: aRefString), ' (take a snapshot to see the current refs)']
! !

!RemoteSnapshot methodsFor: 'queries'!
find: aString
	"Answer the nodes whose label or ref contains aString, ignoring case."
	| needle |
	needle := aString asLowercase.
	^(self allNodes select: [:node |
		(node label asLowercase includesSubstring: needle) or: [node ref asLowercase includesSubstring: needle]]) asArray
!
allText
	"Answer everything a wait for text searches: the rendered tree plus each widget's full text."
	^String new: 1000 streamContents: [:s |
		s nextPutAll: (self renderDepth: 1000 bounds: false maxItems: 1000000000).
		self allNodesDo: [:node | node text isNil ifFalse: [s nextPutAll: node text; nextPut: Character lf]]]
!
windowNodes
	^(nodes select: [:each | each isString not and: [each isWindow]]) asArray
!
windowStates
	^self windowNodes collect: [:node |
		Dictionary new
			at: 'ref' put: node atRef;
			at: 'title' put: node label;
			at: 'bounds' put: node boundsDictionary;
			at: 'state' put: node state;
			at: 'focused' put: (node hasState: 'focused');
			yourself]
! !

!RemoteSnapshot methodsFor: 'rendering'!
renderDepth: depth bounds: showBounds maxItems: maxItems
	"Answer the whole tree as text: the root's line, then the top-level nodes and depth levels below them."
	^String new: 4000 streamContents: [:s |
		header isNil ifFalse: [self printLineOf: header on: s indent: 0 bounds: showBounds].
		self print: nodes on: s level: 0 depth: depth bounds: showBounds maxItems: maxItems]
!
renderRef: aRef depth: depth bounds: showBounds maxItems: maxItems
	| node |
	node := self resolveOrFail: aRef.
	^String new: 1000 streamContents: [:s |
		self print: (Array with: node) on: s level: 0 depth: depth bounds: showBounds maxItems: maxItems]
!
print: aCollection on: aStream level: level depth: depth bounds: showBounds maxItems: maxItems
	| shown |
	shown := aCollection size > maxItems
		ifTrue: [aCollection first: maxItems]
		ifFalse: [aCollection].
	shown do: [:each |
		each isString
			ifTrue: [self indent: level on: aStream. aStream nextPutAll: each; nextPut: Character lf]
			ifFalse: [
				self printLineOf: each on: aStream indent: level bounds: showBounds.
				level < depth ifTrue: [
					self print: each children on: aStream level: level + 1 depth: depth bounds: showBounds maxItems: maxItems]]].
	aCollection size > maxItems ifTrue: [
		self indent: level on: aStream.
		aStream nextPutAll: 'more "'; print: aCollection size - maxItems; nextPutAll: ' more items"'; nextPut: Character lf]
!
printLineOf: aNode on: aStream indent: level bounds: showBounds
	self indent: level on: aStream.
	aStream nextPutAll: aNode role.
	aNode ref isNil ifFalse: [aStream nextPutAll: ' @'; nextPutAll: aNode ref].
	aNode label isEmpty ifFalse: [aStream space; nextPutAll: (JSON quote: (self class cut: aNode label to: 80))].
	((showBounds or: [aNode isWindow]) and: [aNode bounds notNil]) ifTrue: [
		aStream space; nextPutAll: (self class boxString: aNode bounds)].
	aNode state do: [:word | aStream space; nextPutAll: word].
	aStream nextPut: Character lf
!
indent: level on: aStream
	level timesRepeat: [aStream nextPutAll: '  ']
! !

!RemoteSnapshot class methodsFor: 'instance creation'!
root: anObject refTable: aRefTable
	^self new setRoot: anObject refTable: aRefTable
! !

!RemoteSnapshot class methodsFor: 'formatting'!
boxString: aRectangle
	"[x,y wxh], rounded to whole points."
	^String new: 24 streamContents: [:s |
		s nextPut: $[; print: aRectangle left rounded; nextPut: $,; print: aRectangle top rounded;
			space; print: aRectangle width rounded; nextPut: $x; print: aRectangle height rounded; nextPut: $]]
!
cut: aString to: anInteger
	aString size <= anInteger ifTrue: [^aString].
	^(aString first: anInteger - 1), (String with: (Character value: 8230))
!
stripAt: aRefString
	| ref |
	ref := aRefString asString trimBoth.
	(ref notEmpty and: [ref first = $@]) ifTrue: [^ref allButFirst].
	^ref
! !
