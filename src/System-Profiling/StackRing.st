Object subclass: #StackRing
	instanceVariableNames: 'data dataSize head tail count first lastTime depth processes processUses frameKeys framePcs frameHash frameMask frameCount lostFrames frameMarks frameFree frameScan frameReclaimAt frameEpoch slotProcesses slotBuffers slotIds lastFlags decodeKeys decodeStacks decodedFrames decodeEpoch epoch stackMemo'
	classVariableNames: ''
	package: 'System-Profiling'!

StackRing comment: 'I am the profiler''s sample store: a ring of variable-length records in one preallocated ByteArray, each a complete sample with its stack stored inline, so recording never allocates and nothing is ever evicted but the oldest records. A record (little-endian, at any byte offset):

	byte 0     flags: 1 idle, 2 truncated stack, 4 process unknown, 8 innermost frame just activated, 16 allocation sample
	byte 1     n, the number of frames (at most depth)
	bytes 2-3  process slot (0: none)
	bytes 4-7  low 32 bits of the microsecond clock
	allocation samples only: bytes 8-11 the class (a frame id), 12-15 the byte size
	then n frame ids of 4 bytes, outermost first

Frame ids index a frame table (method or block: CompiledMethod and the block''s startpc, 0 for the method; for allocation samples the class), interned with open addressing. When the table is full, the ids that no record in the ring uses are reclaimed for new frames (frameEpoch counts how often: an id may mean another frame afterwards). Process slots index a table of Processes, reused when no record in the ring references them any more. When a record does not fit before the end of the buffer a byte 255 marks the wrap and the record starts at offset 0; the oldest records are dropped as the head runs into them.

count is the number of records ever written; record serial k is in the ring while k >= first. The single writer is the timer process (priority 80, never interrupted). Readers walk the records from the oldest one (or continue after the last one they read) and check after reading a record''s header and again after decoding it that the record was not dropped meanwhile (a dropped record''s bytes are overwritten, and its frame ids may be reclaimed); they intern decoded stacks in a trie (decodeKeys / decodeStacks) so that equal stacks decode to the same Array, and look whole stacks up first in stackMemo, keyed by the record''s frame id bytes as a String (whose hash and comparison are primitives), so a deep stack seen before costs one lookup. What they keep of decoded stacks they forget when frame ids were reclaimed and when they decoded a dropped record.'!

!StackRing methodsFor: 'initialization'!
setBytes: totalBytes depth: maxDepth
	"Use totalBytes for everything (tables included): the data ring gets what the tables leave."
	| slots fixed |
	depth := maxDepth.
	processes := Array new: 512.
	processUses := Array new: 512.
	frameKeys := Array new: 8192.
	framePcs := ByteArray new: 8192 * 2.
	slots := 16384.
	frameHash := ByteArray new: slots * 2.
	frameMarks := ByteArray new: frameKeys size.
	frameMask := slots - 1.
	slotProcesses := Array new: 16.
	slotBuffers := (1 to: 16) collect: [:i | Array new: maxDepth * 2 + 1].
	slotIds := (1 to: 16) collect: [:i | Array new: maxDepth].
	fixed := self tableBytes + 16.
	dataSize := totalBytes - fixed max: 1024.
	dataSize := dataSize // 8 * 8.
	data := ByteArray new: dataSize.
	self reset
!
reset
	"Forget all records and frames (the buffers are kept)."
	head := tail := 0.
	count := first := 0.
	lastTime := 0.
	lostFrames := 0.
	frameCount := 0.
	frameFree := frameScan := frameReclaimAt := 0.
	frameEpoch := decodeEpoch := 0.
	frameKeys atAllPut: nil.
	frameHash atAllPut: 0.
	processes atAllPut: nil.
	processUses atAllPut: -1.
	slotProcesses atAllPut: nil.
	slotBuffers do: [:each | each atAllPut: nil].
	decodeKeys := decodeStacks := decodedFrames := stackMemo := nil.
	epoch := (epoch ifNil: [0]) + 1
