Object subclass: #LowtalkNames
	instanceVariableNames: ''
	classVariableNames: 'CKeywords'
	package: 'VM-Lowtalk'!

LowtalkNames comment: 'I turn Smalltalk names into C names: camel case into snake case (allocObj:format:slots: → alloc_obj, edenLo → eden_lo, CacheEntry → cache_entry), away from C keywords.'!

!LowtalkNames class methodsFor: 'converting'!
snake: aString
	"Answer aString (camelCase, possibly with colons) in snake case. UPPER_SNAKE stays as it is."
	| s out prev c next |
	s := aString asString copyWithout: $:.
	(s allSatisfy: [:ch | ch isUppercase or: [ch isDigit or: [ch = $_]]]) ifTrue: [^s].
	out := WriteStream on: String new.
	1 to: s size do: [:i |
		c := s at: i.
		prev := i > 1 ifTrue: [s at: i - 1] ifFalse: [nil].
		next := i < s size ifTrue: [s at: i + 1] ifFalse: [nil].
		(c isUppercase and: [prev notNil and: [prev ~= $_ and: [
			prev isLowercase or: [prev isDigit or: [next notNil and: [next isLowercase]]]]]])
				ifTrue: [out nextPut: $_].
		out nextPut: c asLowercase].
	^self avoidKeyword: out contents
!
functionNameFor: aSelector
	"The C name of a function: its selector's first keyword in snake case."
	| sel |
	sel := aSelector asString.
	(sel includes: $:) ifTrue: [sel := sel copyFrom: 1 to: (sel indexOf: $:) - 1].
	^self snake: sel
!
avoidKeyword: aString
	CKeywords isNil ifTrue: [
		CKeywords := Set withAll: #('auto' 'break' 'case' 'char' 'const' 'continue' 'default' 'do' 'double' 'else' 'enum' 'extern' 'float' 'for' 'goto' 'if' 'inline' 'int' 'long' 'register' 'restrict' 'return' 'short' 'signed' 'sizeof' 'static' 'struct' 'switch' 'typedef' 'union' 'unsigned' 'void' 'volatile' 'while' 'bool' 'true' 'false' 'main' 'errno' 'stdin' 'stdout' 'stderr' 'NULL')].
	^(CKeywords includes: aString) ifTrue: [aString , '_'] ifFalse: [aString]
! !
