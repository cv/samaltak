Object subclass: #NvRtcCache
	instanceVariableNames: 'options cubins order failed pending times limit'
	classVariableNames: ''
	package: 'System-NV'!

NvRtcCache comment: 'I keep the cubins NVRTC (NvRtc) makes of CUDA C++ sources with my options, by the SHA-256 of the source (keyOf:): a kept one answers at once; a source being compiled (in the background, isReady: or compileInBackground:key:, or by another Process) is waited for, not compiled twice; a source that did not compile keeps NVRTC''s log and is not compiled again. At most limit cubins (default 256) and 32 failures are kept, the oldest going first. NvShaderCompiler (Graphics-NV: the GLSL fragment shaders) has one, Cuda (System-CUDA) one per device architecture, for its kernels (Cuda kernelNamed:source:, CudaExpression''s fused element-wise kernels). times: the last compiles, key -> milliseconds.

	cache := NvRtcCache options: #(''-arch=sm_121'' ''-std=c++17'').
	cache cubinFor: cudaSource ifFail: [:log | self error: log]
	cache isReady: cudaSource         "true, or false after starting a compile in the background"'!

!NvRtcCache class methodsFor: 'instance creation'!
options: anArray
	^self new setOptions: anArray
! !

!NvRtcCache methodsFor: 'initialization'!
setOptions: anArray
	options := anArray.
	limit := 256.
	pending := Dictionary new.
	self flush
!
flush
	"Forget the cubins and failures (compiles under way go on, and keep what they make)."
	cubins := Dictionary new.
	order := OrderedCollection new.
	failed := Dictionary new
! !

!NvRtcCache methodsFor: 'accessing'!
options
	^options
!
limit: anInteger
	limit := anInteger max: 1
!
size
	^cubins size
!
keyOf: aString
	^(SHA256 hash: aString asByteArray) hex
!
includesKey: key
	"Whether a cubin, or a failure, is kept for key."
	^(cubins includesKey: key) or: [failed includesKey: key]
!
isPending: key
	"Whether a compile of key's source is under way."
	^pending includesKey: key
!
at: key
	"The cubin kept for key, or nil."
	^cubins at: key ifAbsent: [nil]
!
at: key put: aCubin
	"Keep aCubin for key (one compiled here, or made elsewhere: precompiled); the oldest go past limit."
	(cubins includesKey: key) ifFalse: [order addLast: key].
	cubins at: key put: aCubin.
	[cubins size > limit and: [order notEmpty]] whileTrue: [cubins removeKey: order removeFirst ifAbsent: []].
	^aCubin
!
failureAt: key
	"NVRTC's log for key's source that did not compile, or nil."
	^failed at: key ifAbsent: [nil]
!
times
	"The last compiles: key -> milliseconds."
	^times ifNil: [#()]
! !

!NvRtcCache methodsFor: 'compiling'!
cubinFor: aString ifFail: aBlock
	^self cubinFor: aString key: (self keyOf: aString) ifFail: aBlock
!
cubinFor: aString key: key ifFail: aBlock
	"The cubin of the CUDA C++ aString (key its keyOf:): kept, or compiled now, after waiting for a compile of it under way. If it does not compile, aBlock's value with NVRTC's log (or why nothing could compile it: no NVRTC here, which is not kept)."
	| cubin |
	self waitFor: key.
	(failed at: key ifAbsent: [nil]) ifNotNil: [:log | ^aBlock value: log].
	cubin := cubins at: key ifAbsent: [nil].
	cubin notNil ifTrue: [^cubin].
	NvRtc isAvailable ifFalse: [^aBlock value: 'no NVRTC here (the CUDA toolkit''s libnvrtc; SAMALTAK_NVRTC names it)'].
	cubin := self compile: aString key: key.
	cubin notNil ifTrue: [^cubin].
	^aBlock value: (failed at: key ifAbsent: ['NVRTC made no cubin'])
!
waitFor: key
	[pending includesKey: key] whileTrue: [(Delay forMilliseconds: 2) wait]
!
compile: aString key: key
	"Compile aString now (pending meanwhile); keep and answer its cubin, or keep NVRTC's log and answer nil."
	| t0 r |
	pending at: key put: true.
	[t0 := Time millisecondClockValue.
	r := NvRtc compile: aString options: options.
	self note: key ms: Time millisecondClockValue - t0]
		ensure: [pending removeKey: key ifAbsent: []].
	r first isNil ifTrue: [
		failed size >= 32 ifTrue: [failed := Dictionary new].
		failed at: key put: r last.
		^nil].
	^self at: key put: r first
!
isReady: aString
	^self isReady: aString key: (self keyOf: aString)
!
isReady: aString key: key
	"Whether cubinFor: answers at once (a cubin or a failure kept, or no NVRTC to compile with); if it would compile, start compiling in the background and answer false."
	(self includesKey: key) ifTrue: [^true].
	(pending includesKey: key) ifTrue: [^false].
	NvRtc isAvailable ifFalse: [^true].
	self compileInBackground: aString key: key.
	^false
!
compileInBackground: aString key: key
	"Compile aString in a Process of its own; pending at once, so cubinFor: waits for it instead of compiling it again. An error (NVRTC refusing the job) leaves nothing kept: cubinFor: tries again."
	(self includesKey: key) | (pending includesKey: key) ifTrue: [^self].
	pending at: key put: true.
	[[[self compile: aString key: key] on: Error do: [:e | nil]]
		ensure: [pending removeKey: key ifAbsent: []]] fork
! !

!NvRtcCache methodsFor: 'private'!
note: key ms: n
	times isNil ifTrue: [times := OrderedCollection new].
	times size >= 64 ifTrue: [times removeFirst].
	times add: key -> n
! !

!NvRtcCache methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an NvRtcCache '; print: options; nextPutAll: ': '; print: cubins size; nextPutAll: ' cubins'.
	pending isEmpty ifFalse: [aStream nextPutAll: ', '; print: pending size; nextPutAll: ' compiling']
! !
