TestCase subclass: #NvGspFirmwareFileTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-NV'!

NvGspFirmwareFileTest comment: 'Tests NvGspFirmware on the driver''s real gsp_ga10x.bin (where driver 580.178.04 is installed: the Spark; make test-nv runs me, I do not run by default): its version, the GB10B image and signature sizes, the radix-3 counts of docs/nv-gsp.md, and a boot of the real 75 MB image against the fake GB10 (which reads it back through the radix-3 tables), with a synthetic FMC and boot loader. Touches no GPU.'!

!NvGspFirmwareFileTest class methodsFor: 'testing'!
runsByDefault
	^false
!
path
	^'/lib/firmware/nvidia/', NvGspFirmware driverVersion, '/gsp_ga10x.bin'
! !

!NvGspFirmwareFileTest methodsFor: 'tests'!
testTheDriversGspRm
	| boot f memory |
	(File exists: self class path) ifFalse: [^self error: 'no ', self class path, ': NvGspFirmwareFileTest needs driver ', NvGspFirmware driverVersion, ' installed'].
	boot := NvGspBootTest firmware.
	f := NvGspFirmware gspBin: (File readBytes: self class path) fmcImage: boot fmcImage hash: boot fmcHash signature: boot fmcSignature publicKey: boot fmcPublicKey
		bootImage: boot bootImage descriptor: boot bootDescriptor bytes.
	self assert: f gspVersion equals: '580.178.04'.
	self assert: f gspImage size equals: 16r4783000.
	self assert: f gspSignature size equals: 4096.
	self assert: (NvGsp radix3Counts: f gspImage size) equals: #(1 1 36 18307).
	self assert: f problems isEmpty.
	memory := NvFakeDmaMemory new.
	[| gpu |
	gpu := NvFakeGb10 memory: memory firmware: f.
	(NvGspBoot registers: gpu memory: memory firmware: f) sysmemHeapSize: 4096; boot.
	self assert: gpu rejections isEmpty description: gpu rejections printString]
		ensure: [memory release]
! !
