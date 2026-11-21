Object subclass: #HMAC
	instanceVariableNames: 'inner outer'
	classVariableNames: ''
	package: 'System-Crypto'!

HMAC comment: 'I am HMAC (RFC 2104) over a CryptoHash class: HMAC hash: SHA256 key: k message: m answers the tag (digestSize bytes); incremental, (HMAC hash: SHA256 key: k) update: m; update: more; digest, where digest leaves the receiver going on, as CryptoHash''s does. A key longer than the hash''s block is hashed first; a String key or message is its UTF-8. Compare tags with ByteArray>>constantTimeEquals:.'!

!HMAC class methodsFor: 'instance creation'!
hash: aHashClass key: key
	^self new setHash: aHashClass key: key
! !

!HMAC class methodsFor: 'hashing'!
hash: aHashClass key: key message: bytes
	^(self hash: aHashClass key: key) update: bytes; digest
! !

!HMAC methodsFor: 'initialization'!
setHash: aHashClass key: key
	| k pad |
	k := key isString ifTrue: [key utf8Encoded] ifFalse: [key].
	k size > aHashClass blockSize ifTrue: [k := aHashClass hash: k].
	pad := ByteArray new: aHashClass blockSize withAll: 16r36.
	1 to: k size do: [:i | pad at: i put: ((k at: i) bitXor: 16r36)].
	inner := aHashClass new update: pad.
	pad atAllPut: 16r5C.
	1 to: k size do: [:i | pad at: i put: ((k at: i) bitXor: 16r5C)].
	outer := aHashClass new update: pad
!
postCopy
	inner := inner copy
! !

!HMAC methodsFor: 'hashing'!
update: bytes
	inner update: bytes
!
update: bytes from: start to: stop
	inner update: bytes from: start to: stop
!
digest
	"The tag of the bytes given so far; the receiver is unchanged."
	^outer copy update: inner digest; digest
! !
