Object subclass: #NvGspFirmware
	instanceVariableNames: 'gspImage gspSignature gspVersion fmcImage fmcHash fmcSignature fmcPublicKey bootImage bootDescriptor'
	classVariableNames: ''
	package: 'System-NV'!

NvGspFirmware comment: 'I am the firmware a GSP boot on GB10 takes (docs/nv-gsp.md 1): from gsp_ga10x.bin the GSP-RM image (its .fwimage section), its signature for GB10B (.fwsignature_gb10y) and version (.fwversion, which must be the driver''s, 580.178.04); from the driver''s bindata the GSP-FMC image with its SHA-384 hash, signature and public key (the production- or debug-signed archive, by the fuse), and the GSP-RM boot loader with its RM_RISCV_UCODE_DESC (an NvGspStruct). All ByteArrays. NvGspBoot puts them in DMA memory and describes them to SEC2 and the FMC.'!

!NvGspFirmware class methodsFor: 'instance creation'!
gspImage: image signature: signature version: aString fmcImage: fmc hash: hash signature: fmcSignature publicKey: key bootImage: boot descriptor: anRmRiscvUcodeDesc
	^self new setGspImage: image signature: signature version: aString fmcImage: fmc hash: hash signature: fmcSignature publicKey: key bootImage: boot descriptor: anRmRiscvUcodeDesc
! !

!NvGspFirmware class methodsFor: 'loading'!
signatureSection
	"GB10B's signature section of gsp_ga10x.bin: the prefix (not confidential computing, kgspGetSignatureSectionNamePrefix_GB100) and the chip family's name (_kgspGetSectionNameForPrefix, kernel_gsp.c 4796-4840; nv-firmware.h 60)."
	^'.fwsignature_gb10y'
!
fromDirectory: aPath debug: aBoolean
	"The firmware tools/nv-gsp-firmware.sh put in aPath: gsp_ga10x.bin and gb10b/, the debug- or production-signed FMC and boot loader (as the fuse says: NvProbe reads it)."
	| kind fmc boot |
	kind := aBoolean ifTrue: ['debug'] ifFalse: ['prod'].
	fmc := [:ext | File readBytes: aPath, '/gb10b/fmc-', kind, '.', ext].
	boot := [:ext | File readBytes: aPath, '/gb10b/boot-', kind, '.', ext].
	^self gspBin: (File readBytes: aPath, '/gsp_ga10x.bin')
		fmcImage: (fmc value: 'image') hash: (fmc value: 'hash') signature: (fmc value: 'sig') publicKey: (fmc value: 'pkey')
		bootImage: (boot value: 'image') descriptor: (boot value: 'desc')
!
gspBin: gspBinBytes fmcImage: fmc hash: hash signature: signature publicKey: key bootImage: boot descriptor: descBytes
	"From gsp_ga10x.bin's bytes (its .fwimage, .fwversion and GB10B signature sections) and the bindata files' bytes (the descriptor an RM_RISCV_UCODE_DESC's 84)."
	| elf image version gspSignature desc |
	elf := NvElf on: gspBinBytes.
	image := elf sectionNamed: '.fwimage'.
	image isNil ifTrue: [^self error: 'gsp_ga10x.bin: no .fwimage section'].
	version := (elf sectionNamed: '.fwversion') ifNil: [^self error: 'gsp_ga10x.bin: no .fwversion section'].
	version := (version copyUpTo: 0) asString.
	gspSignature := (elf sectionNamed: self signatureSection) ifNil: [^self error: 'gsp_ga10x.bin: no ', self signatureSection, ' section'].
	desc := NvGsp struct: 'RM_RISCV_UCODE_DESC'.
	descBytes size = desc size ifFalse: [^self error: 'boot loader descriptor of ', descBytes size printString, ' bytes, not ', desc size printString].
	desc bytesAt: 0 put: descBytes.
	^self gspImage: image signature: gspSignature version: version fmcImage: fmc hash: hash signature: signature publicKey: key bootImage: boot descriptor: desc
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
