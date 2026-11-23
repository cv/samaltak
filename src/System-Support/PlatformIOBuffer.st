Object subclass: #PlatformIOBuffer
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Support'!

PlatformIOBuffer comment: 'Convert a raw byte or 32-bit word slice into the exact ByteArray accepted by a prepared I/O call. Copy a read result back without touching bytes outside the actual result.'!

!PlatformIOBuffer class methodsFor: 'slices'!
sizeOf: buffer
	| class |
	class := buffer class.
	class isWords ifTrue: [^buffer basicSize * 4].
	(class isBytes and: [class inheritsFrom: CompiledMethod]) ifTrue: [^-1].
	class == CompiledMethod ifTrue: [^-1].
	class isBytes ifTrue: [^buffer basicSize].
	^-1
!
valid: buffer start: start count: count
	(start isInteger and: [count isInteger]) ifFalse: [^false].
	^start >= 1 and: [count >= 0 and: [start - 1 + count <= (self sizeOf: buffer)]]
!
writeSliceFrom: buffer start: start count: count
	| bytes |
	(self valid: buffer start: start count: count) ifFalse: [^nil].
	bytes := ByteArray new: count.
	buffer class isWords ifFalse: [
		^bytes replaceFrom: 1 to: count with: buffer startingAt: start].
	1 to: count do: [:i |
		| offset word |
		offset := start + i - 2.
		word := buffer basicAt: (offset // 4) + 1.
		bytes at: i put: ((word bitShift: ((offset bitAnd: 3) * -8)) bitAnd: 255)].
	^bytes
!
readInto: buffer start: start count: count failure: failure using: operation
	| bytes done |
	((self valid: buffer start: start count: count) and: [buffer isReadOnlyObject not]) ifFalse: [^failure].
	bytes := ByteArray new: count.
	done := operation value: bytes.
	(done isInteger and: [done > 0]) ifTrue: [self copy: bytes to: buffer start: start count: done].
	^done
!
copy: bytes to: buffer start: start count: count
	buffer class isWords ifFalse: [
		1 to: count do: [:i | buffer basicAt: start + i - 1 put: (bytes at: i)].
		^self].
	1 to: count do: [:i |
		| offset shift index word mask |
		offset := start + i - 2.
		index := (offset // 4) + 1.
		shift := (offset bitAnd: 3) * 8.
		mask := (255 bitShift: shift) bitXor: 16rFFFFFFFF.
		word := (buffer basicAt: index) bitAnd: mask.
		buffer basicAt: index put: (word bitOr: ((bytes at: i) bitShift: shift))]
! !