! !

!StackRing methodsFor: 'accessing'!
count
	"Answer how many records were ever written."
	^count
!
firstSerial
	^first
!
size
	"Answer how many records are in the ring."
	^count - first
!
isValidSerial: k
	^k < count and: [k >= first]
!
epoch
	"Answer how many times I was reset (serials restart at 0 then)."
	^epoch
!
depth
	^depth
!
dataSize
	^dataSize
!
frameCount
	^frameCount
!
lostFrames
	"Answer how many frames were recorded as unknown because the frame table was full."
	^lostFrames
!
lastFlags
	^lastFlags
!
usedBytes
	"Answer how many bytes the records in the ring take (about: a wrap leaves a gap at the end)."
	count = first ifTrue: [^0].
	^head > tail ifTrue: [head - tail] ifFalse: [dataSize - tail + head]
!
newestTime
	^count = first ifTrue: [nil] ifFalse: [lastTime]
!
oldestTime
	count = first ifTrue: [^nil].
	^self timeFrom: (data uint32At: tail + 5)
!
timeFrom: low32
	^lastTime - ((lastTime - low32) bitAnd: 16rFFFFFFFF)
! !

!StackRing methodsFor: 'recording'!
record: aProcess flags: flagBits
	"A CPU sample: aProcess's stack. Answer the serial. Never allocates."
	^self record: aProcess flags: flagBits class: nil size: 0
!
record: aProcess flags: flagBits class: aClassOrNil size: byteCount
	"Record aProcess's stack (aProcess nil: an unknown process, no stack); with aClassOrNil an allocation sample. Answer the serial. Never allocates."
	^self record: aProcess flags: flagBits class: aClassOrNil size: byteCount from: nil at: 0 count: 0 time: Time microsecondClockValue
!
record: aProcess flags: flagBits class: aClassOrNil size: byteCount from: anArrayOrNil at: start count: stackSize time: t
	"Record a sample taken at t (microsecond clock): with anArrayOrNil nil aProcess's stack now (aProcess not the active process), else the count frames from start in anArrayOrNil (method, block startpc pairs, outermost first, as the VM recorded them: Profiler>>drainBuffer), flagBits including the VM's (2 truncated, 8 just activated). Answer the serial. Never allocates."
	| buffer ids n k r slot o len extra procSlot prev lim truncated |
	n := 0.
	k := 0.
	lastFlags := 0.
	aProcess isNil ifFalse: [
		slot := aProcess identityHash \\ 16 + 1.
		buffer := slotBuffers at: slot.
		(slotProcesses at: slot) == aProcess ifFalse: [
			slotProcesses at: slot put: aProcess.
			buffer at: 1 put: nil].
		anArrayOrNil isNil
			ifTrue: [
				r := aProcess profilerStackInto: buffer maxDepth: depth.
				k := r bitAnd: 255.
				n := (r bitShift: -8) bitAnd: 255.
				lastFlags := (r bitShift: -15) bitAnd: 2.
				(r bitAnd: 16r20000) = 0 ifFalse: [lastFlags := lastFlags bitOr: 8]]
			ifFalse: [
				"as profilerStackInto:maxDepth: does: the bottom frames that equal the stack recorded last keep their ids"
				n := stackSize min: depth.
				lastFlags := flagBits bitAnd: 10.
				truncated := (lastFlags bitAnd: 2) = 0 ifTrue: [0] ifFalse: [1].
				prev := buffer at: 1.
				(prev isInteger and: [((prev bitShift: -16) bitAnd: 1) = truncated]) ifTrue: [
					lim := (prev bitAnd: 16rFFFF) min: n.
					[k < lim and: [(buffer at: k * 2 + 2) == (anArrayOrNil at: start + (k * 2)) and: [
						(buffer at: k * 2 + 3) = (anArrayOrNil at: start + (k * 2) + 1)]]] whileTrue: [k := k + 1]].
				k + 1 to: n do: [:j |
					buffer at: j * 2 put: (anArrayOrNil at: start + (j * 2) - 2).
					buffer at: j * 2 + 1 put: (anArrayOrNil at: start + (j * 2) - 1)].
				buffer at: 1 put: (n bitOr: (truncated bitShift: 16))].
		ids := slotIds at: slot.
		k + 1 to: n do: [:j | | id |
			id := self frameIdOf: (buffer at: j * 2) pc: ((buffer at: j * 2 + 1) min: 16rFFFE).
			"A frame that got no id is looked up again with the next sample of the process."
			id = 0 ifTrue: [buffer at: 1 put: nil].
			ids at: j put: id]].
	extra := aClassOrNil isNil ifTrue: [0] ifFalse: [8].
	len := 8 + extra + (4 * n).
	self makeRoom: len.
	o := head.
	procSlot := aProcess isNil ifTrue: [0] ifFalse: [self slotOfProcess: aProcess].
	data at: o + 1 put: ((flagBits bitOr: lastFlags) bitOr: (extra = 0 ifTrue: [0] ifFalse: [16])).
	data at: o + 2 put: n.
	data uint16At: o + 3 put: procSlot.
	data uint32At: o + 5 put: (t bitAnd: 16rFFFFFFFF).
	extra = 0 ifFalse: [
		data uint32At: o + 9 put: (self frameIdOf: aClassOrNil pc: 16rFFFF).
		data uint32At: o + 13 put: (byteCount min: 16rFFFFFFFF)].
	1 to: n do: [:j | data uint32At: o + 9 + extra + (j - 1 * 4) put: (ids at: j)].
	head := o + len.
	lastTime := t.
	count := count + 1.
	^count - 1
