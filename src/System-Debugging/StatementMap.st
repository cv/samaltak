Object subclass: #StatementMap
	instanceVariableNames: 'statements'
	classVariableNames: ''
	package: 'System-Debugging'!

StatementMap comment: 'I know the statements of one method''s source (the statements of its body and of every block in it, inlined or not) as 1-based Intervals. DebugSession steps Over by statements: chainAt: anInterval answers the statements containing anInterval, outermost first.

	(StatementMap forMethod: Integer >> #gcd:) chainAt: (81 to: 88)'!

!StatementMap methodsFor: 'accessing'!
statements
	^statements
!
chainAt: anInterval
	"The statements containing anInterval, outermost first."
	| chain |
	anInterval isNil ifTrue: [^#()].
	chain := statements select: [:each | each first <= anInterval first and: [anInterval last <= each last]].
	^(chain asSortedCollection: [:a :b | a size > b size or: [a size = b size and: [a first <= b first]]]) asArray
! !

!StatementMap methodsFor: 'private'!
setSource: aString doIt: aBoolean
	| tree |
	statements := OrderedCollection new.
	(aString isNil or: [aString isEmpty]) ifTrue: [^self].
	tree := [aBoolean ifTrue: [Parser new parseExpression: aString] ifFalse: [Parser new parseMethod: aString]]
		on: Error do: [:e | e return: nil].
	tree isNil ifFalse: [self walk: tree]
!
walk: aNode
	aNode isNil ifTrue: [^self].
	(aNode isKindOf: SequenceNode) ifTrue: [
		aNode statements do: [:each |
			(each start notNil and: [each stop notNil]) ifTrue: [statements add: (each start to: each stop)].
			self walk: each].
		^self].
	(aNode isKindOf: MethodNode) ifTrue: [^self walk: aNode body].
	(aNode isKindOf: BlockNode) ifTrue: [^self walk: aNode body].
	(aNode isKindOf: MessageNode) ifTrue: [
		self walk: aNode receiver.
		aNode arguments do: [:each | self walk: each].
		^self].
	(aNode isKindOf: CascadeNode) ifTrue: [
		self walk: aNode receiver.
		aNode messages do: [:each | each arguments do: [:arg | self walk: arg]].
		^self].
	(aNode isKindOf: AssignmentNode) ifTrue: [^self walk: aNode value].
	(aNode isKindOf: ReturnNode) ifTrue: [^self walk: aNode value].
	(aNode isKindOf: BraceNode) ifTrue: [aNode elements do: [:each | self walk: each]]
! !

!StatementMap class methodsFor: 'instance creation'!
forMethod: aCompiledMethod
	^self new setSource: aCompiledMethod sourceCode doIt: aCompiledMethod selector == #DoIt
!
source: aString doIt: aBoolean
	^self new setSource: aString doIt: aBoolean
! !
