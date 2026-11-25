Object subclass: #TApprovedFFI
	instanceVariableNames: 'owner id name signature native testOnly'
	classVariableNames: ''
	package: 'VM-Translator'!

TApprovedFFI comment: 'I validate a declared downcall against its Lowtalk prototype. Only the defining module emits its dispatch; core never names SDL functions. The signature is the bytes of the nonzero argument tags, then the result tag: as a NUL-terminated C string it encodes the exact arity and signature.'!

!TApprovedFFI class methodsFor: 'collecting'!
fromFunctions: functions
	| rows ids names |
	rows := OrderedCollection new.
	ids := Set new.
	names := Set new.
	functions do: [:f |
		(f pragmaAt: #approvedFFI:symbol:arguments:result:) ifNotNil: [:spec |
			| row key |
			row := self new setFunction: f spec: spec.
			key := {row owner. row name}.
			((ids includes: row id) or: [names includes: key]) ifTrue: [
				row fail: 'duplicate approved export ID or name'].
			ids add: row id.
			names add: key.
			rows add: row]].
	^rows asSortedCollection: [:a :b | a id <= b id]
! !

!TApprovedFFI methodsFor: 'validation'!
setFunction: f spec: spec
	| key tags result parameters types accepted slot |
	native := f.
	owner := f module moduleClass name.
	(#('SDLPlatform' 'FFIPrimitives') includes: owner) ifFalse: [self fail: 'invalid approved export owner'].
	(f kind == #function and: [f hasPragma: #function]) ifFalse: [self fail: 'approved export must be a native <function>'].
	(f primitive notNil or: [f interface notNil or: [
		(#(#abi: #arch: #export #noreturn) anySatisfy: [:p | f hasPragma: p])]]) ifTrue: [self fail: 'approved export must use the default native ABI'].
	testOnly := f hasPragma: #approvedFFITest.
	key := spec first.
	(key isInteger and: [key between: 1 and: 4095]) ifFalse: [self fail: 'invalid approved export key'].
	id := 1024 + key.
	name := spec at: 2.
	(name isString and: [(name size between: 1 and: 127) and: [
		name allSatisfy: [:c | c value between: 1 and: 127]]]) ifFalse: [self fail: 'invalid approved export name'].
	(owner = 'SDLPlatform' and: [self class legacyPlatformNames includes: name]) ifTrue: [self fail: 'name reserved by a legacy FFI export'].
	tags := spec at: 3.
	result := spec at: 4.
	(tags class == Array and: [tags size <= 16 and: [tags allSatisfy: [:tag | #(1 2 3 4 6 8 9 10 13 14 16 17 18) includes: tag]]]) ifFalse: [
		self fail: 'invalid approved export argument tags'].
	(#(1 2 3 4 6 7 11 12 15 16) includes: result) ifFalse: [self fail: 'invalid approved export result tag'].
	(f pragmaAt: #returns:) = (Array with: ((result = 11 or: [result = 15]) ifTrue: ['void'] ifFalse: [self scalarType: result])) ifFalse: [self fail: 'result tag does not match explicit native type'].
	types := OrderedCollection new.
	((tags includes: 13) or: [(tags includes: 14) or: [result = 15]])
		ifTrue: [
			(owner = 'FFIPrimitives' and: [
				(tags = #(13) and: [result = 7]) or: [tags = #(14) and: [result = 15]]])
				ifFalse: [self fail: 'invalid synchronous text signature'].
			types add: (result = 7 ifTrue: [#('const uint8_t *')] ifFalse: [#('const char *')]).
			types add: #('uint64_t').
			result = 15 ifTrue: [types add: #('FFITextBuffer *')]]
		ifFalse: [
			tags do: [:tag |
				tag = 10
					ifTrue: [types add: #('const uint64_t *'); add: #('int64_t')]
					ifFalse: [
						(#(8 9 17 18) includes: tag)
							ifTrue: [
								types add: ((tag = 8 or: [tag = 17]) ifTrue: [#('const uint8_t *' 'const void *')] ifFalse: [#('uint8_t *' 'void *')]).
								types add: #('uint64_t')]
							ifFalse: [types add: (Array with: (self scalarType: tag))]]]].
	result = 11 ifTrue: [
		(owner = 'FFIPrimitives' and: [tags = #(10 10)]) ifFalse: [self fail: 'invalid owned integer result signature'].
		types add: #('BigIntegerNativeResult *')].
	parameters := f arguments.
	(types size <= 16 and: [types size = parameters size]) ifFalse: [self fail: 'wrong native slot count'].
	types doWithIndex: [:choices :i |
		slot := f declaredTypeOf: (parameters at: i).
		accepted := choices includes: slot.
		accepted ifFalse: [self fail: 'argument tag does not match explicit native type: ' , (parameters at: i)]].
	signature := (tags , (Array with: result)) asByteArray
!
scalarType: tag
	tag = 12 ifTrue: [^'int64_t'].
	tag = 16 ifTrue: [^'float'].
	^#('int32_t' 'uint32_t' 'int64_t' 'uint64_t' nil 'double' 'void') at: tag
!
fail: aString
	^TranslationError signal: native printString , ': ' , aString
! !

!TApprovedFFI class methodsFor: 'validation'!
legacyPlatformNames
	^((FFIPrimitives declarations detect: [:declaration | declaration first == #platformNames]) at: 3)
! !

!TApprovedFFI methodsFor: 'accessing'!
owner
	^owner
!
id
	^id
!
name
	^name
! !

!TApprovedFFI class methodsFor: 'generating'!
printLookup: cFunction rows: rows on: s
	| f args |
	f := cFunction function.
	args := f arguments collect: [:a | LowtalkNames snake: a].
	rows notEmpty ifTrue: [
		s nextPutAll: '#ifndef SAMALTAK_UEFI'; lf.
		rows do: [:entry | entry printTraceOn: s].
		s nextPutAll: '#endif'; lf].
	f isStatic ifTrue: [s nextPutAll: 'static '].
	s nextPutAll: cFunction definitionPrototype; lf; nextPut: ${; lf.
	rows notEmpty ifTrue: [
		s nextPutAll: '#ifndef SAMALTAK_UEFI'; lf.
		rows do: [:entry | entry printCheckWith: args on: s].
		s nextPutAll: '#endif'; lf].
	s nextPutAll: '    return 0;'; lf; nextPut: $}; lf
! !

!TApprovedFFI methodsFor: 'generating'!
printCheckWith: args on: s
	| nullable |
	testOnly ifTrue: [s nextPutAll: '#ifdef SAMALTAK_FFI_TEST_EXPORTS'; lf].
	nullable := signature last = 12.
	s nextPutAll: '    if ('.
	nullable ifTrue: [s nextPut: $(].
	self printSignature: signature is: args second on: s.
	"Tag 12 changes boxing, not the ABI. Keep the exact signed signature for older images."
	nullable ifTrue: [
		s nextPutAll: ' || '.
		self printSignature: (signature copy at: signature size put: 3; yourself) is: args second on: s.
		s nextPut: $)].
	s nextPutAll: ' && strcmp('; nextPutAll: args first; nextPutAll: ', ';
		nextPutAll: (CConst value: name type: nil) cString; nextPutAll: ') == 0) {'; lf;
		nextPutAll: '        *'; nextPutAll: args third; nextPutAll: ' = (uint64_t) '; nextPutAll: native cName; nextPut: $;; lf.
	self printTracedAddressWith: args on: s.
	s nextPutAll: '        return '; print: id; nextPut: $;; lf;
		nextPutAll: '    }'; lf.
	testOnly ifTrue: [s nextPutAll: '#endif'; lf]
!
printSignature: bytes is: argument on: s
	"Compare the dispatch's NUL-terminated tag string with bytes, each an octal escape."
	s nextPutAll: 'strcmp((const char *) '; nextPutAll: argument; nextPutAll: ', "'.
	bytes do: [:b | s nextPut: $\. b printOn: s base: 8 nDigits: 3].
	s nextPutAll: '") == 0'
! !
