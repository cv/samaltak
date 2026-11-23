Object subclass: #TApprovedFFI
	instanceVariableNames: 'owner id name signature native testOnly'
	classVariableNames: ''
	package: 'VM-Translator'!

TApprovedFFI comment: 'I validate a declared downcall against its Lowtalk prototype. Only the defining module emits its dispatch; core never names SDL functions. Nonzero tags packed in nibbles encode the exact arity and signature.'!

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
	(tags class == Array and: [tags size <= 6 and: [tags allSatisfy: [:tag | #(1 2 3 4 6 8 9 10) includes: tag]]]) ifFalse: [
		self fail: 'invalid approved export argument tags'].
	(#(1 2 3 4 6 7) includes: result) ifFalse: [self fail: 'invalid approved export result tag'].
	(f pragmaAt: #returns:) = (Array with: (self scalarType: result)) ifFalse: [self fail: 'result tag does not match explicit native type'].
	types := OrderedCollection new.
	tags do: [:tag |
		tag = 10
			ifTrue: [types add: #('const uint64_t *'); add: #('int64_t')]
			ifFalse: [
				(#(8 9) includes: tag)
					ifTrue: [
						types add: (tag = 8 ifTrue: [#('const uint8_t *' 'const void *')] ifFalse: [#('uint8_t *' 'void *')]).
						types add: #('uint64_t')]
					ifFalse: [types add: (Array with: (self scalarType: tag))]]].
	parameters := f arguments.
	(types size <= 6 and: [types size = parameters size]) ifFalse: [self fail: 'wrong native slot count'].
	types doWithIndex: [:choices :i |
		slot := f declaredTypeOf: (parameters at: i).
		accepted := choices includes: slot.
		accepted ifFalse: [self fail: 'argument tag does not match explicit native type: ' , (parameters at: i)]].
	signature := tags inject: 0 into: [:sig :tag | (sig bitShift: 4) + tag].
	signature := (signature bitShift: 4) + result
!
scalarType: tag
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
	testOnly ifTrue: [s nextPutAll: '#ifdef SAMALTAK_FFI_TEST_EXPORTS'; lf].
	s nextPutAll: '    if ('; nextPutAll: args second; nextPutAll: ' == '; print: signature;
		nextPutAll: ' && strcmp('; nextPutAll: args first; nextPutAll: ', ';
		nextPutAll: (CConst value: name type: nil) cString; nextPutAll: ') == 0) {'; lf;
		nextPutAll: '        *'; nextPutAll: args third; nextPutAll: ' = (uint64_t) '; nextPutAll: native cName; nextPut: $;; lf.
	self printTracedAddressWith: args on: s.
	s nextPutAll: '        return '; print: id; nextPut: $;; lf;
		nextPutAll: '    }'; lf.
	testOnly ifTrue: [s nextPutAll: '#endif'; lf]
! !
