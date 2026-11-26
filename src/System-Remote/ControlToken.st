Object subclass: #ControlToken
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Remote'!

ControlToken comment: 'Control credentials are 32 ASCII hex digits, optionally four groups of eight separated by single hyphens. ASCII case is ignored; the verifier is SHA-256 of the 32 canonical lowercase ASCII bytes. Format does not establish randomness: provision from a CSPRNG.'!

!ControlToken class methodsFor: 'verifying'!
verifierFor: aString
	aString isString ifFalse: [^nil].
	^self verifierOfLength: aString size byteAt: [:i | (aString at: i) value]
!
verifierOfLength: size byteAt: atBlock
	| canonical j byte |
	(size = 32 or: [size = 35]) ifFalse: [^nil].
	canonical := ByteArray new: 32.
	j := 0.
	^[1 to: size do: [:i |
		byte := atBlock value: i.
		(size = 35 and: [i \\ 9 = 0])
			ifTrue: [byte = 45 ifFalse: [^nil]]
			ifFalse: [
				(byte between: 65 and: 70) ifTrue: [byte := byte + 32].
				((byte between: 48 and: 57) or: [byte between: 97 and: 102]) ifFalse: [^nil].
				j := j + 1.
				canonical at: j put: byte]].
	  ControlTokenHash digestOf: canonical] ensure: [canonical atAllPut: 0]
!
digest: candidate matches: verifier
	"Always compare all 32 bytes of well-formed digests."
	| difference |
	(candidate isNil or: [verifier isNil]) ifTrue: [^false].
	difference := 0.
	1 to: 32 do: [:i | difference := difference bitOr: ((candidate at: i) bitXor: (verifier at: i))].
	^difference = 0
! !

!ControlToken class methodsFor: 'provisioning'!
verifierFromFile: path
	"A hosted file contains one token, optionally terminated by LF or CRLF."
	| bytes count size |
	bytes := ByteArray new: 38. "Largest accepted file plus one byte to detect trailing data."
	^[count := self readFrom: path into: bytes.
	  count isNil ifTrue: [self error: 'cannot read --control-token-file'].
	  size := count.
	  (size > 0 and: [(bytes at: size) = 10]) ifTrue: [
		size := size - 1.
		(size > 0 and: [(bytes at: size) = 13]) ifTrue: [size := size - 1]].
	  self verifierOfLength: size byteAt: [:i | bytes at: i]] ensure: [bytes atAllPut: 0]
!
generate
	"Return a mutable display token, exactly 16 fresh platform CSPRNG bytes in hex. Caller must clear it."
	| bytes firmware token hex j byte |
	bytes := ByteArray new: 16.
	^[firmware := Firmware current.
	  (firmware isNil
		ifTrue: [(self readFrom: '/dev/urandom' into: bytes) = bytes size]
		ifFalse: [firmware readRandomInto: bytes]) ifFalse: [
			self error: 'platform entropy unavailable'].
	  hex := '0123456789abcdef'.
	  token := String new: 35.
	  j := 1.
	  1 to: bytes size do: [:i |
		byte := bytes at: i.
		token at: j put: (hex at: (byte bitShift: -4) + 1).
		token at: j + 1 put: (hex at: (byte bitAnd: 15) + 1).
		j := j + 2.
		(i < bytes size and: [i \\ 4 = 0]) ifTrue: [token at: j put: $-. j := j + 1]].
	  token] ensure: [bytes atAllPut: 0]
!
readFrom: path into: bytes
	"Read only as many bytes as the caller will use, without a FileStream read-ahead copy."
	| file used count |
	file := File primOpen: path mode: 0.
	file isNil ifTrue: [^nil].
	used := 0.
	^[[used < bytes size] whileTrue: [
		count := File primRead: file into: bytes startingAt: used + 1 count: bytes size - used.
		count isNil ifTrue: [^nil].
		count = 0 ifTrue: [^used].
		used := used + count].
	  used] ensure: [File primClose: file]
! !
