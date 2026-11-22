Object subclass: #NvQmd
	instanceVariableNames: 'bytes'
	classVariableNames: 'Fields'
	package: 'System-NV'!

NvQmd comment: 'I am a Queue Meta Data (QMD) block, version 5, which the Blackwell compute classes (BLACKWELL_COMPUTE_A/B) launch a grid from: 384 bytes of bit fields (program address, grid and block size, registers, shared memory, constant buffers, semaphore releases). Fields have NVIDIA''s names (NVCEC0_QMDV05_00_<NAME>) in lower case, indexed ones with the index appended (constant_buffer_valid_0); fieldTable lists them with their bit ranges.

	(NvQmd new) at: ''grid_width'' put: 4; at: ''grid_width''   "4"

NvCompute fills me from an NvKernel and a launch; bytes go into GPU-visible memory at a 256-byte aligned address.'!

!NvQmd methodsFor: 'initialization'!
initialize
	bytes := ByteArray new: 384
! !

!NvQmd methodsFor: 'accessing'!
bytes
	^bytes
!
at: name
	| f |
	f := self class field: name.
	^self bitsFrom: (f at: 2) to: (f at: 1)
!
at: name put: anInteger
	| f |
	f := self class field: name.
	self bitsFrom: (f at: 2) to: (f at: 1) put: anInteger.
	^anInteger
!
at: lowerName and: upperName put: anInteger
	"A value split into a lower 32-bit field and an upper one (addresses)."
	self at: lowerName put: (anInteger bitAnd: 16rFFFFFFFF).
	self at: upperName put: (anInteger bitShift: -32)
