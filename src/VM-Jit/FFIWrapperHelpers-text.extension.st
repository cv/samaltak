!FFIWrapperHelpers methodsFor: 'synchronous text arguments'!
textArgumentHelper: tag
	^self cCoerce: (tag = 13
		ifTrue: [self functionPointer: #ffiPrepareCountedText:into:]
		ifFalse: [self functionPointer: #ffiPrepareCText:into:]) to: 'uint64_t'
!
textResultHelper: tag
	tag = 7 ifTrue: [^self cCoerce: (self functionPointer: #ffiReleaseCountedText:) to: 'uint64_t'].
	(libc getenv: 'SAMALTAK_FFI_BOX_FULL_GC') notNull ifTrue: [
		^self cCoerce: (self functionPointer: #ffiBoxOwnedTextWithGC:) to: 'uint64_t'].
	^self cCoerce: (self functionPointer: #ffiBoxOwnedText:) to: 'uint64_t'
!
ffiPrepareCountedText: o into: out
	<function>
	<var: #o type: 'oop'>
	<var: #out type: 'FFITextBuffer *'>
	<returns: 'bool'>
	^self prepareText: o into: out terminated: false
!
ffiPrepareCText: o into: out
	<function>
	<var: #o type: 'oop'>
	<var: #out type: 'FFITextBuffer *'>
	<returns: 'bool'>
	^self prepareText: o into: out terminated: true
!
ascii: bytes size: n
	"Both VM byte bodies and the owned buffer are aligned. Read no padding."
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'bool'>
	| i word |
	word := self local: 'uint64_t'.
	i := 0 asUInt64.
	[i + 8 <= n] whileTrue: [
		libc memcpy: word from: bytes + i size: 8.
		(word value bitAnd: 16r8080808080808080 asUInt64) ~= 0 ifTrue: [^false].
		i := i + 8].
	[i < n] whileTrue: [
		(bytes at: i) >= 128 ifTrue: [^false].
		i := i + 1].
	^true
!
prepareText: o into: out terminated: terminated
	<var: #terminated type: 'bool'>
	| c bytes fmt n size copy ascii capacity byteArray |
	(o = 0 or: [(self isPtr: o) not]) ifTrue: [^false].
	c := self rawClass: o.
	fmt := self formatOf: o.
	byteArray := c = memory clsBytearray and: [terminated not].
	(byteArray or: [memory isKindOfString: o]) ifFalse: [^false].
	out allocation: self null.
	(byteArray or: [c = memory clsBytestring or: [c = (memory special: SO_BYTESYMBOL)]])
		ifTrue: [
			(fmt < F_BYTES or: [fmt >= (F_BYTES + 8)]) ifTrue: [^false].
			n := (self numSlots: o) asUInt64 * 8.
			n < (fmt - F_BYTES) asUInt64 ifTrue: [^false].
			n := n - (fmt - F_BYTES) asUInt64.
			bytes := self bytesOf: o.
			ascii := byteArray or: [self ascii: bytes size: n].
			(ascii and: [terminated not]) ifTrue: [
				out data: bytes.
				out count: n.
				^true].
			(terminated and: [(libc memchr: bytes value: 0 size: n) notNull]) ifTrue: [^false].
			capacity := (ascii ifTrue: [n] ifFalse: [2 * n]) + (terminated ifTrue: [1] ifFalse: [0]).
			copy := out small.
			capacity > 512 ifTrue: [
				copy := self cCoerce: (libc malloc: capacity) to: 'uint8_t *'.
				copy isNull ifTrue: [^false].
				out allocation: copy].
			ascii
				ifTrue: [libc memcpy: copy from: bytes size: n]
				ifFalse: [n := self encodeLatin1: bytes size: n into: copy].
			terminated ifTrue: [copy at: n put: 0].
			out data: copy.
			out count: n.
			^true].
	((fmt = F_W32 or: [fmt = (F_W32 + 1)]) and: [
		(fmt - F_W32) asUInt64 <= ((self numSlots: o) asUInt64 * 2)]) ifFalse: [^false].
	"Use the VM codec for wide code points and surrogate escapes."
	size := self local: 'size_t'.
	copy := self cCoerce: (memory utf8BytesOf: o size: size) to: 'uint8_t *'.
	copy isNull ifTrue: [^false].
	(terminated and: [(libc memchr: copy value: 0 size: size value) notNull]) ifTrue: [
		libc free: copy.
		^false].
	out data: copy.
	out count: size value.
	out allocation: copy.
	^true
!
encodeLatin1: bytes size: n into: copy
	"ByteString and ByteSymbol hold code points, not UTF-8 bytes. As in
	 ObjectMemory, 0..127 are unchanged and 128..255 expand to two bytes."
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #copy type: 'uint8_t *'>
	<returns: 'uint64_t'>
	| p i code |
	p := copy.
	i := 0 asUInt64.
	[i < n] whileTrue: [
		code := bytes at: i.
		code >= 128 ifTrue: [
			p value: (16rC0 bitOr: (code >> 6)) asUInt8.
			p := p + 1.
			code := (16r80 bitOr: (code bitAnd: 16r3F)) asUInt8].
		p value: code.
		p := p + 1.
		i := i + 1].
	^(p - copy) asUInt64
!
ffiReleaseCountedText: out
	<function>
	<var: #out type: 'FFITextBuffer *'>
	<returns: 'oop'>
	out allocation notNull ifTrue: [libc free: out allocation].
	^memory nilOop
! !

!FFIWrapperHelpers methodsFor: 'owned text results'!
ffiBoxOwnedText: out
	<function>
	<var: #out type: 'FFITextBuffer *'>
	<returns: 'oop'>
	| answer n data bytes slots padding |
	data := out data.
	data isNull ifTrue: [^memory nilOop].
	"Never allocate while an input still points into the Smalltalk heap."
	jit syncPendingBoundFrame.
	n := out count.
	(self ascii: data size: n)
		ifTrue: [
			padding := (8 - (n bitAnd: 7)) bitAnd: 7.
			slots := (n + padding) quo: 8.
			answer := memory allocUnfilledTry: memory clsBytestring format: F_BYTES + padding asInt32 slots: slots.
			answer = 0
				ifTrue: [answer := memory nilOop]
				ifFalse: [
					bytes := self bytesOf: answer.
					libc memcpy: bytes from: data size: n.
					padding > 0 ifTrue: [libc memset: bytes + n value: 0 size: padding]]]
		ifFalse: [answer := memory stringFromUtf8: (self cCoerce: data to: 'const char *') size: n].
	out allocation notNull ifTrue: [libc free: out allocation].
	^answer
!
ffiBoxOwnedTextWithGC: out
	<function>
	<var: #out type: 'FFITextBuffer *'>
	<returns: 'oop'>
	jit syncPendingBoundFrame.
	gc fullGC.
	^self ffiBoxOwnedText: out
! !
