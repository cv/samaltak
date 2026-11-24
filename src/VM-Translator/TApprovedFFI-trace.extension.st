!TApprovedFFI methodsFor: 'generating native entry witnesses'!
traceName
	^native cName , '_entry_witness'
!
printTraceOn: s
	"Only diagnostic resolutions address this typed forwarding function. The normal target, its ABI, and the wrapper compiler are unchanged."
	| type |
	type := (native pragmaAt: #returns:) first.
	testOnly ifTrue: [s nextPutAll: '#ifdef SAMALTAK_FFI_TEST_EXPORTS'; lf].
	s nextPutAll: 'static '; nextPutAll: type; space; nextPutAll: self traceName; nextPut: $(.
	native arguments isEmpty
		ifTrue: [s nextPutAll: 'void']
		ifFalse: [native arguments doWithIndex: [:arg :i |
			i > 1 ifTrue: [s nextPutAll: ', '].
			s nextPutAll: ((native parameterTypeAt: i) declarator: ('a', i printString))]].
	s nextPutAll: ') {'; lf.
	s nextPutAll: '    fprintf(stderr, "\nffi-native-entry '; print: id; nextPutAll: '\n");'; lf.
	s nextPutAll: '    '.
	type = 'void' ifFalse: [s nextPutAll: 'return '].
	s nextPutAll: native cName; nextPut: $(.
	1 to: native arguments size do: [:i |
		i > 1 ifTrue: [s nextPutAll: ', '].
		s nextPut: $a; print: i].
	s nextPutAll: ');'; lf; nextPut: $}; lf.
	testOnly ifTrue: [s nextPutAll: '#endif'; lf]
!
printTracedAddressWith: args on: s
	s nextPutAll: '        const char *trace = getenv("SAMALTAK_FFI_NATIVE_TRACE");'; lf.
	s nextPutAll: '        if (trace && strcmp(trace, "1") == 0) *';
		nextPutAll: args third; nextPutAll: ' = (uint64_t) '; nextPutAll: self traceName; nextPut: $;; lf
! !
