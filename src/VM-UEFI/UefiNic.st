UefiModule subclass: #UefiSnp
	instanceVariableNames: 'common events snp mac txBuffers txBusy started queue queueLengths queueHead queueCount sem armed lastActiveNs received sent failed'
	classVariableNames: 'EFI_NOT_READY EFI_OPEN_PROTOCOL_EXCLUSIVE EFI_OPEN_PROTOCOL_GET_PROTOCOL SNP_BUSY_NS SNP_FRAME SNP_QUEUE SNP_TX_SLOTS'
	package: 'VM-UEFI'!

UefiSnp comment: 'The raw network interface on UEFI (in place of PlatformNic), through the firmware''s simple network protocol (SNP): Ethernet frames for the image''s TCP/IP stack. open: takes the first Ethernet SNP with EFI_OPEN_PROTOCOL_EXCLUSIVE from our image, so that the firmware''s own network stack (MNP and everything over it) lets go of it and takes no more frames, starts and initializes it, and lets unicast and broadcast frames in. A frame goes out from one of SNP_TX_SLOTS buffers of ours, busy until GetStatus hands it back. poll (from the platform''s poll and wait) moves what the NIC received into a queue of SNP_QUEUE frames, from which receive:max: takes them, and signals the semaphore. While frames came or went in the last SNP_BUSY_NS, a wait polls without pause (spin:): the firmware''s timer ticks only every 10 ms.'!

!UefiSnp class methodsFor: 'declaring'!
declarations
	^#((common PlatformCommon) (events UefiEvents) (snp 'EfiSimpleNetwork *') (mac 'uint8_t[6]') (txBuffers 'uint8_t *') (txBusy 'bool[64]') (started bool)
		(queue 'uint8_t *') (queueLengths 'int32_t[256]') (queueHead int32_t) (queueCount int32_t) (sem int32_t) (armed bool)
		(lastActiveNs int64_t) (received int64_t) (sent int64_t) (failed int64_t))
!
replaces
	^PlatformNic
!
initialize
	EFI_NOT_READY := 16r8000000000000006.
	EFI_OPEN_PROTOCOL_GET_PROTOCOL := 2.
	EFI_OPEN_PROTOCOL_EXCLUSIVE := 16r20.
	SNP_FRAME := 1536.
	SNP_TX_SLOTS := 64.
	SNP_QUEUE := 256.
	SNP_BUSY_NS := 20000000
! !

!UefiSnp methodsFor: 'starting'!
open: aMac
	"Find, take and initialize the NIC (once); its MAC address into aMac."
	<function>
	<var: #aMac type: 'uint8_t *'>
	<returns: 'bool'>
	self start ifFalse: [
		common setError: 'no network interface'.
		^false].
	libc memcpy: aMac from: mac size: 6.
	^true
!
start
	<function>
	<returns: 'bool'>
	| guid count handles |
	started ifTrue: [^snp notNull].
	started := true.
	guid := self local: 'EfiGuid'.
	firmware guid: guid data1: 16rA19832B9 data2: 16rAC25 data3: 16r11D3 data4: 16r9A2D0090273FC14D.
	count := self local: 'uint64_t'.
	handles := self local: 'void **'.
	(self efiFailed: (self efi: self boot locateHandleBuffer with: 2 with: guid with: self null with: count with: handles)) ifTrue: [^false].
	0 to: count value asInt64 - 1 do: [:i |
		snp isNull ifTrue: [self open: (handles value at: i) guid: guid]].
	self efi: self boot freePool with: handles value.
	snp isNull ifTrue: [^false].
	txBuffers := self cCoerce: (libc malloc: SNP_FRAME * SNP_TX_SLOTS) to: 'uint8_t *'.
	queue := self cCoerce: (libc malloc: SNP_FRAME * SNP_QUEUE) to: 'uint8_t *'.
	(txBuffers isNull or: [queue isNull]) ifTrue: [snp := self null].
	^snp notNull
