Object subclass: #NvShaderCompiler
	instanceVariableNames: ''
	classVariableNames: 'Cubins Translations Identity Times Precompiled Failed Pending'
	package: 'Graphics-NV'!

NvShaderCompiler comment: 'I make the GB10''s kernels of GLSL fragment shaders (FragmentShader''s, their prelude included): GlslShader parses and checks the source (a ShaderError at its line and column if it is not the GLSL subset), GlslCudaWriter writes it as CUDA C++ (the kernel gl_fragment), and its key, the SHA-256 of that CUDA, finds the cubin: made already in this session (kept), precompiled at build time (NvPrecompiledShaders, the shipped shaders: no compiler needed), or compiled now by NVRTC (NvRtc; NVRTC''s errors as ShaderErrors). A shader whose translation changed (a new GlslCudaWriter, or an edited source) has another key, so a precompiled cubin is never stale. docs/nv-shaders.md.

	NvShaderCompiler cubinFor: glslSource      "a ByteArray, or a ShaderError"
	NvShaderCompiler canBuild: glslSource      "precompiled, or NVRTC is here"
	NvShaderCompiler times                     "the last compiles: key -> milliseconds (translation, NVRTC)"'!

!NvShaderCompiler class methodsFor: 'compiling'!
cubinFor: aString
	"The cubin (gl_fragment for sm_121) of the GLSL fragment shader aString; a ShaderError if it does not compile."
	| cuda key |
	cuda := self cudaFor: aString.
	key := self keyOf: cuda.
	Cubins isNil ifTrue: [Cubins := Dictionary new. Failed := Dictionary new. Pending := Dictionary new].
	[Pending includesKey: key] whileTrue: [(Delay forMilliseconds: 5) wait].
	(Failed at: key ifAbsent: [nil]) ifNotNil: [:e | ^ShaderError line: e line column: e column detail: e detail].
	^Cubins at: key ifAbsent: [| cubin |
		cubin := self precompiledAt: key.
		cubin isNil ifTrue: [
			cubin := [self compile: cuda key: key] on: ShaderError do: [:e |
				Failed size >= 32 ifTrue: [Failed := Dictionary new].
				Failed at: key put: e.
				e pass]].
		Cubins at: key put: cubin.
		cubin]
!
isReady: aString
	"Whether cubinFor: aString answers (or signals its error) at once; if it would compile, start compiling in the background and answer false (a FragmentShader keeps its old pipeline meanwhile)."
	| key |
	key := [self keyFor: aString] on: ShaderError do: [:e | ^true].
	Cubins isNil ifTrue: [Cubins := Dictionary new. Failed := Dictionary new. Pending := Dictionary new].
	((Cubins includesKey: key) or: [(Failed includesKey: key) or: [self precompiled includesKey: key]]) ifTrue: [^true].
	(Pending includesKey: key) ifTrue: [^false].
	NvRtc isAvailable ifFalse: [^true].
	Pending at: key put: nil.
	[[self compileInBackground: aString key: key] ensure: [Pending removeKey: key ifAbsent: []]] fork.
	^false
!
compileInBackground: aString key: key
	| cubin |
	cubin := [self compile: (self cudaFor: aString) key: key] on: ShaderError do: [:e |
		Failed size >= 32 ifTrue: [Failed := Dictionary new].
		Failed at: key put: e.
		^self].
	Cubins at: key put: cubin
!
keyFor: aString
	"The key of the GLSL fragment shader aString (a ShaderError if it does not parse)."
	^self keyOf: (self cudaFor: aString)
!
canBuild: aString
	"Whether cubinFor: can make aString's kernel: NVRTC is here, or it is precompiled. A source that does not parse can be built (to report its error) where NVRTC is."
	NvRtc isAvailable ifTrue: [^true].
	^[| key | key := self keyFor: aString. (Cubins notNil and: [Cubins includesKey: key]) or: [self precompiled includesKey: key]]
		on: ShaderError do: [:e | e return: false]
!
canBuildAny
	"Whether any fragment shader runs: NVRTC is here, or some are precompiled."
	^NvRtc isAvailable or: [self precompiled notEmpty]
!
cudaFor: aString
	"aString's CUDA C++."
	^(self translationOf: aString) first
!
uniformSizeFor: aString
	"The bytes of aString's uniform block (std140)."
	^(self translationOf: aString) last
!
translationOf: aString
	"(cuda uniformSize) of aString, translated once (the last 32 sources are kept, looked up by identity first: ShaderView asks every frame)."
	| t0 r |
	Identity isNil ifTrue: [Identity := IdentityDictionary new. Translations := Dictionary new].
	(Identity at: aString ifAbsent: [nil]) ifNotNil: [:c | ^c].
	r := Translations at: aString ifAbsent: [| shader |
		t0 := Time millisecondClockValue.
		shader := GlslShader parse: aString.
		r := Array with: (GlslCudaWriter cudaFor: shader) with: shader uniformSize.
		self note: #translate ms: Time millisecondClockValue - t0.
		Translations size >= 32 ifTrue: [Translations := Dictionary new].
		Translations at: aString put: r].
	Identity size >= 32 ifTrue: [Identity := IdentityDictionary new].
	Identity at: aString put: r.
	^r
!
keyOf: aCudaString
	^(SHA256 hash: aCudaString asByteArray) hex
