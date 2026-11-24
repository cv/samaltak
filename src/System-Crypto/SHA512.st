CryptoHash subclass: #SHA512
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Crypto'!

SHA512 comment: 'I am SHA-512 (FIPS 180-4, 6.4): a 64-byte digest of 128-byte blocks. SHA512 hash: bytes; SHA512 new update: bytes; update: more; digest (CryptoHash).'!

!SHA512 class methodsFor: 'accessing'!
algorithm
	^3
!
digestSize
	^64
!
blockSize
	^128
! !
