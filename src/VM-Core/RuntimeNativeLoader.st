VMCoreModule subclass: #RuntimeNativeLoader
	instanceVariableNames: 'dynamicLinker manifest grants grantCount'
	classVariableNames: 'NATIVE_GRANT_BYTES NATIVE_GRANT_BUFFER_SIZE NATIVE_GRANT_LIMIT NATIVE_GRANT_NAME_MAX NATIVE_GRANT_ARITY_MAX'
	package: 'VM-Core'!

RuntimeNativeLoader comment: 'The hosted launcher may grant fixed scalar exports before the image starts. It supplies absolute library paths, exact symbol names and their trusted C prototypes in SAMALTAK_NATIVE_GRANTS. The image supplies only counted logical names and tags. Lookup never loads a library and a target is returned only to VM code that builds the adapter.'!

!RuntimeNativeLoader class methodsFor: 'declaring'!
declarations
	^#((dynamicLinker PosixDynamicLinker) (manifest 'char[NATIVE_GRANT_BUFFER_SIZE]') (grants 'RuntimeNativeGrant[NATIVE_GRANT_LIMIT]') (grantCount int32_t))
!
initialize
	NATIVE_GRANT_BYTES := 4096.
	NATIVE_GRANT_BUFFER_SIZE := NATIVE_GRANT_BYTES + 1.
	NATIVE_GRANT_LIMIT := 32.
	NATIVE_GRANT_NAME_MAX := 127.
	NATIVE_GRANT_ARITY_MAX := 6
! !

!RuntimeNativeLoader methodsFor: 'launcher'!
configure
	<function>
	<returns: 'bool'>
	| source size line end row count handle last |
	"Called once, before loading the image. In the simulator there is no dynamic linker."
	dynamicLinker RTLD_NOW = 0 ifTrue: [^true].
	"Do not take executable grants from the environment of a set-ID invocation."
	(dynamicLinker uid ~= dynamicLinker euid or: [dynamicLinker gid ~= dynamicLinker egid]) ifTrue: [^true].
	source := libc getenv: 'SAMALTAK_NATIVE_GRANTS'.
	source isNull ifTrue: [^true].
	size := 0.
	[size <= NATIVE_GRANT_BYTES and: [(source at: size) ~= 0]] whileTrue: [size := size + 1].
	size > NATIVE_GRANT_BYTES ifTrue: [^false].
	libc memcpy: manifest from: source size: (size + 1) asUInt64.
	line := manifest + 0.
	count := 0.
	"Validate the whole manifest before opening any library."
	[line value ~= 0] whileTrue: [
		count >= NATIVE_GRANT_LIMIT ifTrue: [^false].
		end := self endOf: line or: 10.
		row := grants + count.
		last := end value = 0.
		end value: 0.
		(self parseRow: line into: row count: count) ifFalse: [^false].
		line := last ifTrue: [end] ifFalse: [end + 1].
		count := count + 1].
	0 to: count - 1 do: [:i |
		row := grants + i.
		handle := dynamicLinker open: row path flags: (dynamicLinker RTLD_NOW bitOr: dynamicLinker RTLD_LOCAL).
		handle isNull ifTrue: [^false].
		row target: (dynamicLinker symbol: row symbol in: handle).
		row target isNull ifTrue: [^false]].
	"Never dlclose: generated code and grant targets live for this VM process."
	grantCount := count.
	^true
!
endOf: text or: separator
	<var: #text type: 'char *'>
	<var: #separator type: 'int32_t'>
	| end |
	end := text.
	[end value ~= 0 and: [end value ~= separator]] whileTrue: [end := end + 1].
	^end
!
fieldAfter: text
	| end |
	end := self endOf: text or: $| value.
	end value = 0 ifTrue: [^self null].
	end value: 0.
	^end + 1
