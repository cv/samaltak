Object subclass: #NvGspFirmware
	instanceVariableNames: 'gspImage gspSignature gspVersion fmcImage fmcHash fmcSignature fmcPublicKey bootImage bootDescriptor'
	classVariableNames: ''
	package: 'System-NV'!

NvGspFirmware comment: 'I am the firmware a GSP boot on GB10 takes (docs/nv-gsp.md 1): from gsp_ga10x.bin the GSP-RM image (its .fwimage section), its signature for GB10B (.fwsignature_gb10y) and version (.fwversion, which must be the driver''s, 580.178.04); from the driver''s bindata the GSP-FMC image with its SHA-384 hash, signature and public key (the production- or debug-signed archive, by the fuse), and the GSP-RM boot loader with its RM_RISCV_UCODE_DESC (an NvGspStruct). All ByteArrays. NvGspBoot puts them in DMA memory and describes them to SEC2 and the FMC.'!

!NvGspFirmware class methodsFor: 'instance creation'!
gspImage: image signature: signature version: aString fmcImage: fmc hash: hash signature: fmcSignature publicKey: key bootImage: boot descriptor: anRmRiscvUcodeDesc
	^self new setGspImage: image signature: signature version: aString fmcImage: fmc hash: hash signature: fmcSignature publicKey: key bootImage: boot descriptor: anRmRiscvUcodeDesc
! !

!NvGspFirmware class methodsFor: 'versions'!
driverVersion
	"The driver whose firmware and structures these are; gsp_ga10x.bin's .fwversion must be it (kernel_gsp.c 4731-4775)."
	^'580.178.04'
! !

!NvGspFirmware methodsFor: 'initialization'!
setGspImage: image signature: signature version: aString fmcImage: fmc hash: hash signature: fmcSig publicKey: key bootImage: boot descriptor: desc
	gspImage := image.
	gspSignature := signature.
	gspVersion := aString.
	fmcImage := fmc.
	fmcHash := hash.
	fmcSignature := fmcSig.
	fmcPublicKey := key.
	bootImage := boot.
	bootDescriptor := desc
! !

!NvGspFirmware methodsFor: 'accessing'!
gspImage
	^gspImage
!
gspSignature
	^gspSignature
!
gspVersion
	^gspVersion
!
fmcImage
	^fmcImage
!
fmcHash
	^fmcHash
!
fmcSignature
	^fmcSignature
!
fmcPublicKey
	^fmcPublicKey
!
bootImage
	^bootImage
!
bootDescriptor
	"The boot loader's RM_RISCV_UCODE_DESC (an NvGspStruct)."
	^bootDescriptor
! !

!NvGspFirmware methodsFor: 'checking'!
problems
	"Why NvGspBoot should not use me, one line each (none: fine)."
	| p |
	p := OrderedCollection new.
	gspVersion = self class driverVersion ifFalse: [p add: 'GSP-RM is version ', gspVersion printString, ', not ', self class driverVersion].
	gspImage isEmpty ifTrue: [p add: 'no GSP-RM image'].
	(gspSignature isEmpty or: [gspSignature size > 4096]) ifTrue: [p add: 'GSP-RM signature of ', gspSignature size printString, ' bytes'].
	fmcHash size = 48 ifFalse: [p add: 'GSP-FMC hash of ', fmcHash size printString, ' bytes, not 48'].
	fmcSignature size = 384 ifFalse: [p add: 'GSP-FMC signature of ', fmcSignature size printString, ' bytes, not 384'].
	fmcPublicKey size = 384 ifFalse: [p add: 'GSP-FMC public key of ', fmcPublicKey size printString, ' bytes, not 384'].
	bootImage isEmpty ifTrue: [p add: 'no boot loader'].
	^p
! !
