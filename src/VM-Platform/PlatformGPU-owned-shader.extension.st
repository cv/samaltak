!PlatformGPU methodsFor: 'owned shader compiler output'!
shaderOutputRoom: out capacity: cap
	"Per-process leases, bound only the number of live results, not their aggregate bytes."
	<function>
	<var: #out type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'gpu_shader_output *'>
	| nonce row |
	cap ~= 16 ifTrue: [
		common setError: 'wrong GPU shader output receipt size'.
		^self null].
	0 to: 15 do: [:i | (out at: i) ~= 0 ifTrue: [
		common setError: 'GPU shader output requires a fresh receipt'.
		^self null]].
	shaderOutputSession = 0 ifTrue: [
		nonce := self local: 'uint64_t'.
		((posix getEntropy: nonce size: 8) = 0 and: [
			(nonce value bitAnd: 16r3FFFFFFFFFFFFFFF asUInt64) ~= 0]) ifFalse: [
			common setError: 'cannot initialize GPU shader output tickets'.
			^self null].
		shaderOutputSession := nonce value bitAnd: 16r3FFFFFFFFFFFFFFF asUInt64].
	shaderOutputSerial >= 16r3FFFFFFFFFFFFFFE asUInt64 ifTrue: [
		common setError: 'GPU shader output ticket space exhausted'.
		^self null].
	0 to: MAX_SHADER_OUTPUTS - 1 do: [:i |
		row := shaderOutputs + i.
		row ticket = 0 ifTrue: [^row]].
	common setError: 'too many outstanding GPU shader outputs'.
	^self null
!
adoptShaderOutput: row bytes: payload count: n receipt: out
	<function>
	<var: #row type: 'gpu_shader_output *'>
	<var: #payload type: 'uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #out type: 'uint8_t *'>
	<returns: 'bool'>
	| ticket |
	n > 16r7FFFFFFF8 asUInt64 ifTrue: [
		common setError: 'GPU shader output cannot fit a ByteArray'.
		^false].
	shaderOutputSerial := shaderOutputSerial + 1.
	shaderOutputSerial = shaderOutputSession ifTrue: [shaderOutputSerial := shaderOutputSerial + 1].
	ticket := shaderOutputSession bitXor: shaderOutputSerial.
	row payload: payload.
	row payloadBytes: n.
	row ticket: ticket.
	0 to: 7 do: [:i | out at: i + 8 put: (n >> (i * 8)) asUInt8].
	0 to: 7 do: [:i | out at: i put: (ticket >> (i * 8)) asUInt8].
	^true
!
shaderOutputRow: ticket
	<function>
	<var: #ticket type: 'uint64_t'>
	<returns: 'gpu_shader_output *'>
	| row |
	ticket = 0 ifTrue: [^self null].
	0 to: MAX_SHADER_OUTPUTS - 1 do: [:i |
		row := shaderOutputs + i.
		row ticket = ticket ifTrue: [^row]].
	^self null
!
copyShaderOutput: ticket offset: offset into: out capacity: cap
	<function>
	<var: #ticket type: 'uint64_t'>
	<var: #offset type: 'uint64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'bool'>
	| row |
	row := self shaderOutputRow: ticket.
	(row isNull or: [cap > 1048576 or: [offset > row payloadBytes or: [
		cap > (row payloadBytes - offset)]]]) ifTrue: [
		common setError: 'invalid GPU shader output page'.
		^false].
	cap ~= 0 ifTrue: [libc memcpy: out from: row payload + offset size: cap].
	^true
!
clearShaderOutput: row
	<function>
	<var: #row type: 'gpu_shader_output *'>
	libc free: row payload.
	row ticket: 0.
	row payload: self null.
	row payloadBytes: 0
!
releaseShaderOutput: ticket
	<function>
	<var: #ticket type: 'uint64_t'>
	<returns: 'bool'>
	| row |
	row := self shaderOutputRow: ticket.
	row isNull ifTrue: [^false].
	self clearShaderOutput: row.
	^true
!
discardShaderOutputs
	<function>
	| row |
	0 to: MAX_SHADER_OUTPUTS - 1 do: [:i |
		row := shaderOutputs + i.
		row ticket ~= 0 ifTrue: [self clearShaderOutput: row]]
! !
