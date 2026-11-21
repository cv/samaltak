SHA512 subclass: #SHA384
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Crypto'!

SHA384 comment: 'I am SHA-384 (FIPS 180-4, 6.5): SHA-512 from another initial hash value, its digest truncated to 48 bytes. SHA384 hash: bytes; SHA384 new update: bytes; digest (CryptoHash).'!

!SHA384 class methodsFor: 'accessing'!
digestSize
	^48
! !

!SHA384 methodsFor: 'initialization'!
initialState
	^#(16rCBBB9D5D 16rC1059ED8 16r629A292A 16r367CD507 16r9159015A 16r3070DD17 16r152FECD8 16rF70E5939
		16r67332667 16rFFC00B31 16r8EB44A87 16r68581511 16rDB0C2E0D 16r64F98FA7 16r47B5481D 16rBEFA4FA4)
! !