!
bitsFrom: lo to: hi
	| v |
	v := 0.
	hi to: lo by: -1 do: [:bit |
		v := (v bitShift: 1) bitOr: (((bytes at: bit // 8 + 1) bitShift: 0 - (bit \\ 8)) bitAnd: 1)].
	^v
!
bitsFrom: lo to: hi put: anInteger
	(anInteger < 0 or: [anInteger >= (1 bitShift: hi - lo + 1)])
		ifTrue: [^self error: 'QMD field of ', (hi - lo + 1) printString, ' bits cannot hold ', anInteger printString].
	lo to: hi do: [:bit | | i mask |
		i := bit // 8 + 1.
		mask := 1 bitShift: bit \\ 8.
		bytes at: i put: (((anInteger bitShift: lo - bit) bitAnd: 1) = 1
			ifTrue: [(bytes at: i) bitOr: mask]
			ifFalse: [(bytes at: i) bitAnd: 255 - mask])]
! !

!NvQmd methodsFor: 'launch'!
programAddress: gpuAddress
	self at: 'program_address_lower_shifted4' and: 'program_address_upper_shifted4' put: (gpuAddress bitShift: -4).
	self at: 'program_prefetch_addr_lower_shifted' and: 'program_prefetch_addr_upper_shifted' put: (gpuAddress bitShift: -8)
!
constantBuffer: index address: gpuAddress size: size
	"Bind constant bank index to size bytes at gpuAddress (64-byte aligned)."
	self at: 'constant_buffer_addr_lower_shifted6_', index printString
		and: 'constant_buffer_addr_upper_shifted6_', index printString
		put: (gpuAddress bitShift: -6).
	self at: 'constant_buffer_size_shifted4_', index printString put: size.
	self at: 'constant_buffer_valid_', index printString put: 1
!
grid: aTriple block: anotherTriple
	self at: 'grid_width' put: (aTriple at: 1); at: 'grid_height' put: (aTriple at: 2); at: 'grid_depth' put: (aTriple at: 3).
	self at: 'cta_thread_dimension0' put: (anotherTriple at: 1);
		at: 'cta_thread_dimension1' put: (anotherTriple at: 2);
		at: 'cta_thread_dimension2' put: (anotherTriple at: 3)
!
release: index address: gpuAddress payload: value
	"When the grid is done, write value (64 bits) to gpuAddress; index 0 or 1."
	self at: 'release_semaphore', index printString, '_addr_lower' and: 'release_semaphore', index printString, '_addr_upper' put: gpuAddress.
	self at: 'release_semaphore', index printString, '_payload_lower' and: 'release_semaphore', index printString, '_payload_upper' put: value.
	self at: 'release', index printString, '_enable' put: 1.
	self at: 'release_structure_size_', index printString put: 2
! !

!NvQmd class methodsFor: 'fields'!
fieldTable
	"Name, highest bit, lowest bit (from NVIDIA''s clcec0qmd.h as tinygrad''s autogen has it)."
	^#(
		'qmd_group_id' 149 144
		'qmd_type' 153 151
		'sass_version' 455 448
		'api_visible_call_limit' 456 456
		'sampler_index' 457 457
		'qmd_minor_version' 467 464
		'qmd_major_version' 471 468
		'invalidate_texture_header_cache' 472 472
		'invalidate_texture_sampler_cache' 473 473
		'invalidate_texture_data_cache' 474 474
		'invalidate_shader_data_cache' 475 475
		'invalidate_instruction_cache' 476 476
		'invalidate_shader_constant_cache' 477 477
		'release_semaphore0_addr_lower' 511 480
		'release_semaphore0_addr_upper' 536 512
		'release_semaphore0_payload_lower' 575 544
		'release_semaphore0_payload_upper' 607 576
		'cwd_membar_type' 625 624
		'release_semaphore1_addr_lower' 799 768
		'release_semaphore1_addr_upper' 824 800
		'release_semaphore1_payload_lower' 863 832
		'release_semaphore1_payload_upper' 895 864
		'dependent_qmd0_enable' 336 336
		'dependent_qmd0_action' 339 337
		'dependent_qmd0_prefetch' 340 340
		'dependent_qmd0_pointer' 415 384
		'program_address_lower_shifted4' 1055 1024
		'program_address_upper_shifted4' 1076 1056
		'program_prefetch_size' 1085 1077
		'cta_thread_dimension0' 1103 1088
		'cta_thread_dimension1' 1119 1104
		'cta_thread_dimension2' 1127 1120
		'register_count' 1136 1128
		'barrier_count' 1141 1137
		'shared_memory_size_shifted7' 1162 1152
		'min_sm_config_shared_mem_size' 1168 1163
		'max_sm_config_shared_mem_size' 1174 1169
		'target_sm_config_shared_mem_size' 1180 1175
		'shader_local_memory_low_size_shifted4' 1199 1184
		'shader_local_memory_high_size_shifted4' 1215 1200
		'grid_width' 1279 1248
		'grid_height' 1295 1280
		'grid_depth' 1327 1312
		'program_prefetch_addr_lower_shifted' 1919 1888
		'program_prefetch_addr_upper_shifted' 1936 1920
		'release0_enable' 288 288
		'release_structure_size_0' 290 289
		'release_membar_type_0' 291 291
		'release_payload64b_0' 300 300
		'release1_enable' 304 304
		'release_structure_size_1' 306 305
		'release_membar_type_1' 307 307
		'release_payload64b_1' 316 316
		'constant_buffer_addr_lower_shifted6_0' 1375 1344
		'constant_buffer_addr_upper_shifted6_0' 1394 1376
		'constant_buffer_size_shifted4_0' 1407 1395
		'constant_buffer_valid_0' 1856 1856
		'constant_buffer_invalidate_0' 1859 1859
		'constant_buffer_addr_lower_shifted6_1' 1439 1408
		'constant_buffer_addr_upper_shifted6_1' 1458 1440
		'constant_buffer_size_shifted4_1' 1471 1459
		'constant_buffer_valid_1' 1860 1860
		'constant_buffer_invalidate_1' 1863 1863
		'constant_buffer_addr_lower_shifted6_2' 1503 1472
		'constant_buffer_addr_upper_shifted6_2' 1522 1504
		'constant_buffer_size_shifted4_2' 1535 1523
		'constant_buffer_valid_2' 1864 1864
		'constant_buffer_invalidate_2' 1867 1867
		'constant_buffer_addr_lower_shifted6_3' 1567 1536
		'constant_buffer_addr_upper_shifted6_3' 1586 1568
		'constant_buffer_size_shifted4_3' 1599 1587
		'constant_buffer_valid_3' 1868 1868
		'constant_buffer_invalidate_3' 1871 1871
		'constant_buffer_addr_lower_shifted6_4' 1631 1600
		'constant_buffer_addr_upper_shifted6_4' 1650 1632
		'constant_buffer_size_shifted4_4' 1663 1651
		'constant_buffer_valid_4' 1872 1872
		'constant_buffer_invalidate_4' 1875 1875
		'constant_buffer_addr_lower_shifted6_5' 1695 1664
		'constant_buffer_addr_upper_shifted6_5' 1714 1696
		'constant_buffer_size_shifted4_5' 1727 1715
		'constant_buffer_valid_5' 1876 1876
		'constant_buffer_invalidate_5' 1879 1879
		'constant_buffer_addr_lower_shifted6_6' 1759 1728
		'constant_buffer_addr_upper_shifted6_6' 1778 1760
		'constant_buffer_size_shifted4_6' 1791 1779
		'constant_buffer_valid_6' 1880 1880
		'constant_buffer_invalidate_6' 1883 1883
		'constant_buffer_addr_lower_shifted6_7' 1823 1792
		'constant_buffer_addr_upper_shifted6_7' 1842 1824
		'constant_buffer_size_shifted4_7' 1855 1843
		'constant_buffer_valid_7' 1884 1884
		'constant_buffer_invalidate_7' 1887 1887)
!
field: name
	"(hi lo) of the field name; error if there is none."
	Fields isNil ifTrue: [
		| t |
		t := self fieldTable.
		Fields := Dictionary new.
		1 to: t size by: 3 do: [:i | Fields at: (t at: i) put: (Array with: (t at: i + 1) with: (t at: i + 2))]].
	^Fields at: name ifAbsent: [self error: 'no QMD field ', name]
! !
