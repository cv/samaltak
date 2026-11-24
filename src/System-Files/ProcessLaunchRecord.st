Object subclass: #ProcessLaunchRecord
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Files'!

ProcessLaunchRecord comment: 'Encode counted OS text for hosted process downcalls. Vectors start with a LE32 count; fields start with a LE32 byte length. PTY records append environment and directory after argv. All-ones means inherit in either optional field. Payload bytes are unpadded and embedded NUL is rejected.'!

!ProcessLaunchRecord class methodsFor: 'encoding'!
arguments: argv
	| out |
	out := WriteStream on: (ByteArray new: 64).
	(self writeVector: argv optional: false on: out) ifFalse: [^nil].
	^out contents
!
arguments: argv environment: env directory: cwd
	| out |
	out := WriteStream on: (ByteArray new: 64).
	(self writeVector: argv optional: false on: out) ifFalse: [^nil].
	(self writeVector: env optional: true on: out) ifFalse: [^nil].
	(self writeText: cwd optional: true on: out) ifFalse: [^nil].
	^out contents
! !

!ProcessLaunchRecord class methodsFor: 'private'!
writeVector: vector optional: optional on: out
	| count |
	(optional and: [vector isNil]) ifTrue: [
		self writeUint32: 16rFFFFFFFF on: out.
		^true].
	vector class instSpec = VMConstants fVar ifFalse: [^false].
	count := vector basicSize.
	(count = 16rFFFFFFFF or: [count = 0 and: [optional not]]) ifTrue: [^false].
	self writeUint32: count on: out.
	1 to: count do: [:i |
		(self writeText: (vector basicAt: i) optional: false on: out) ifFalse: [^false]].
	^true
!
writeText: field optional: optional on: out
	| bytes |
	(optional and: [field isNil]) ifTrue: [
		self writeUint32: 16rFFFFFFFF on: out.
		^true].
	bytes := PlatformFFI osTextBytes: field.
	(bytes isNil or: [bytes size >= 16rFFFFFFFF]) ifTrue: [^false].
	self writeUint32: bytes size on: out.
	out nextPutAll: bytes.
	^true
!
writeUint32: value on: out
	0 to: 24 by: 8 do: [:shift |
		out nextPut: ((value bitShift: shift negated) bitAnd: 255)]
! !
