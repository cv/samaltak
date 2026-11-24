!FFIPrimitives methodsFor: 'owned output test fixture'!
ownedTest: ticket mode: mode
	<function>
	<approvedFFI: 4004 symbol: 'ffi_test_owned_octets' arguments: #(4 1) result: 1>
	<approvedFFITest>
	<var: #ticket type: 'uint64_t'>
	<var: #mode type: 'int32_t'>
	<returns: 'int32_t'>
	| enabled bytes copy published |
	enabled := libc getenv: 'SAMALTAK_FFI_OWNED_TEST'.
	(enabled isNull or: [(libc strcmp: enabled with: '1') ~= 0]) ifTrue: [^-37].
	(self ownedCanProduce: ticket) ifFalse: [^-29].
	mode = 0 ifTrue: [^0].
	mode < 0 ifTrue: [^-17].
	mode = 2 ifTrue: [
		^(self ownedPublish: ticket from: self null size: 0 asUInt64)
			ifTrue: [1] ifFalse: [-23]].
	mode = 4 ifTrue: [^1]. "Broken producer for testing completed copyout rejection."
	bytes := self local: 'uint8_t[5]'.
	bytes at: 0 put: 0.
	bytes at: 1 put: 255.
	bytes at: 2 put: 65.
	bytes at: 3 put: 128.
	bytes at: 4 put: 0.
	mode = 3 ifTrue: [
		copy := self cCoerce: (libc malloc: 5 asUInt64) to: 'uint8_t *'.
		copy isNull ifTrue: [^-23].
		libc memcpy: copy from: bytes size: 5 asUInt64.
		published := self ownedAdopt: ticket from: copy size: 5 asUInt64 capacity: 5 asUInt64.
		published ifFalse: [libc free: copy]]
		ifFalse: [published := self ownedPublish: ticket from: bytes size: 5 asUInt64].
	^published ifTrue: [1] ifFalse: [-23]
! !
