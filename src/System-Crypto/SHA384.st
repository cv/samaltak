CryptoHash subclass: #SHA384
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Crypto'!

SHA384 comment: 'I am SHA-384 (FIPS 180-4, 6.5): SHA-512 from another initial hash value, its digest truncated to 48 bytes. SHA384 hash: bytes; SHA384 new update: bytes; digest (CryptoHash).'!

!SHA384 class methodsFor: 'accessing'!
algorithm
	^2
!
digestSize
	^48
!
blockSize
	^128
! !
