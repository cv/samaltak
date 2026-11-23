!Integer methodsFor: 'candidate integer calls'!
ffiCandidateCompareInteger: anInteger
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'vm:core' 'core_bigint_compare' (integerMagnitude integerMagnitude) i32))
		tryInvoke2: self with: anInteger.
	result == false ifTrue: [^self compareInteger: anInteger].
	^result
! !
