TestCase subclass: #VfioLayoutTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Devices'!

VfioLayoutTest comment: 'Tests VfioPciDevice''s tables of the VFIO structures and numbers against the C compiler: VfioLayouts holds sizeof, every offsetof and member size, and the constants from linux/vfio.h (tools/vfio-layouts.sh); each must be VfioPciDevice''s, byte for byte. Needs no VFIO.'!

!VfioLayoutTest methodsFor: 'tests'!
testEveryStructureAsTheCompilerLaysItOut
	self assert: VfioPciDevice structs equals: VfioLayouts layouts
!
testConstantsAsTheHeaderDefinesThem
	VfioLayouts constants do: [:pair |
		self assert: (VfioPciDevice constant: pair first) = pair last description: pair first].
	self assert: (VfioLayouts constants collect: [:pair | pair first]) asSet equals: VfioPciDevice constants keys asSet
!
testRequestNames
	self assert: (VfioPciDevice requestName: 16r3B71) equals: 'VFIO_IOMMU_MAP_DMA'.
	self assert: (VfioPciDevice requestName: 3) isNil
! !
