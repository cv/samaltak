Object subclass: #RemoteRefTable
	instanceVariableNames: 'refs'
	classVariableNames: ''
	package: 'System-Remote'!

RemoteRefTable comment: 'I remember which ref each widget got in the last snapshot (an IdentityDictionary widget -> ref), so a widget keeps its ref while it stays under the same parent with the same name, even when siblings with the same name come and go. A ref is its parent''s ref, a dot and the slug of the widget''s remoteName (or label, or role); among siblings, repeated slugs get ~2, ~3, ...'!

!RemoteRefTable methodsFor: 'initialization'!
initialize
	refs := IdentityDictionary new
! !

!RemoteRefTable methodsFor: 'assigning'!
assignTopLevel: nodes
	"Assign refs to the whole tree below nodes (top-level nodes have no prefix) and remember them, forgetting widgets that are gone."
	| assigned |
	assigned := IdentityDictionary new.
	self assign: nodes prefix: '' into: assigned.
	refs := assigned
!
assign: nodes prefix: prefix into: assigned
	| siblings used pending base old |
	siblings := nodes reject: [:each | each isString].
	used := Set new.
	pending := OrderedCollection new.
	siblings do: [:node |
		base := prefix isEmpty ifTrue: [node name] ifFalse: [prefix, '.', node name].
		old := refs at: node widget ifAbsent: [nil].
		(old notNil and: [(self class baseOf: old) = base and: [(used includes: old) not]])
			ifTrue: [node ref: old. used add: old]
			ifFalse: [pending add: node -> base]].
	pending do: [:each | | candidate n |
		candidate := each value.
		n := 1.
		[used includes: candidate] whileTrue: [
			n := n + 1.
			candidate := each value, '~', n printString].
		each key ref: candidate.
		used add: candidate].
	siblings do: [:node |
		assigned at: node widget put: node ref.
		self assign: node children prefix: node ref into: assigned]
!
refOf: aWidget
	^refs at: aWidget ifAbsent: [nil]
! !

!RemoteRefTable class methodsFor: 'refs'!
baseOf: aRef
	"Answer aRef without a ~n suffix on its last component."
	| tilde dot |
	tilde := aRef lastIndexOf: $~.
	tilde = 0 ifTrue: [^aRef].
	dot := aRef lastIndexOf: $..
	tilde < dot ifTrue: [^aRef].
	^aRef copyFrom: 1 to: tilde - 1
!
slug: aString
	"Answer aString as a ref component: lowercase letters, digits, _ and -, at most 40 characters; operators get names (+ -> plus)."
	| s lastDash result |
	s := WriteStream on: (String new: aString size).
	lastDash := true.
	aString asString asLowercase do: [:c |
		((c value < 128 and: [c isLetter or: [c isDigit]]) or: [c = $_])
			ifTrue: [s nextPut: c. lastDash := false]
			ifFalse: [lastDash ifFalse: [s nextPut: $-. lastDash := true]]].
	result := s contents.
	(result notEmpty and: [result last = $-]) ifTrue: [result := result allButLast].
	result isEmpty ifTrue: [result := self operatorSlug: aString].
	result size > 40 ifTrue: [result := result first: 40].
	(result notEmpty and: [result last = $-]) ifTrue: [result := result allButLast].
	^result
!
operatorSlug: aString
	| names |
	names := OrderedCollection new.
	aString do: [:c | (self operatorName: c) ifNotNil: [:n | names add: n]].
	^names inject: '' into: [:a :b | a isEmpty ifTrue: [b] ifFalse: [a, '-', b]]
!
operatorName: aCharacter
	| ops i |
	ops := '+-*/\<>=~@%|&?,^!!'.
	i := ops indexOf: aCharacter.
	i = 0 ifTrue: [^nil].
	^#('plus' 'minus' 'star' 'slash' 'backslash' 'lt' 'gt' 'eq' 'tilde' 'at' 'pct' 'bar' 'amp' 'qm' 'comma' 'caret' 'bang') at: i
! !