!
open: handle guid: guid
	"handle's SNP if it is Ethernet's: exclusively (the firmware's own stack stops), else shared; started, initialized, filtering."
	<function>
	<var: #handle type: 'void *'>
	<var: #guid type: 'EfiGuid *'>
	| p s mode |
	p := self local: 'void *'.
	(self efiFailed: (self efi: self boot handleProtocol with: handle with: guid with: p)) ifTrue: [^self].
	s := self cCoerce: p value to: 'EfiSimpleNetwork *'.
	(s mode ifType ~= 1 or: [s mode hwAddressSize ~= 6]) ifTrue: [^self].
	(self efiFailed: (self efi: self boot openProtocol with: handle with: guid with: p with: firmware imageHandle with: self null with: EFI_OPEN_PROTOCOL_EXCLUSIVE))
		ifTrue: [self efi: self boot openProtocol with: handle with: guid with: p with: firmware imageHandle with: self null with: EFI_OPEN_PROTOCOL_GET_PROTOCOL].
	s := self cCoerce: p value to: 'EfiSimpleNetwork *'.
	mode := s mode.
	mode state = 0 ifTrue: [self efi: s start with: s].
	mode state = 1 ifTrue: [self efi: s initializeNic with: s with: 0 with: 0].
	mode state = 2 ifFalse: [^self].
	"unicast and broadcast"
	self efi: s receiveFilters with: s with: (mode receiveFilterMask bitAnd: 5) with: 0 with: 0 with: 0 with: self null.
	0 to: 5 do: [:i | mac at: i put: ((self cCoerce: (mode fieldAddress: #currentAddress) to: 'uint8_t *') at: i)].
	snp := s
! !

!UefiSnp methodsFor: 'frames'!
send: frame length: n
	"A whole Ethernet frame (without its checksum); false if it could not go (the transmit queue full)."
	<function>
	<var: #frame type: 'const uint8_t *'>
	<var: #n type: 'int64_t'>
	<returns: 'bool'>
	| slot buf size status tries |
	snp isNull ifTrue: [
		common setError: 'no network interface'.
		^false].
	n > SNP_FRAME ifTrue: [^false].
	self recycle.
	slot := -1.
	0 to: SNP_TX_SLOTS - 1 do: [:i | (slot < 0 and: [(txBusy at: i) not]) ifTrue: [slot := i]].
	slot < 0 ifTrue: [
		failed := failed + 1.
		^false].
	buf := txBuffers + (slot * SNP_FRAME).
	libc memcpy: buf from: frame size: n asUInt64.
	size := n.
	size < 60 ifTrue: [
		libc memset: buf + size value: 0 size: (60 - size) asUInt64.
		size := 60].
	tries := 0.
	[status := self efi: snp transmit with: snp with: 0 with: size with: buf with: self null with: self null with: self null.
	 status = EFI_NOT_READY and: [tries < 100]] whileTrue: [
		self recycle.
		tries := tries + 1].
	(self efiFailed: status) ifTrue: [
		failed := failed + 1.
		^false].
	txBusy at: slot put: true.
	sent := sent + 1.
	lastActiveNs := self nowNs.
	^true
!
recycle
	"Take back the transmit buffers the NIC is done with."
	<function>
	| p slot |
	p := self local: 'void *'.
	[p value: self null.
	 (self efiFailed: (self efi: snp getStatus with: snp with: self null with: p)) not and: [p value notNull]] whileTrue: [
		slot := ((self cCoerce: p value to: 'uint8_t *') - txBuffers) quo: SNP_FRAME.
		(slot >= 0 and: [slot < SNP_TX_SLOTS]) ifTrue: [txBusy at: slot put: false]]
!
receive: buf max: n
	"The next frame received into buf (cut to n bytes): its length, 0 if none (the semaphore armed)."
	<function>
	<var: #buf type: 'uint8_t *'>
	<var: #n type: 'int64_t'>
	<returns: 'int64_t'>
	| len |
	snp isNull ifTrue: [
		common setError: 'no network interface'.
		^-2].
	queueCount = 0 ifTrue: [self take].
	queueCount = 0 ifTrue: [
		armed := true.
		^0].
	len := (queueLengths at: queueHead) asInt64.
	libc memcpy: buf from: queue + (queueHead * SNP_FRAME) size: (len < n ifTrue: [len] ifFalse: [n]) asUInt64.
	queueHead := (queueHead + 1) rem: SNP_QUEUE.
	queueCount := queueCount - 1.
	^len
!
take
	"Move the frames the NIC has into the queue, while there is room (the rest wait in the NIC)."
	<function>
	| size slot more |
	size := self local: 'uint64_t'.
	more := true.
	[more and: [queueCount < SNP_QUEUE]] whileTrue: [
		slot := (queueHead + queueCount) rem: SNP_QUEUE.
		size value: SNP_FRAME.
		(self efiFailed: (self efi: snp receive with: snp with: self null with: size with: queue + (slot * SNP_FRAME) with: self null with: self null with: self null))
			ifTrue: [more := false]
			ifFalse: [
				queueLengths at: slot put: size value asInt32.
				queueCount := queueCount + 1.
				received := received + 1.
				lastActiveNs := self nowNs]]
!
frameSemaphore: index
	"Signal external semaphore index once when a frame is waiting (0: none)."
	<function>
	<var: #index type: 'int32_t'>
	<returns: 'bool'>
	sem := index.
	armed := true.
	events updatePollInterval.
	^true
!
counters: v
	"{frames received. sent. sends that failed. frames waiting}"
	<function>
	<var: #v type: 'int64_t *'>
	<returns: 'bool'>
	snp isNull ifTrue: [
		common setError: 'no network interface'.
		^false].
	v at: 0 put: received.
	v at: 1 put: sent.
	v at: 2 put: failed.
	v at: 3 put: queueCount asInt64.
	^true
! !

!UefiSnp methodsFor: 'polling'!
nowNs
	<function>
	<returns: 'int64_t'>
	| ts |
	ts := self local: 'struct timespec'.
	posix clockGettime: posix CLOCK_MONOTONIC into: ts.
	^(ts tv_sec * 1000000000) + ts tv_nsec
!
wantsPolling
	"Whether the image waits for frames: then the platform polls (every millisecond, and its waits last 10 ms at most)."
	<function>
	<returns: 'bool'>
	^sem ~= 0 and: [snp notNull]
!
poll
	"Take what the NIC received; signal the semaphore if a frame waits. Answer whether it did."
	<function>
	<returns: 'bool'>
	(sem = 0 or: [snp isNull]) ifTrue: [^false].
	self recycle.
	self take.
	(armed and: [queueCount > 0]) ifFalse: [^false].
	armed := false.
	scheduler signalExternalSemaphore: sem.
	^true
!
spin: us
	"Instead of waiting up to us (< 0: indefinitely) while frames come and go: poll without pause until a frame waits, the NIC falls quiet or 10 ms pass. Answer how long there is still to wait (0 if a frame came or the time ran out)."
	<function>
	<var: #us type: 'int64_t'>
	<returns: 'int64_t'>
	| start limit elapsed |
	(self wantsPolling not or: [self nowNs - lastActiveNs >= SNP_BUSY_NS]) ifTrue: [^us].
	start := self nowNs.
	limit := ((us < 0 or: [us > 10000]) ifTrue: [10000] ifFalse: [us]) * 1000.
	elapsed := 0.
	[elapsed < limit and: [start + elapsed - lastActiveNs < SNP_BUSY_NS]] whileTrue: [
		self poll ifTrue: [^0].
		elapsed := self nowNs - start].
	elapsed >= limit ifTrue: [^0].
	^us < 0 ifTrue: [us] ifFalse: [us - (elapsed quo: 1000)]
! !

VMStruct subclass: #EfiSimpleNetwork
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiSimpleNetwork comment: 'EFI_SIMPLE_NETWORK_PROTOCOL (UEFI 2.10, 24.1).'!

!EfiSimpleNetwork class methodsFor: 'declaring'!
fields
	^#((revision uint64_t) (start 'void *') (stop 'void *') (initializeNic 'void *') (reset 'void *') (shutdown 'void *')
		(receiveFilters 'void *') (stationAddress 'void *') (statistics 'void *') (mcastIpToMac 'void *') (nvData 'void *')
		(getStatus 'void *') (transmit 'void *') (receive 'void *') (waitForPacket 'void *') (mode 'EfiSnpMode *'))
! !

VMStruct subclass: #EfiSnpMode
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiSnpMode comment: 'EFI_SIMPLE_NETWORK_MODE (state: 0 stopped, 1 started, 2 initialized; the MAC addresses are EFI_MAC_ADDRESS, 32 bytes).'!

!EfiSnpMode class methodsFor: 'declaring'!
fields
	^#((state uint32_t) (hwAddressSize uint32_t) (mediaHeaderSize uint32_t) (maxPacketSize uint32_t) (nvRamSize uint32_t)
		(nvRamAccessSize uint32_t) (receiveFilterMask uint32_t) (receiveFilterSetting uint32_t) (maxMCastFilterCount uint32_t)
		(mcastFilterCount uint32_t) (mcastFilter 'uint8_t[512]') (currentAddress 'uint8_t[32]') (broadcastAddress 'uint8_t[32]')
		(permanentAddress 'uint8_t[32]') (ifType uint8_t) (macAddressChangeable uint8_t) (multipleTxSupported uint8_t)
		(mediaPresentSupported uint8_t) (mediaPresent uint8_t))
! !