!
makeRoom: len
	"Drop the oldest records until len bytes are free at head (wrapping to offset 0 if they do not fit before the end)."
	head + len > dataSize ifTrue: [
		[count > first and: [tail >= head]] whileTrue: [self dropOldest].
		head < dataSize ifTrue: [data at: head + 1 put: 255].
		head := 0].
	[count > first and: [tail >= head and: [tail < (head + len)]]] whileTrue: [self dropOldest].
	count = first ifTrue: [tail := head]
!
dropOldest
	tail := tail + (self lengthAt: tail).
	first := first + 1.
	(tail >= dataSize or: [(data at: tail + 1) = 255]) ifTrue: [tail := 0].
	count = first ifTrue: [tail := head]
!
lengthAt: o
	^8 + (((data at: o + 1) bitAnd: 16) = 0 ifTrue: [0] ifFalse: [8]) + (4 * (data at: o + 2))
!
frameIdOf: anObject pc: pc
	"Intern (anObject, pc) in the frame table; answer its id (0 when the table is full of frames that records in the ring use)."
	| h id |
	h := (anObject identityHash * 31) + pc bitAnd: frameMask.
	[(id := frameHash uint16At: h * 2 + 1) = 0] whileFalse: [
		((frameKeys at: id) == anObject and: [(framePcs uint16At: id * 2 - 1) = pc]) ifTrue: [^id].
		h := h + 1 bitAnd: frameMask].
	frameCount < frameKeys size
		ifTrue: [id := frameCount := frameCount + 1]
		ifFalse: [
			(id := self freeFrameId) = 0 ifTrue: [lostFrames := lostFrames + 1. ^0].
			"Reclaiming rebuilds the hash table."
			h := (anObject identityHash * 31) + pc bitAnd: frameMask.
			[(frameHash uint16At: h * 2 + 1) = 0] whileFalse: [h := h + 1 bitAnd: frameMask]].
	frameKeys at: id put: anObject.
	framePcs uint16At: id * 2 - 1 put: pc.
	frameHash uint16At: h * 2 + 1 put: id.
	^id
