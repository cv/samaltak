Object subclass: #PlatformFFI
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Support'!

PlatformFFI comment: 'Private downcalls for platform facades. Cache successful bindings at their call sites and use a fixed-arity tryInvoke method. Use the legacy primitive only when bind: answers nil or invocation answers false. Native results (including zero or nil) never trigger fallback.'!

!PlatformFFI class methodsFor: 'binding'!
bind: descriptor
	"Bind a platform facade's literal call descriptor. Answer nil if it is unavailable."
	^FFI tryBindCall: descriptor
! !

!PlatformFFI class methodsFor: 'counted text'!
cTextBytes: anObject
	"Like textBytes:, but reject embedded NUL before a C-string downcall. Nil is a pre-entry miss, not an empty string."
	| bytes |
	bytes := self textBytes: anObject.
	(bytes isNil or: [bytes includes: 0]) ifTrue: [^nil].
	^bytes
!
textBytes: anObject
	"Exact ByteArray passes through unchanged. Encode only the VM's canonical String and Symbol classes; other inputs miss before entry. Preserve NUL for counted consumers such as stdout. No terminator is added."
	| class |
	class := anObject class.
	class == ByteArray ifTrue: [^anObject].
	(class == ByteString or: [class == WideString or: [class == ByteSymbol or: [class == WideSymbol]]]) ifFalse: [^nil].
	^ByteArray new: anObject size streamContents: [:out |
		anObject do: [:ch | self putTextCodePoint: ch value on: out]]
!
textFromBytes: bytes
	"Decode an exact ByteArray, including any NUL. Nil represents absence. Each ill-formed byte escapes independently (ObjectMemory>>utf8Decode:size:at:)."
	| i end first n out |
	bytes isNil ifTrue: [^nil].
	bytes class == ByteArray ifFalse: [^self error: 'Expected an exact ByteArray for counted text'].
	i := 1.
	end := bytes size.
	out := WriteStream on: (String new: end).
	[i <= end] whileTrue: [
		first := bytes at: i.
		first < 16r80
			ifTrue: [
				out nextPut: (Character value: first).
				i := i + 1]
			ifFalse: [
				n := bytes utf8LengthAt: i to: end.
				n > 0
					ifTrue: [
						out nextPut: (bytes utf8CharacterAt: i length: n).
						i := i + n]
					ifFalse: [
						out nextPut: (Character value: 16rDC00 + first).
						i := i + 1]]].
	^out contents
!
putTextCodePoint: codePoint on: out
	"Match ObjectMemory>>utf8BytesOf:size:, not the general-purpose UTF-8 encoder."
	| c |
	c := codePoint.
	(c between: 16rDC80 and: 16rDCFF) ifTrue: [^out nextPut: c - 16rDC00].
	(c > 16r10FFFF or: [c between: 16rD800 and: 16rDFFF]) ifTrue: [c := 16rFFFD].
	c < 16r80 ifTrue: [^out nextPut: c].
	c < 16r800
		ifTrue: [out nextPut: 16rC0 + (c bitShift: -6)]
		ifFalse: [
			c < 16r10000
				ifTrue: [out nextPut: 16rE0 + (c bitShift: -12)]
				ifFalse: [
					out nextPut: 16rF0 + (c bitShift: -18).
					out nextPut: 16r80 + ((c bitShift: -12) bitAnd: 16r3F)].
			out nextPut: 16r80 + ((c bitShift: -6) bitAnd: 16r3F)].
	out nextPut: 16r80 + (c bitAnd: 16r3F)
! !
