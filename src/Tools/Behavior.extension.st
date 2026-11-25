!Behavior methodsFor: '*Tools'!
initializesAddedInstanceVariables
	"Whether a live update (SourceUpdate) sets the instance variables I gain, in the instances I already have, to what initialize sets them to in a new one (initializeAddedInstanceVariables:in:). Answer true in a class whose new only sets fields: nothing registered, opened or started, no other side effect. Otherwise they stay nil in my existing instances."
	^false
!
initializeAddedInstanceVariables: names in: instances
	"A live update gave me the instance variables names (Strings), nil in instances, the instances I had (each subclass gets this for its own). When initializesAddedInstanceVariables, set each that is still nil to its value in a new instance, a fresh one per instance (no two share a collection); a class that knows better overrides this. Answer whether they were set."
	| all indices |
	self initializesAddedInstanceVariables ifFalse: [^false].
	all := (self allInstVarNames collect: [:n | n asString]) asArray.
	indices := (names collect: [:n | all indexOf: n asString]) reject: [:i | i = 0].
	instances do: [:each | | fresh |
		fresh := self new.
		indices do: [:i | (each instVarAt: i) isNil ifTrue: [each instVarAt: i put: (fresh instVarAt: i)]]].
	^true
! !
