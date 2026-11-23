FFIStubMemory subclass: #UefiFFIStubMemory
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

!UefiFFIStubMemory class methodsFor: 'declaring'!
targetOS
	^#uefi
!
isSimulated
	^false
! !

!UefiFFIStubMemory methodsFor: 'publication'!
canMapFFIStubs
	<export>
	^false
!
publishFFIStub: bytes size: size
	<export>
	^0
! !
