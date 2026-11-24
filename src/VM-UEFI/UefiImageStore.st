UefiModule subclass: #UefiImageStore
	instanceVariableNames: 'blockIo mediaId blockSize slotBytes current sequence buffer used position length writing target'
	classVariableNames: 'STORE_BUFFER STORE_DATA STORE_HEADER_BYTES'
	package: 'VM-UEFI'!

UefiImageStore comment: 'The image on a raw partition (or a whole disk) without a file system: the image path disk: (UefiLibC>>fopen:mode:) reads the newest of two slots and a snapshot writes the other, so a crash while writing leaves the last good image. Found at start among the firmware''s block devices by its superblock.

Layout, in bytes: 0 the superblock (SAMSTORE), 4096 and 8192 the headers of slots 0 and 1 (UefiSlotHeader: SAMSLOT1, sequence, length, check), 1 MB slot 0''s image, 1 MB + slotBytes slot 1''s, slotBytes half of what follows the first megabyte. A snapshot writes the image, flushes, then writes its slot''s header with the next sequence number and flushes again: a header is valid (magic and check) only once its image is complete. UefiImageDisk writes a store with the image in slot 0.'!

!UefiImageStore class methodsFor: 'declaring'!
declarations
	^#((blockIo 'EfiBlockIo *') (mediaId uint32_t) (blockSize uint64_t) (slotBytes uint64_t) (current int32_t -1) (sequence uint64_t)
		(buffer 'uint8_t *') (used uint64_t) (position uint64_t) (length uint64_t) (writing bool) (target int32_t))
!
initialize
	STORE_HEADER_BYTES := 4096.
	STORE_DATA := 16r100000.
	STORE_BUFFER := 16r100000
! !

!UefiImageStore class methodsFor: 'layout'!
slotCheckOf: sequence length: length
	"UefiSlotHeader's check, as checkOf:length: computes it (for UefiImageDisk)."
	^(((sequence * 16r9E3779B97F4A7C15) bitAnd: 16rFFFFFFFFFFFFFFFF) bitXor: ((length * 16rC2B2AE3D27D4EB4F) bitAnd: 16rFFFFFFFFFFFFFFFF)) bitXor: 16r53414D414C54414B
! !

!UefiImageStore methodsFor: 'finding'!
start
	"Find the block device whose first bytes are the superblock; read its slot headers."
	<function>
	| guid count handles bio pages |
	pages := self local: 'uint64_t'.
	(self efiFailed: (self efi: self boot allocatePages with: EFI_ALLOCATE_ANY_PAGES with: EFI_LOADER_DATA with: STORE_BUFFER >> 12 with: pages)) ifTrue: [^self].
	buffer := self cCoerce: pages value to: 'uint8_t *'.
	guid := self local: 'EfiGuid'.
	firmware guid: guid data1: 16r964E5B21 data2: 16r6459 data3: 16r11D2 data4: 16r8E3900A0C969723B.
	count := self local: 'uint64_t'.
	handles := self local: 'void **'.
	(self efiFailed: (self efi: self boot locateHandleBuffer with: 2 with: guid with: self null with: count with: handles)) ifTrue: [^self].
	bio := self local: 'EfiBlockIo *'.
	0 to: (count value asInt64) - 1 do: [:i |
		(blockIo isNull and: [(self efiFailed: (self efi: self boot handleProtocol with: (handles value at: i) with: guid with: bio)) not]) ifTrue: [
			(self isStore: bio value) ifTrue: [blockIo := bio value]]].
	self efi: self boot freePool with: handles value.
	blockIo isNull ifTrue: [^self].
	mediaId := blockIo media mediaId.
	blockSize := blockIo media blockSize asUInt64.
	slotBytes := ((((blockIo media lastBlock + 1) * blockSize) - STORE_DATA) quo: 2) bitClear: STORE_HEADER_BYTES - 1.
	0 to: 1 do: [:slot |
		(self read: STORE_HEADER_BYTES * (slot + 1) asUInt64 count: STORE_HEADER_BYTES into: buffer) ifTrue: [
			(self isValid: (self cCoerce: buffer to: 'UefiSlotHeader *')) ifTrue: [
				(current < 0 or: [(self cCoerce: buffer to: 'UefiSlotHeader *') sequence > sequence]) ifTrue: [
					current := slot asInt32.
					sequence := (self cCoerce: buffer to: 'UefiSlotHeader *') sequence.
					length := (self cCoerce: buffer to: 'UefiSlotHeader *') length]]]]
