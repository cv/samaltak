NvTransport subclass: #NvFakeTransport
	instanceVariableNames: 'open log nextHandle objects mappings'
	classVariableNames: ''
	package: 'Tests-NV'!

NvFakeTransport comment: 'I am an NvTransport without a GPU, for NvTransportTest: I answer RM calls the way the kernel module does on the GB10 for what NvDevice open, NvMemory and close ask (handles from 16rCAFE0001, deviceInstance 0, a class list, GR info with SM version 16rA04), keep the objects alive in objects (handle -> {class. parent}), map memory to the CPU as Machine memory, and log every call as an Array: {#alloc. class. client. parent. handle}, {#control. command. client. object}, {#free. handle. client. parent}, {#mapMemory. handle}, {#mapUsermode. handle}, {#unmapCpu. size}, {#mapToGpu. handle. dma}, {#unmapFromGpu. handle. dma}.'!

!NvFakeTransport class methodsFor: 'answers'!
classList
	"The classes I report: a root, device, subdevice, VA space, memory, usermode, GPFIFO and compute class of the GB10's."
	^#(16r41 16r80 16r2080 16r90F1 16r3E 16r50A0 16rC761 16rC96F 16rCDC0 16rA06C 16r900E)
!
grInfo
	"GR info index -> value, as the GB10 reports it (48 SMs)."
	^Dictionary new at: NvRm grInfoSmVersion put: 16rA04; at: NvRm grInfoNumGpcs put: 3; at: NvRm grInfoNumTpcPerGpc put: 8; at: NvRm grInfoNumSmPerTpc put: 2; at: NvRm grInfoMaxWarpsPerSm put: 48; yourself
! !

!NvFakeTransport methodsFor: 'accessing'!
log
	^log
!
objects
	^objects
!
mappings
	^mappings
! !

!NvFakeTransport methodsFor: 'opening'!
open
	open := true.
	log := OrderedCollection new.
	objects := Dictionary new.
	mappings := Dictionary new.
	nextHandle := 16rCAFE0001
!
isOpen
	^open == true
!
attachGpu: index
	log add: {#attachGpu. index}.
	index = 0 ifFalse: [^self error: 'no NVIDIA GPU number ', index printString].
	^16r100
!
close
	log add: {#close}.
	open := false
! !

!NvFakeTransport methodsFor: 'resource manager'!
alloc: rmClass client: hClient parent: hParent params: anNvStructOrNil
	| handle |
	(hParent ~= 0 and: [(objects includesKey: hParent) not]) ifTrue: [^NvError signal: 'RM alloc of class 16r', (rmClass printString: 16) status: 16r19].
	handle := nextHandle.
	nextHandle := nextHandle + 1.
	objects at: handle put: {rmClass. hParent}.
	log add: {#alloc. rmClass. hClient. hParent. handle}.
	^handle
!
control: command client: hClient object: hObject params: anNvStruct
	log add: {#control. command. hClient. hObject}.
	command = NvRm cmdGpuGetIdInfoV2 ifTrue: [anNvStruct u32At: 8 put: 0].
	command = NvRm cmdDeviceGetClassList ifTrue: [
		(anNvStruct u32At: 0) = 0
			ifTrue: [anNvStruct u32At: 0 put: self class classList size]
			ifFalse: [self class classList doWithIndex: [:c :i | Machine uint32At: (anNvStruct u64At: 8) + (4 * (i - 1)) put: c]]].
	command = NvRm cmdGrGetInfo ifTrue: [| list |
		list := anNvStruct u64At: 8.
		0 to: (anNvStruct u32At: 0) - 1 do: [:i | | index |
			index := Machine uint32At: list + (8 * i).
			Machine uint32At: list + (8 * i) + 4 put: (self class grInfo at: index ifAbsent: [0])]].
	^anNvStruct
!
free: hObject client: hClient parent: hParent
	log add: {#free. hObject. hClient. hParent}.
	(objects includesKey: hObject) ifFalse: [^NvError signal: 'RM free' status: 16r19].
	"Freeing an object frees its descendants, as RM does."
	self freeTree: hObject
!
freeTree: hObject
	(objects keys select: [:h | ((objects at: h) at: 2) = hObject]) do: [:child | self freeTree: child].
	objects removeKey: hObject
! !

!NvFakeTransport methodsFor: 'mapping'!
mapMemory: hMemory client: hClient device: hDevice size: size
	^self map: hMemory size: size as: #mapMemory
!
mapUsermode: hUsermode client: hClient device: hDevice size: size
	^self map: hUsermode size: size as: #mapUsermode
!
map: handle size: size as: kind
	| address |
	log add: {kind. handle}.
	address := Machine allocate: size.
	mappings at: address put: size.
	^address
!
unmapCpu: address size: size
	log add: {#unmapCpu. size}.
	(mappings removeKey: address) = size ifFalse: [self error: 'unmapped with another size'].
	Machine free: address
!
mapToGpu: hMemory client: hClient device: hDevice dma: hDma size: size flags: flags
	log add: {#mapToGpu. hMemory. hDma}.
	^16r200000000 + ((hMemory bitAnd: 16rFFFF) bitShift: 20)
!
unmapFromGpu: hMemory client: hClient device: hDevice dma: hDma gpuAddress: gpuAddress
	log add: {#unmapFromGpu. hMemory. hDma}
! !
