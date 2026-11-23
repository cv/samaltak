Object subclass: #NvGmmu
	instanceVariableNames: 'memory root tables'
	classVariableNames: ''
	package: 'System-NV'!

NvGmmu comment: 'I am the GPU page tables of one VA space as the client RM builds them (docs/nv-gsp.md 3.3, 3.4, 14): GB10B''s GMMU format, Hopper''s version 3 with five levels for a 57-bit VA (kern_gmmu_fmt_gb10x.c 24-61; kern_gmmu_fmt_gh10x.c 59-120): PD4 (bit 56, 2 entries), PD3 (55:47), PD2 (46:38), PD1 (37:29), PD0 (28:21, dual 16-byte entries: big pages, then small), then 4 KB page tables (20:12). Every table is a zeroed 4 KB NvDmaBuffer of memory (an NvDmaMemory), made when a mapping first needs it; the entries are NvGsp pde:, dualPdeSmall: and pte:. map:at:size: maps device memory (its DMA address) at a GPU VA in 4 KB pages, unmap:size: clears them, translate: walks the tables as the GMMU would (for tests and the Debugger). root and rootEntries are what NV0080_CTRL_CMD_DMA_SET_PAGE_DIRECTORY tells GSP-RM.

Verified only against NvFakeGsp''s own walk and the bit positions of dev_mmu.h (NvGspLayouts): what the GB10''s GMMU does with them waits for the dedicated Spark. Not done: big (64 KB) and huge pages, the PDEs GSP-RM keeps for itself (NV90F1_CTRL_CMD_VASPACE_COPY_SERVER_RESERVED_PDES), TLB invalidation after unmapping.'!

!NvGmmu class methodsFor: 'instance creation'!
on: anNvDmaMemory
	^self new setMemory: anNvDmaMemory
! !

!NvGmmu class methodsFor: 'format'!
levels
	"{name. low bit of its index. index bits. entry size} from the root down (PD4 to the 4 KB page table)."
	^#(#('PD4' 56 1 8) #('PD3' 47 9 8) #('PD2' 38 9 8) #('PD1' 29 9 8) #('PD0' 21 8 16) #('PT' 12 9 8))
!
vaBits
	^57
! !

!NvGmmu methodsFor: 'initialization'!
setMemory: anNvDmaMemory
	memory := anNvDmaMemory.
	tables := Dictionary new.
	root := self newTable
!
newTable
	| t |
	t := memory allocate: 4096.
	tables at: t deviceAddress put: t.
	^t
! !

!NvGmmu methodsFor: 'accessing'!
root
	"The PD4 table (an NvDmaBuffer)."
	^root
!
rootEntries
	^2
!
tableCount
	^tables size
! !

!NvGmmu methodsFor: 'mapping'!
index: va level: aLevel
	^(va bitShift: (aLevel at: 2) negated) bitAnd: (1 bitShift: (aLevel at: 3)) - 1
!
pageTableFor: va
	"The 4 KB page table holding va's PTE, made (with the directories above it) if missing."
	| t |
	(va >= 0 and: [va < (1 bitShift: self class vaBits)]) ifFalse: [^self error: 'GMMU: VA 16r', (va printString: 16), ' outside 57 bits'].
	t := root.
	(self class levels first: 4) do: [:level | | slot entry |
		slot := 8 * (self index: va level: level).
		entry := t u64At: slot.
		entry = 0
			ifTrue: [| child | child := self newTable. t u64At: slot put: (NvGsp pde: child deviceAddress). t := child]
			ifFalse: [t := tables at: (NvGsp field: 'NV_MMU_VER3_PDE_ADDRESS' of: entry) * 4096]].
	^self pageTableIn: t at: 16 * (self index: va level: (self class levels at: 5))
!
pageTableIn: pd0 at: slot
	| high |
	high := pd0 u64At: slot + 8.
	high = 0 ifTrue: [| pt words |
		pt := self newTable.
		words := NvGsp dualPdeSmall: pt deviceAddress.
		pd0 u64At: slot put: words first; u64At: slot + 8 put: words last.
		^pt].
	^tables at: (NvGsp field: 'NV_MMU_VER3_DUAL_PDE_ADDRESS_SMALL' of: (high bitShift: 64)) * 4096
!
map: aDeviceAddress at: va size: bytes
	"Map bytes (whole 4 KB pages) of device memory from aDeviceAddress at the GPU VA va."
	((va bitAnd: 16rFFF) = 0 and: [(aDeviceAddress bitAnd: 16rFFF) = 0]) ifFalse: [^self error: 'GMMU: mappings are 4 KB aligned'].
	0 to: bytes - 1 by: 4096 do: [:offset | | pt |
		pt := self pageTableFor: va + offset.
		pt u64At: 8 * (self index: va + offset level: self class levels last) put: (NvGsp pte: aDeviceAddress + offset)]
!
unmap: va size: bytes
	0 to: bytes - 1 by: 4096 do: [:offset |
		(self pteSlotOf: va + offset) ifNotNil: [:pair | pair first u64At: pair last put: 0]]
!
pteSlotOf: va
	"{page table. byte offset of va''s PTE}, or nil if no table holds it."
	| t pd0 slot high |
	t := root.
	(self class levels first: 4) do: [:level | | entry |
		entry := t u64At: 8 * (self index: va level: level).
		entry = 0 ifTrue: [^nil].
		t := tables at: (NvGsp field: 'NV_MMU_VER3_PDE_ADDRESS' of: entry) * 4096 ifAbsent: [^nil]].
	pd0 := t.
	slot := 16 * (self index: va level: (self class levels at: 5)).
	high := pd0 u64At: slot + 8.
	high = 0 ifTrue: [^nil].
	t := tables at: (NvGsp field: 'NV_MMU_VER3_DUAL_PDE_ADDRESS_SMALL' of: (high bitShift: 64)) * 4096 ifAbsent: [^nil].
	^Array with: t with: 8 * (self index: va level: self class levels last)
!
translate: va
	"The device address va maps to, or nil."
	| pair pte |
	pair := self pteSlotOf: va.
	pair isNil ifTrue: [^nil].
	pte := pair first u64At: pair last.
	(NvGsp field: 'NV_MMU_VER3_PTE_VALID' of: pte) = 1 ifFalse: [^nil].
	^((NvGsp field: 'NV_MMU_VER3_PTE_ADDRESS' of: pte) * 4096) + (va bitAnd: 16rFFF)
! !
