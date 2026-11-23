!GPUPrimitives class methodsFor: '*Graphics-GPU-window'!
ffiCandidateOpenWindow: w height: h title: title flags: flags
	| binding bytes result |
	binding := WindowPlatformFFI openCall.
	bytes := binding isNil ifFalse: [PlatformFFI cTextBytes: title].
	(binding isNil or: [bytes isNil]) ifTrue: [^self openWindow: w height: h title: title flags: flags].
	result := binding tryInvoke4: w with: h with: {bytes. 1. bytes size} with: flags.
	result == false ifTrue: [^self openWindow: w height: h title: title flags: flags].
	result = 0 ifTrue: [^self fail: 'windowOpen'].
	^result
!
ffiCandidateWindowSize: window
	| binding bytes result |
	binding := WindowPlatformFFI sizeCall.
	binding isNil ifTrue: [^self windowSize: window].
	bytes := ByteArray new: 8.
	result := binding tryInvoke2: window with: {bytes. 1. 8}.
	result == false ifTrue: [^self windowSize: window].
	result = 0 ifTrue: [^self fail: 'windowSize'].
	^{WindowPlatformFFI signed32At: 1 in: bytes. WindowPlatformFFI signed32At: 5 in: bytes}
!
ffiCandidateWindowPixelSize: window
	| binding bytes result |
	binding := WindowPlatformFFI pixelSizeCall.
	binding isNil ifTrue: [^self windowPixelSize: window].
	bytes := ByteArray new: 8.
	result := binding tryInvoke2: window with: {bytes. 1. 8}.
	result == false ifTrue: [^self windowPixelSize: window].
	result = 0 ifTrue: [^self fail: 'windowPixelSize'].
	^{WindowPlatformFFI signed32At: 1 in: bytes. WindowPlatformFFI signed32At: 5 in: bytes}
!
ffiCandidateWindow: window title: title
	| binding bytes result |
	binding := WindowPlatformFFI titleCall.
	bytes := binding isNil ifFalse: [PlatformFFI cTextBytes: title].
	(binding isNil or: [bytes isNil]) ifTrue: [^self window: window title: title].
	result := binding tryInvoke2: window with: {bytes. 1. bytes size}.
	result == false ifTrue: [^self window: window title: title].
	result = 0 ifTrue: [^self fail: 'windowSetTitle'].
	^self
!
ffiCandidateWindow: window width: w height: h
	| binding result |
	binding := WindowPlatformFFI setSizeCall.
	binding isNil ifTrue: [^self window: window width: w height: h].
	result := binding tryInvoke3: window with: w with: h.
	result == false ifTrue: [^self window: window width: w height: h].
	^result = 0 ifTrue: [false] ifFalse: [self]
!
ffiCandidateClipboardGet
	| binding result |
	binding := WindowPlatformFFI clipboardGetCall.
	binding isNil ifTrue: [^self clipboardGet].
	result := FFIOwnedOutput captureUpTo: 67108864 do: [:ticket | binding tryInvoke1: ticket].
	result == false ifTrue: [^self clipboardGet].
	result class == ByteArray ifFalse: [^self fail: 'clipboardGet'].
	^PlatformFFI textFromBytes: result
!
ffiCandidateClipboardSet: title
	| binding bytes result |
	binding := WindowPlatformFFI clipboardSetCall.
	bytes := binding isNil ifFalse: [PlatformFFI cTextBytes: title].
	(binding isNil or: [bytes isNil]) ifTrue: [^self clipboardSet: title].
	result := binding tryInvoke1: {bytes. 1. bytes size}.
	result == false ifTrue: [^self clipboardSet: title].
	result = 0 ifTrue: [^self fail: 'clipboardSet'].
	^self
!
ffiCandidateClipboardData: mime
	| binding bytes result |
	binding := WindowPlatformFFI clipboardDataCall.
	bytes := binding isNil ifFalse: [PlatformFFI cTextBytes: mime].
	(binding isNil or: [bytes isNil]) ifTrue: [^self clipboardData: mime].
	result := FFIOwnedOutput captureUpTo: 20971520 do: [:ticket |
		binding tryInvoke2: {bytes. 1. bytes size} with: ticket].
	result == false ifTrue: [^self clipboardData: mime].
	^result class == ByteArray ifTrue: [result] ifFalse: [nil]
!
ffiCandidateLastError
	| binding bytes count |
	binding := WindowPlatformFFI lastErrorCall.
	binding isNil ifTrue: [^self lastError].
	bytes := ByteArray new: 1024.
	count := binding tryInvoke1: {bytes. 1. 1024}.
	count == false ifTrue: [^self lastError].
	count <= 0 ifTrue: [^''].
	^PlatformFFI textFromBytes: (bytes copyFrom: 1 to: count)
!
ffiCandidateNextEvent: a
	| binding result |
	binding := WindowPlatformFFI nextEventCall.
	(binding isNil or: [a class ~~ Array or: [a size < 8 or: [a isReadOnlyObject]]])
		ifTrue: [^self nextEvent: a].
	result := FFIOwnedOutput captureUpTo: 67108864 do: [:ticket | binding tryInvoke1: ticket].
	result == false ifTrue: [^self nextEvent: a].
	result isNil ifTrue: [^nil].
	result class == ByteArray ifFalse: [^self fail: 'nextEvent'].
	^WindowPlatformFFI decodeEvent: result into: a
!
ffiCandidateInjectEvent: a
	| binding bytes result |
	binding := WindowPlatformFFI injectEventCall.
	bytes := binding isNil ifFalse: [WindowPlatformFFI encodeEvent: a].
	(binding isNil or: [bytes isNil]) ifTrue: [^self injectEvent: a].
	result := binding tryInvoke1: {bytes. 1. bytes size}.
	result == false ifTrue: [^self injectEvent: a].
	result = 0 ifTrue: [^self fail: 'injectEvent'].
	^self
! !
