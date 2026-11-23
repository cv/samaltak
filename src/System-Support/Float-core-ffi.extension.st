!Float methodsFor: 'core FFI candidates'!
ffiCandidateFractionPart
	<ffiSite>
	| answer |
	answer := (self ffiSite: #(call 'vm:core' 'core_float_fraction_part' (f64) f64)) tryInvoke1: self.
	answer == false ifTrue: [^self fractionPart].
	^answer
!
ffiCandidatePrimPrintString
	| binding buffer count string |
	binding := CoreFFI floatPrintString.
	binding isNil ifTrue: [^self primPrintString].
	buffer := ByteArray new: 64.
	count := binding tryInvoke2: self with: {buffer. 1. 64}.
	count == false ifTrue: [^self primPrintString].
	count < 0 ifTrue: [^self primitiveFailed].
	string := ByteString new: count.
	string replaceFrom: 1 to: count with: buffer startingAt: 1.
	^string
! !