!
parseRow: line into: row count: count
	| name signature path previous |
	name := self fieldAfter: line.
	name isNull ifTrue: [^false].
	signature := self fieldAfter: name.
	signature isNull ifTrue: [^false].
	path := self fieldAfter: signature.
	path isNull ifTrue: [^false].
	(path value ~= $/ value or: [(self endOf: path or: $| value) value ~= 0]) ifTrue: [^false].
	((self validName: line alias: true) and: [self validName: name alias: false]) ifFalse: [^false].
	"Do not shadow curated namespaces or allow multiple claimed types for one name."
	((libc strcmp: line with: 'libc') = 0 or: [(libc strcmp: line with: 'libm') = 0 or: [
		(libc strcmp: line with: 'platform') = 0]]) ifTrue: [^false].
	0 to: count - 1 do: [:i |
		previous := grants + i.
		((libc strcmp: line with: previous library) = 0 and: [(libc strcmp: name with: previous symbol) = 0])
			ifTrue: [^false]].
	(self parseSignature: signature into: row) ifFalse: [^false].
	row library: line.
	row symbol: name.
	row path: path.
	row librarySize: (libc strlen: line).
	row symbolSize: (libc strlen: name).
	^true
!
validName: text alias: alias
	<var: #alias type: 'bool'>
	| size c |
	size := 0.
	[(c := text at: size) ~= 0] whileTrue: [
		size >= NATIVE_GRANT_NAME_MAX ifTrue: [^false].
		((c >= $A value and: [c <= $Z value]) or: [
			(c >= $a value and: [c <= $z value]) or: [
			c = $_ value or: [
			((alias or: [size > 0]) and: [c >= $0 value and: [c <= $9 value]]) or: [
			alias and: [c = $. value or: [c = $- value]]]]]]) ifFalse: [^false].
		size := size + 1].
	^size > 0
!
parseSignature: text into: row
	| start end result n tag more |
	end := self endOf: text or: $( value.
	end value = 0 ifTrue: [^false].
	end value: 0.
	result := self scalarTag: text.
	result = 0 ifTrue: [^false].
	start := end + 1.
	end := self endOf: start or: $) value.
	(end value = 0 or: [(end at: 1) ~= 0]) ifTrue: [^false].
	end value: 0.
	n := 0.
	more := start value ~= 0.
	[more] whileTrue: [
		n >= NATIVE_GRANT_ARITY_MAX ifTrue: [^false].
		end := self endOf: start or: $, value.
		more := end value ~= 0.
		end value: 0.
		tag := self scalarTag: start.
		(tag = 0 or: [tag = 7]) ifTrue: [^false].
		row types at: n put: tag asUInt8.
		n := n + 1.
		start := end + 1].
	row arity: n.
	row resultType: result.
	^true
!
scalarTag: text
	"Match the registry/adapter's tag numbers. No pointer form."
	(libc strcmp: text with: 'i32') = 0 ifTrue: [^1].
	(libc strcmp: text with: 'u32') = 0 ifTrue: [^2].
	(libc strcmp: text with: 'i64') = 0 ifTrue: [^3].
	(libc strcmp: text with: 'u64') = 0 ifTrue: [^4].
	(libc strcmp: text with: 'f64') = 0 ifTrue: [^6].
	(libc strcmp: text with: 'void') = 0 ifTrue: [^7].
	^0
! !

!RuntimeNativeLoader methodsFor: 'registry'!
lookupLibrary: library length: libLength symbol: symbol length: symLength types: types count: n result: result
	<function>
	<var: #library type: 'const uint8_t *'>
	<var: #libLength type: 'size_t'>
	<var: #symbol type: 'const uint8_t *'>
	<var: #symLength type: 'size_t'>
	<var: #types type: 'const uint8_t *'>
	<var: #n type: 'int32_t'>
	<var: #result type: 'int32_t'>
	<returns: 'void *'>
	| row |
	0 to: grantCount - 1 do: [:i |
		row := grants + i.
		(row arity = n and: [row resultType = result and: [
			row librarySize = libLength and: [row symbolSize = symLength and: [
			(libc memcmp: library with: row library size: libLength) = 0 and: [
			(libc memcmp: symbol with: row symbol size: symLength) = 0 and: [
			n = 0 or: [(libc memcmp: types with: row types size: n asUInt64) = 0]]]]]]])
				ifTrue: [^row target]].
	^self null
! !

VMStruct subclass: #RuntimeNativeGrant
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

!RuntimeNativeGrant class methodsFor: 'declaring'!
fields
	^#((library 'const char *') (symbol 'const char *') (path 'const char *')
		(librarySize size_t) (symbolSize size_t) (types 'uint8_t[6]')
		(arity int32_t) (resultType int32_t) (target 'void *'))
! !
