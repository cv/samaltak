!GPUPrimitives class methodsFor: '*Graphics-GPU-window'!
openWindow: w height: h title: title flags: flags
	| binding bytes result |
	binding := WindowPlatformFFI openCall.
	bytes := binding isNil ifFalse: [WindowPlatformFFI cTextBytes: title].
	(binding isNil or: [bytes isNil]) ifTrue: [^self ffiRejected: 'windowOpen'].
	result := binding tryInvoke4: w with: h with: {bytes. 1. bytes size} with: flags.
	result == false ifTrue: [^self ffiRejected: 'windowOpen'].
	result = 0 ifTrue: [^self fail: 'windowOpen'].
	^result
!
windowSize: window
	| binding bytes result |
	binding := WindowPlatformFFI sizeCall.
	binding isNil ifTrue: [^self ffiRejected: 'windowSize'].
	bytes := ByteArray new: 8.
	result := binding tryInvoke2: window with: {bytes. 1. 8}.
	result == false ifTrue: [^self ffiRejected: 'windowSize'].
	result = 0 ifTrue: [^self fail: 'windowSize'].
	^{WindowPlatformFFI signed32At: 1 in: bytes. WindowPlatformFFI signed32At: 5 in: bytes}
!
windowPixelSize: window
	| binding bytes result |
	binding := WindowPlatformFFI pixelSizeCall.
	binding isNil ifTrue: [^self ffiRejected: 'windowPixelSize'].
	bytes := ByteArray new: 8.
	result := binding tryInvoke2: window with: {bytes. 1. 8}.
	result == false ifTrue: [^self ffiRejected: 'windowPixelSize'].
	result = 0 ifTrue: [^self fail: 'windowPixelSize'].
	^{WindowPlatformFFI signed32At: 1 in: bytes. WindowPlatformFFI signed32At: 5 in: bytes}
!
window: window title: title
	| binding bytes result |
	binding := WindowPlatformFFI titleCall.
	bytes := binding isNil ifFalse: [WindowPlatformFFI cTextBytes: title].
	(binding isNil or: [bytes isNil]) ifTrue: [^self ffiRejected: 'windowSetTitle'].
	result := binding tryInvoke2: window with: {bytes. 1. bytes size}.
	result == false ifTrue: [^self ffiRejected: 'windowSetTitle'].
	result = 0 ifTrue: [^self fail: 'windowSetTitle'].
	^self
!
window: window width: w height: h
	| binding result |
	binding := WindowPlatformFFI setSizeCall.
	binding isNil ifTrue: [^false].
	result := binding tryInvoke3: window with: w with: h.
	result == false ifTrue: [^false].
	^result = 0 ifTrue: [false] ifFalse: [self]
!
window: window background: rgb
	| binding result |
	binding := WindowPlatformFFI backgroundCall.
	binding isNil ifTrue: [^false].
	result := binding tryInvoke2: window with: rgb.
	result == false ifTrue: [^false].
	^result = 0 ifTrue: [false] ifFalse: [self]
!
window: window minimumWidth: w height: h
	| binding result |
	binding := WindowPlatformFFI minimumSizeCall.
	binding isNil ifTrue: [^false].
	result := binding tryInvoke3: window with: w with: h.
	result == false ifTrue: [^false].
	^result = 0 ifTrue: [false] ifFalse: [self]
!
window: window presentingWidth: w height: h
	| binding |
	binding := WindowPlatformFFI presentingCall.
	binding isNil ifFalse: [binding tryInvoke3: window with: w with: h]
!
clipboardGet
	| binding result |
	binding := WindowPlatformFFI clipboardGetCall.
	binding isNil ifTrue: [^self ffiRejected: 'clipboardGet'].
	result := FFIPagedPlatformOutput capture: [:receipt | binding tryInvoke1: {receipt. 1. 16}].
	result == false ifTrue: [^self ffiRejected: 'clipboardGet'].
	result class == ByteArray ifFalse: [^self fail: 'clipboardGet'].
	^PlatformFFI textFromBytes: result
!
clipboardSet: title
	| binding bytes result |
	binding := WindowPlatformFFI clipboardSetCall.
	bytes := binding isNil ifFalse: [WindowPlatformFFI cTextBytes: title].
	(binding isNil or: [bytes isNil]) ifTrue: [^self ffiRejected: 'clipboardSet'].
	result := binding tryInvoke1: {bytes. 1. bytes size}.
	result == false ifTrue: [^self ffiRejected: 'clipboardSet'].
	result = 0 ifTrue: [^self fail: 'clipboardSet'].
	^self
!
clipboardData: mime
	| binding bytes result |
	binding := WindowPlatformFFI clipboardDataCall.
	bytes := binding isNil ifFalse: [WindowPlatformFFI cTextBytes: mime].
	(binding isNil or: [bytes isNil]) ifTrue: [^nil].
	result := FFIOwnedOutput captureUpTo: 20971520 do: [:ticket |
		binding tryInvoke2: {bytes. 1. bytes size} with: ticket].
	result == false ifTrue: [^nil].
	^result class == ByteArray ifTrue: [result] ifFalse: [nil]
!
lastError
	^WindowPlatformFFI lastError ifNil: ['']
!
nextEvent: a
	| binding header result |
	binding := WindowPlatformFFI nextEventCall.
	(binding isNil or: [a class instSpec ~= VMConstants fVar or: [a basicSize < 8 or: [a isReadOnlyObject]]])
		ifTrue: [^self ffiRejected: 'nextEvent'].
	header := ByteArray new: 80.
	result := FFIPagedPlatformOutput capture: [:receipt |
		binding tryInvoke2: {header. 1. 80} with: {receipt. 1. 16}].
	result == false ifTrue: [^self ffiRejected: 'nextEvent'].
	result isNil ifTrue: [^nil].
	result class == ByteArray ifFalse: [^self fail: 'nextEvent'].
	^WindowPlatformFFI decodeEvent: header text: result into: a
!
injectEvent: a
	(WindowPlatformFFI tryInjectEvent: a) ifFalse: [^self ffiRejected: 'injectEvent'].
	^self
! !