!
isStore: bio
	"Whether bio's medium starts with the superblock."
	<function>
	<var: #bio type: 'EfiBlockIo *'>
	<returns: 'bool'>
	| media |
	media := bio media.
	(media mediaPresent = 0 or: [media blockSize = 0 or: [(STORE_HEADER_BYTES rem: media blockSize) ~= 0]]) ifTrue: [^false].
	(self efiFailed: (self efi: bio readBlocks with: bio with: media mediaId with: 0 with: STORE_HEADER_BYTES with: buffer)) ifTrue: [^false].
	^(libc memcmp: buffer with: 'SAMSTORE' size: 8) = 0
!
isValid: header
	<function>
	<var: #header type: 'UefiSlotHeader *'>
	<returns: 'bool'>
	^(libc memcmp: header magic with: 'SAMSLOT1' size: 8) = 0
		and: [header check = (self checkOf: header sequence length: header length)
		and: [header length <= slotBytes]]
!
checkOf: aSequence length: aLength
	<function>
	<var: #aSequence type: 'uint64_t'>
	<var: #aLength type: 'uint64_t'>
	<returns: 'uint64_t'>
	^(((aSequence * 16r9E3779B97F4A7C15) asUInt64) bitXor: ((aLength * 16rC2B2AE3D27D4EB4F) asUInt64)) bitXor: 16r53414D414C54414B
!
isPresent
	"Whether there is a store with an image."
	<function>
	<returns: 'bool'>
	^current >= 0
! !

!UefiImageStore methodsFor: 'blocks'!
read: offset count: n into: p
	"n bytes at offset (both multiples of the block size) into p."
	<function>
	<var: #offset type: 'uint64_t'>
	<var: #n type: 'uint64_t'>
	<var: #p type: 'uint8_t *'>
	<returns: 'bool'>
	^(self efiFailed: (self efi: blockIo readBlocks with: blockIo with: mediaId with: (offset quo: blockSize) with: n with: p)) not
!
write: offset count: n from: p
	<function>
	<var: #offset type: 'uint64_t'>
	<var: #n type: 'uint64_t'>
	<var: #p type: 'uint8_t *'>
	<returns: 'bool'>
	^(self efiFailed: (self efi: blockIo writeBlocks with: blockIo with: mediaId with: (offset quo: blockSize) with: n with: p)) not
!
flush
	<function>
	<returns: 'bool'>
	^(self efiFailed: (self efi: blockIo flushBlocks with: blockIo)) not
!
slotStart: slot
	^STORE_DATA + (slot asUInt64 * slotBytes)
!
roundUp: n
	^(n + blockSize - 1) bitClear: blockSize - 1
! !

!UefiImageStore methodsFor: 'image'!
openForReading
	"Read the newest slot from the start; false if there is none."
	<function>
	<returns: 'bool'>
	current < 0 ifTrue: [^false].
	writing := false.
	position := 0.
	^true
!
openForWriting
	"Write the other slot."
	<function>
	<returns: 'bool'>
	blockIo isNull ifTrue: [^false].
	writing := true.
	target := current = 0 ifTrue: [1] ifFalse: [0].
	position := 0.
	used := 0.
	^true
!
seek: offset
	<function>
	<var: #offset type: 'uint64_t'>
	<returns: 'bool'>
	writing ifTrue: [^false].
	position := offset.
	^true