!
compile: cuda key: key
	"NVRTC's cubin of cuda; a ShaderError (NVRTC's first error) if it does not compile, or if there is no NVRTC."
	| t0 r |
	NvRtc isAvailable ifFalse: [
		^ShaderError line: nil column: nil detail: 'this shader is not precompiled (make nv-shaders), and there is no NVRTC here to compile it (the CUDA toolkit''s libnvrtc)'].
	t0 := Time millisecondClockValue.
	r := NvRtc compile: cuda options: self options.
	self note: #nvrtc ms: Time millisecondClockValue - t0.
	r first isNil ifTrue: [^self signalErrorIn: r last].
	^r first
!
options
	"NVRTC's options at run time: the GB10's code, ptxas at -O1 (a third of -O3's time for the World's shaders; NvPrecompiledShaders are -O3)."
	^#('-arch=sm_121' '-std=c++17' '-Xptxas=-O1')
!
buildOptions
	"NVRTC's options for NvPrecompiledShaders."
	^#('-arch=sm_121' '-std=c++17')
!
signalErrorIn: aLog
	"NVRTC's first error ('shader(12): error: ...': the shader's line, from my #line directives) as a ShaderError."
	| lines first |
	lines := aLog lines.
	first := lines detect: [:l | (l includesSubstring: 'error') ] ifNone: [lines isEmpty ifTrue: ['NVRTC failed'] ifFalse: [lines first]].
	((first beginsWith: 'shader(') and: [(first indexOf: $)) > 8]) ifTrue: [| n rest |
		n := (first copyFrom: 8 to: (first indexOf: $)) - 1) asInteger.
		rest := first copyFrom: (first indexOf: $)) + 1 to: first size.
		(rest beginsWith: ': ') ifTrue: [rest := rest allButFirst: 2].
		(rest beginsWith: 'error: ') ifTrue: [rest := rest allButFirst: 7].
		^ShaderError line: n column: nil detail: rest, ' (CUDA)'].
	^ShaderError line: nil column: nil detail: first
! !

!NvShaderCompiler class methodsFor: 'measuring'!
note: aSymbol ms: n
	Times isNil ifTrue: [Times := OrderedCollection new].
	Times size >= 64 ifTrue: [Times removeFirst].
	Times add: aSymbol -> n
!
times
	"The last translations and NVRTC compiles: #translate or #nvrtc -> milliseconds."
	^Times ifNil: [#()]
!
flush
	"Forget the cubins and translations made in this session."
	Cubins := Translations := Identity := Failed := Pending := nil
! !

!NvShaderCompiler class methodsFor: 'precompiling'!
precompiled
	"key -> cubin, compressed (ZLib), in Base64: NvPrecompiledShaders'."
	^Precompiled ifNil: [Precompiled := NvPrecompiledShaders encoded]
!
precompiledAt: aKey
	^(self precompiled at: aKey ifAbsent: [^nil]) ifNotNil: [:b64 | ZLib decompress: (Base64 decode: b64)]
!
shippedSources
	"The GLSL fragment shaders the image ships, their prelude included: every ShaderView's (late-bound: they are layers above)."
	| prelude views |
	prelude := (Smalltalk at: #FragmentShader) glslPrelude.
	views := (Smalltalk at: #ShaderView ifAbsent: [nil]) ifNil: [#()] ifNotNil: [:c | c allSubclasses].
	^(views reject: [:c | (c includesSelector: #glslShaderSource) not])
		collect: [:c | c name -> (prelude, c new glslShaderSource)]
!
precompiledSource
	"NvPrecompiledShaders' source: the shipped shaders compiled by NVRTC with buildOptions (make nv-shaders)."
	| entries |
	entries := self shippedSources collect: [:each | | cuda r |
		cuda := self cudaFor: each value.
		r := NvRtc compile: cuda options: self buildOptions.
		r first isNil ifTrue: [self error: each key, ': ', r last].
		Array with: each key with: (self keyOf: cuda) with: r first].
	^self sourceForPrecompiled: entries
!
sourceForPrecompiled: entries
	"NvPrecompiledShaders with entries, each (name key cubin): its class and comment as they are, the data in its two methods."
	| q s nl bang |
	q := [:str | '''', (str copyReplaceAll: '''' with: ''''''), ''''].
	nl := String with: Character lf.
	bang := String with: $!!.
	s := WriteStream on: String new.
	s nextPutAll: 'Object subclass: #NvPrecompiledShaders', nl, '	instanceVariableNames: ''''', nl, '	classVariableNames: ''''', nl, '	package: ''Graphics-NV''', bang, nl, nl.
	s nextPutAll: 'NvPrecompiledShaders comment: ', (q value: NvPrecompiledShaders comment), bang, nl, nl.
	s nextPutAll: bang, 'NvPrecompiledShaders class methodsFor: ''shaders''', bang, nl.
	s nextPutAll: 'encoded', nl, '	"key -> the cubin, compressed (ZLib), in Base64."', nl, '	^Dictionary new'.
	entries do: [:e | s nextPutAll: nl, '		at: ', (q value: (e at: 2)), ' put: ', (q value: (Base64 encode: (ZLib compress: (e at: 3)))), ';'].
	s nextPutAll: nl, '		yourself', nl, bang, nl.
	s nextPutAll: 'names', nl, '	"key -> the class whose shader it is."', nl, '	^Dictionary new'.
	entries do: [:e | s nextPutAll: nl, '		at: ', (q value: (e at: 2)), ' put: ', (q value: (e at: 1) asString), ';'].
	s nextPutAll: nl, '		yourself', nl, bang, ' ', bang, nl.
	^s contents
! !