!
freeFrameId
	"With the frame table full: an id that no record in the ring uses, for a new frame; 0 if there is none. Finding out which are free walks the whole ring, so not again before a quarter of its records are replaced."
	frameFree = 0 ifTrue: [
		count < frameReclaimAt ifTrue: [^0].
		self reclaimFrames.
		frameFree = 0 ifTrue: [^0]].
	[frameScan := frameScan + 1. (frameMarks at: frameScan) = 0] whileFalse.
	frameMarks at: frameScan put: 1.
	frameFree := frameFree - 1.
	^frameScan
!
reclaimFrames
	"Free the ids of the frames that neither a record in the ring uses nor the stack last recorded of a process (the next sample of the process records the frames both have in common by these ids). Never allocates."
	| o p n id h |
	1 to: frameMarks size do: [:i | frameMarks at: i put: 0].
	1 to: slotIds size do: [:s | | ids |
		ids := slotIds at: s.
		1 to: ids size do: [:j |
			((id := ids at: j) isNil or: [id = 0]) ifFalse: [frameMarks at: id put: 1]]].
	o := tail.
	first to: count - 1 do: [:k |
		(o >= dataSize or: [(data at: o + 1) = 255]) ifTrue: [o := 0].
		p := o + 8.
		((data at: o + 1) bitAnd: 16) = 0 ifFalse: [
			(id := data uint32At: o + 9) = 0 ifFalse: [frameMarks at: id put: 1].
			p := p + 8].
		n := data at: o + 2.
		1 to: n do: [:j |
			(id := data uint32At: p + (j - 1 * 4) + 1) = 0 ifFalse: [frameMarks at: id put: 1]].
		o := p + (4 * n)].
	1 to: frameHash size do: [:i | frameHash at: i put: 0].
	frameFree := 0.
	1 to: frameKeys size do: [:i |
		(frameMarks at: i) = 0
			ifTrue: [
				frameKeys at: i put: nil.
				frameFree := frameFree + 1]
			ifFalse: [
				h := ((frameKeys at: i) identityHash * 31) + (framePcs uint16At: i * 2 - 1) bitAnd: frameMask.
				[(frameHash uint16At: h * 2 + 1) = 0] whileFalse: [h := h + 1 bitAnd: frameMask].
				frameHash uint16At: h * 2 + 1 put: i]].
	frameScan := 0.
	frameEpoch := frameEpoch + 1.
	frameReclaimAt := count + (count - first // 4)
!
slotOfProcess: aProcess
	"The process table slot of aProcess (1-based), taking a free slot or one no record in the ring uses; 0 if none."
	| cap h q stale |
	cap := processes size.
	h := aProcess identityHash \\ cap + 1.
	stale := 0.
	cap timesRepeat: [
		q := processes at: h.
		q == aProcess ifTrue: [processUses at: h put: count. ^h].
		q isNil ifTrue: [
			stale = 0 ifTrue: [stale := h].
			processes at: stale put: aProcess.
			processUses at: stale put: count.
			^stale].
		(stale = 0 and: [(processUses at: h) < first]) ifTrue: [stale := h].
		h := h \\ cap + 1].
	stale = 0 ifTrue: [^0].
	processes at: stale put: aProcess.
	processUses at: stale put: count.
	^stale
! !

!StackRing methodsFor: 'reading'!
recordsFrom: startSerial kind: aSymbol frames: aFrameTable do: aBlock
	"Decode the records with serial >= startSerial still in the ring, oldest first, of aSymbol (#cpu or #allocation), into ProfileSamples and evaluate aBlock with each. Records dropped while decoding are left out."
	| o k n result |
	"A consistent start: the writer may interrupt between reading first and tail."
	[n := count. k := first. o := tail. k = first and: [n = count]] whileFalse.
	result := OrderedCollection new.
	[k < n] whileTrue: [ | flags len sample |
		(o >= dataSize or: [(data at: o + 1) = 255]) ifTrue: [o := 0].
		flags := data at: o + 1.
		len := self lengthAt: o.
		(k >= startSerial and: [((flags bitAnd: 16) = 0) = (aSymbol == #cpu)]) ifTrue: [
			sample := self decodeAt: o serial: k frames: aFrameTable.
			"Valid only if the writer did not drop it while it was read."
			k >= first ifTrue: [result add: sample]].
		k < first ifTrue: [
			"The writer overtook me: continue from its oldest record."
			k := first.
			o := tail]
		ifFalse: [
			o := o + len.
			k := k + 1]].
	result do: aBlock
!
recordsFrom: lastSerial at: lastOffset kind: aSymbol frames: aFrameTable do: aBlock
	"Like recordsFrom:kind:frames:do:, but continue after record lastSerial, which starts at byte lastOffset, instead of walking from the oldest record (nil, or lastSerial no longer in the ring: from the oldest). Answer {serial. offset} of the last record walked, to continue after it next time (nil if there is none). A record's bytes stay intact while it is in the ring; where the next one goes is only known once it is written."
	| o k n result lastK lastO |
	[n := count. k := first. o := tail. k = first and: [n = count]] whileFalse.
	(lastOffset notNil and: [lastSerial >= k and: [lastSerial < n]]) ifTrue: [ | len |
		len := self lengthAt: lastOffset.
		lastSerial >= first
			ifTrue: [k := lastSerial + 1. o := lastOffset + len. lastK := lastSerial. lastO := lastOffset]
			ifFalse: [[k := first. o := tail. k = first] whileFalse]].
	result := OrderedCollection new.
	[k < n] whileTrue: [ | flags len |
		(o >= dataSize or: [(data at: o + 1) = 255]) ifTrue: [o := 0].
		flags := data at: o + 1.
		len := self lengthAt: o.
		((flags bitAnd: 16) = 0) = (aSymbol == #cpu) ifTrue: [ | sample |
			sample := self decodeAt: o serial: k frames: aFrameTable.
			k >= first ifTrue: [result add: sample]].
		k < first
			ifTrue: [[k := first. o := tail. k = first] whileFalse]
			ifFalse: [lastK := k. lastO := o. o := o + len. k := k + 1]].
	result do: aBlock.
	^lastK isNil ifTrue: [nil] ifFalse: [Array with: lastK with: lastO]
!
decodeAt: o serial: k frames: aFrameTable
	"The sample of record k, which starts at o; nil if the writer dropped it meanwhile (what is at o then is another record, or the middle of one, and its frame ids may be other frames')."
	| flags n extra sample stack procSlot e |
	flags := data at: o + 1.
	n := data at: o + 2.
	procSlot := data uint16At: o + 3.
	k < first ifTrue: [^nil].
	e := frameEpoch.
	decodeEpoch = e ifFalse: [
		self forgetDecoded.
		decodeEpoch := e].
	extra := (flags bitAnd: 16) = 0 ifTrue: [0] ifFalse: [8].
	stack := self stackAt: o + 8 + extra count: n frames: aFrameTable.
	sample := ProfileSample new.
	sample
		setSerial: k
		time: (self timeFrom: (data uint32At: o + 5))
		process: (procSlot = 0 ifTrue: [nil] ifFalse: [processes at: procSlot])
		flags: (flags bitAnd: 15)
		stack: stack.
	extra = 0 ifFalse: [
		sample setAllocatedClass: (self keyOf: (data uint32At: o + 9)) size: (data uint32At: o + 13)].
	k < first ifTrue: [
		self forgetDecoded.
		^nil].
	^sample
!
forgetDecoded
	decodeKeys := decodeStacks := decodedFrames := stackMemo := nil
!
stackAt: offset count: n frames: aFrameTable
	"The ProfileFrames of the n frame ids at offset (outermost first), innermost first; equal stacks answer the same Array."
	| key |
	n = 0 ifTrue: [^#()].
	key := String new: 4 * n.
	key replaceFrom: 1 to: 4 * n with: data startingAt: offset + 1.
	stackMemo isNil ifTrue: [stackMemo := Dictionary new: 4096].
	^stackMemo at: key ifAbsent: [ | ids |
		stackMemo size > 30000 ifTrue: [stackMemo := Dictionary new: 4096].
		"Decode the key's copy of the ids: the record may be overwritten meanwhile."
		ids := ByteArray new: 4 * n.
		ids replaceFrom: 1 to: 4 * n with: key startingAt: 1.
		stackMemo at: key put: (self stackIn: ids count: n frames: aFrameTable)]
!
stackIn: ids count: n frames: aFrameTable
	"Intern the stack of the n frame ids in the ByteArray ids in the trie."
	| node |
	decodeKeys isNil ifTrue: [
		decodeKeys := Dictionary new: 4096.
		decodeStacks := OrderedCollection new: 4096.
		decodedFrames := Array new: frameKeys size].
	decodeStacks size > 200000 ifTrue: [
		decodeKeys := Dictionary new: 4096.
		decodeStacks := OrderedCollection new: 4096].
	node := 0.
	1 to: n do: [:j | | id key next |
		id := ids uint32At: j - 1 * 4 + 1.
		key := node * 8193 + id.
		next := decodeKeys at: key ifAbsent: [nil].
		next isNil ifTrue: [
			decodeStacks addLast: (node = 0
				ifTrue: [Array with: (self frameFor: id frames: aFrameTable)]
				ifFalse: [(Array with: (self frameFor: id frames: aFrameTable)), (decodeStacks at: node)]).
			next := decodeStacks size.
			decodeKeys at: key put: next].
		node := next].
	^node = 0 ifTrue: [#()] ifFalse: [decodeStacks at: node]
!
keyOf: id
	^(id between: 1 and: frameCount) ifTrue: [frameKeys at: id] ifFalse: [nil]
!
frameFor: id frames: aFrameTable
	| frame key pc |
	(id between: 1 and: frameCount) ifFalse: [^aFrameTable unknownFrame].
	(frame := decodedFrames at: id) isNil ifFalse: [^frame].
	(key := frameKeys at: id) isNil ifTrue: [^aFrameTable unknownFrame].
	pc := framePcs uint16At: id * 2 - 1.
	frame := aFrameTable frameFor: key startpc: (pc = 0 ifTrue: [nil] ifFalse: [pc]).
	decodedFrames at: id put: frame.
	^frame
! !

!StackRing methodsFor: 'statistics'!
tableBytes
	^(16 + (8 * processes size)) + (16 + (8 * processUses size)) + (16 + (8 * frameKeys size)) + (16 + framePcs size) + (16 + frameHash size) + (16 + frameMarks size)
		+ (16 + (8 * 16)) + (16 + (8 * 16)) + (16 * ((16 + (8 * (2 * depth + 1))) + (16 + (8 * depth))))
!
byteSize
	"Answer the bytes my buffers and tables occupy (object headers included)."
	^self tableBytes + 16 + dataSize
! !

!StackRing methodsFor: 'printing'!
printOn: aStream
	super printOn: aStream.
	aStream nextPut: $(; print: self size; nextPutAll: ' samples'.
	count = first ifFalse: [
		aStream nextPutAll: ', '; print: (self newestTime - self oldestTime) // 1000; nextPutAll: ' ms'].
	aStream nextPutAll: ', '; print: self byteSize // 1024; nextPutAll: ' KB)'
! !

!StackRing class methodsFor: 'instance creation'!
bytes: totalBytes depth: maxDepth
	^self new setBytes: totalBytes depth: maxDepth
! !