!
read: p count: n
	"Up to n bytes of the image from the position into p; answer how many."
	<function>
	<var: #p type: 'uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'uint64_t'>
	| want done offset start chunk skip take |
	want := position >= length ifTrue: [0] ifFalse: [(length - position) < n ifTrue: [length - position] ifFalse: [n]].
	done := 0 asUInt64.
	[done < want] whileTrue: [
		offset := (self slotStart: current) + position.
		start := offset bitClear: blockSize - 1.
		skip := offset - start.
		chunk := self roundUp: skip + (want - done).
		chunk > STORE_BUFFER ifTrue: [chunk := STORE_BUFFER].
		(self read: start count: chunk into: buffer) ifFalse: [^done].
		take := chunk - skip.
		take > (want - done) ifTrue: [take := want - done].
		libc memcpy: p + done from: buffer + skip size: take.
		done := done + take.
		position := position + take].
	^done
!
write: p count: n
	"Append n bytes from p; answer how many (0 once the slot is full or the device failed)."
	<function>
	<var: #p type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'uint64_t'>
	| done take |
	position + n > slotBytes ifTrue: [^0].
	done := 0 asUInt64.
	[done < n] whileTrue: [
		take := STORE_BUFFER - used.
		take > (n - done) ifTrue: [take := n - done].
		libc memcpy: buffer + used from: p + done size: take.
		used := used + take.
		done := done + take.
		position := position + take.
		used = STORE_BUFFER ifTrue: [(self writeBuffer) ifFalse: [^0]]].
	^n
!
writeBuffer
	"The buffer to the target slot, padded to whole blocks."
	<function>
	<returns: 'bool'>
	| ok |
	used = 0 ifTrue: [^true].
	libc memset: buffer + used value: 0 size: (self roundUp: used) - used.
	ok := self write: (self slotStart: target) + (position - used) count: (self roundUp: used) from: buffer.
	used := 0.
	^ok
!
close
	"Reading: nothing. Writing: the rest, then the slot's header with the next sequence number; answer whether the image is safely there."
	<function>
	<returns: 'bool'>
	| header ok |
	writing ifFalse: [^true].
	writing := false.
	ok := self writeBuffer and: [self flush].
	ok ifFalse: [^false].
	libc memset: buffer value: 0 size: STORE_HEADER_BYTES.
	header := self cCoerce: buffer to: 'UefiSlotHeader *'.
	libc memcpy: header magic from: 'SAMSLOT1' size: 8.
	header sequence: sequence + 1.
	header length: position.
	header check: (self checkOf: sequence + 1 length: position).
	ok := (self write: STORE_HEADER_BYTES * (target + 1) asUInt64 count: STORE_HEADER_BYTES from: buffer) and: [self flush].
	ok ifFalse: [^false].
	current := target.
	sequence := sequence + 1.
	length := position.
	^true
! !

VMStruct subclass: #UefiSlotHeader
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiSlotHeader comment: 'The header of an image slot of UefiImageStore.'!

!UefiSlotHeader class methodsFor: 'declaring'!
fields
	^#((magic 'char[8]') (sequence uint64_t) (length uint64_t) (check uint64_t))
! !

VMStruct subclass: #EfiBlockIo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiBlockIo comment: 'EFI_BLOCK_IO_PROTOCOL (UEFI 2.10, 13.9).'!

!EfiBlockIo class methodsFor: 'declaring'!
fields
	^#((revision uint64_t) (media 'EfiBlockIoMedia *') (reset 'void *') (readBlocks 'void *') (writeBlocks 'void *') (flushBlocks 'void *'))
! !

VMStruct subclass: #EfiBlockIoMedia
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiBlockIoMedia comment: 'EFI_BLOCK_IO_MEDIA, up to LastBlock.'!

!EfiBlockIoMedia class methodsFor: 'declaring'!
fields
	^#((mediaId uint32_t) (removableMedia uint8_t) (mediaPresent uint8_t) (logicalPartition uint8_t) (readOnly uint8_t)
		(writeCaching uint8_t) (blockSize uint32_t) (ioAlign uint32_t) (lastBlock uint64_t))
! !
