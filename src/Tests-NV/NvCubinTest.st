TestCase subclass: #NvCubinTest
	instanceVariableNames: 'cubin'
	classVariableNames: ''
	package: 'Tests-NV'!

NvCubinTest comment: 'Tests NvCubin and NvKernel on the checked-in test kernels (NvTestKernels, tests/nv/test-kernels.cu compiled for sm_121): the values match cuobjdump -elf and the SASS (parameters at 16r380 in constant bank 0). Needs no GPU.'!

!NvCubinTest methodsFor: 'running'!
setUp
	cubin := NvTestKernels cubin
! !

!NvCubinTest methodsFor: 'tests'!
testKernels
	self assert: cubin kernelNames equals: #('copy16' 'dims' 'fill' 'lookup' 'reverse256' 'vadd').
	self assert: cubin smVersion equals: 121.
	self should: [cubin kernelNamed: 'nothing'] raise: Error
!
testVadd
	| k |
	k := cubin kernelNamed: 'vadd'.
	self assert: k name equals: 'vadd'.
	self assert: k smVersion equals: 121.
	self assert: k registerCount equals: 12.
	self assert: k parameters equals: #(#(0 0 8) #(1 8 8) #(2 16 8) #(3 24 4)).
	self assert: k parameterOffset equals: 16r380.
	self assert: k parameterSize equals: 16r1C.
	self assert: k code size equals: 16r200.
	self assert: (k constantBanks at: 0) size equals: 16r39C.
	self assert: k constantBanks keys asSortedCollection asArray equals: #(0 3).
	self assert: k sharedSize equals: 0.
	self assert: k frameSize equals: 0.
	self assert: k maxThreads isNil.
	self assert: k relocations isEmpty.
	self assert: k exitOffsets equals: #(16r70 16r130)
!
testFill
	| k |
	k := cubin kernelNamed: 'fill'.
	self assert: k registerCount equals: 10.
	self assert: k parameters equals: #(#(0 0 8) #(1 8 4) #(2 12 4)).
	self assert: k parameterSize equals: 16r10.
	self assert: k code size equals: 16r180
!
testLaunchBoundsAndShared
	| copy reverse |
	copy := cubin kernelNamed: 'copy16'.
	self assert: copy maxThreads equals: 256.
	self assert: copy registerCount equals: 14.
	self assert: copy parameters equals: #(#(0 0 8) #(1 8 8) #(2 16 4)).
	reverse := cubin kernelNamed: 'reverse256'.
	self assert: reverse sharedSize equals: 16r800.
	self assert: reverse maxThreads equals: 256.
	self assert: reverse relocations isEmpty
!
testConstantBank
	"lookup reads its __constant__ table from bank 3."
	| k |
	k := cubin kernelNamed: 'lookup'.
	self assert: (k constantBanks keys asSortedCollection asArray) equals: #(0 3).
	self assert: ((k constantBanks at: 3) uint32At: 1) equals: 16r11111111.
	self assert: ((k constantBanks at: 3) uint32At: 13) equals: 16r44444444
!
testInfoAttributes
	| attributes |
	attributes := OrderedCollection new.
	cubin info: '.nv.info.vadd' do: [:attr :value | attributes add: attr].
	self assert: (attributes includes: 16r17).
	self assert: (attributes includes: 16r0A).
	self assert: (attributes select: [:a | a = 16r17]) size equals: 4
!
testParameterBytes
	| k b |
	k := cubin kernelNamed: 'vadd'.
	b := k parameterBytes: #(16r100000000 16r2000 16r123456789A 5).
	self assert: b size equals: 16r1C.
	self assert: (b uint32At: 1) equals: 0.
	self assert: (b uint32At: 5) equals: 1.
	self assert: (b uint32At: 9) equals: 16r2000.
	self assert: (b uint32At: 17) equals: 16r3456789A.
	self assert: (b uint32At: 21) equals: 16r12.
	self assert: (b uint32At: 25) equals: 5.
	self should: [k parameterBytes: #(1 2 3)] raise: Error.
	self assert: (((cubin kernelNamed: 'fill') parameterBytes: (Array with: 0 with: 1.5 with: 2)) float32At: 9) equals: 1.5
!
testAKernelsOwnConstantBank
	"raster_tiles' .nv.constant2.raster_tiles (a switch's jump table) is its bank 2; no other raster kernel has one."
	| raster |
	raster := NvCubin on: NvRasterKernels cubin.
	self assert: ((raster kernelNamed: 'raster_tiles') constantBanks at: 2) equals: ((NvRasterKernels kernel: 'raster_tiles') at: #constantBank2).
	self assert: ((raster kernelNamed: 'raster_prims') constantBanks keys asArray) equals: #(0)
!
testNotACubin
	self should: [NvCubin on: (ByteArray new: 100)] raise: Error.
	self should: [NvCubin on: #[1 2 3]] raise: Error
! !
