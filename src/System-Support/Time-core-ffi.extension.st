!Time class methodsFor: 'core FFI candidates'!
ffiCandidateUtcMicroseconds
	<ffiSite>
	| answer |
	answer := (self ffiSite: #(call 'vm:core' 'core_utc_microseconds' () i64)) tryInvoke0.
	answer == false ifTrue: [^self utcMicroseconds].
	answer = -4611686018427387904 ifTrue: [^self primitiveFailed].
	^answer
! !
