UefiModule subclass: #UefiScreen
	instanceVariableNames: 'gop frameBuffer width height stride rgb shadow cursorX cursorY cursorShown'
	classVariableNames: 'CURSOR_H CURSOR_W'
	package: 'VM-UEFI'!

UefiScreen comment: 'The display: the firmware''s graphics output (GOP) in the mode of the size the window is opened with, else the mode it booted with, written straight into its linear framebuffer. present:width:height: takes a whole frame (BGRA8 rows), keeps it in a shadow copy and draws the pointer over it; moving the pointer restores what was under it from the shadow copy, so it moves without a new frame.'!

!UefiScreen class methodsFor: 'declaring'!
declarations
	^#((gop 'EfiGraphicsOutput *') (frameBuffer 'uint8_t *') (width int32_t) (height int32_t) (stride int64_t) (rgb bool)
		(shadow 'uint8_t *') (cursorX int32_t) (cursorY int32_t) (cursorShown bool))
!
initialize
	CURSOR_W := 12.
	CURSOR_H := 19
! !

!UefiScreen methodsFor: 'starting'!
start: w height: h
	"Find the graphics output, in its mode of w x h if it has one; answer whether there is a framebuffer to draw into."
	<function>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<returns: 'bool'>
	| guid g info |
	frameBuffer notNull ifTrue: [^true].
	guid := self local: 'EfiGuid'.
	firmware guid: guid data1: 16r9042A9DE data2: 16r23DC data3: 16r4A38 data4: 16r96FB7ADED080516A.
	g := self local: 'EfiGraphicsOutput *'.
	(self efiFailed: (self efi: self boot locateProtocol with: guid with: self null with: g)) ifTrue: [^false].
	gop := g value.
	self setMode: w height: h.
	info := gop mode info.
	(info pixelFormat > 1 or: [gop mode frameBufferBase = 0]) ifTrue: [^false].
	rgb := info pixelFormat = 0.
	width := info horizontalResolution asInt32.
	height := info verticalResolution asInt32.
	stride := info pixelsPerScanLine asInt64 * 4.
	frameBuffer := self cCoerce: gop mode frameBufferBase to: 'uint8_t *'.
	shadow := self cCoerce: (libc calloc: (width * height) asUInt64 size: 4) to: 'uint8_t *'.
	shadow isNull ifTrue: [
		frameBuffer := self null.
		^false].
	cursorX := width quo: 2.
	cursorY := height quo: 2.
	firmware screenOwned: true.
	^true
!
setMode: w height: h
	<function>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	| size info found |
	size := self local: 'uint64_t'.
	info := self local: 'EfiGraphicsModeInfo *'.
	0 to: gop mode maxMode asInt32 - 1 do: [:i |
		(self efiFailed: (self efi: gop queryMode with: gop with: i with: size with: info)) ifFalse: [
			found := info value horizontalResolution asInt32 = w and: [info value verticalResolution asInt32 = h].
			self efi: self boot freePool with: info value.
			found ifTrue: [
				self efi: gop setMode with: gop with: i.
				^self]]]
!
width
	^width
!
height
	^height
! !

!UefiScreen methodsFor: 'drawing'!
present: pixels width: w height: h
	"A frame of w x h BGRA8 pixels: into the shadow copy and onto the screen, the pointer over it."
	<function>
	<var: #pixels type: 'const uint8_t *'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	| cw ch |
	frameBuffer isNull ifTrue: [^self].
	cw := w < width ifTrue: [w] ifFalse: [width].
	ch := h < height ifTrue: [h] ifFalse: [height].
	0 to: ch - 1 do: [:y |
		libc memcpy: shadow + (y * width * 4) from: pixels + (y * w * 4) size: (cw * 4) asUInt64].
	self copyToScreen: 0 y: 0 width: width height: height.
	self drawCursor
!
copyToScreen: x y: y width: w height: h
	"Shadow pixels of the rectangle (clipped) to the framebuffer."
	<function>
	<var: #x type: 'int32_t'>
	<var: #y type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	| x0 y0 x1 y1 src dst |
	x0 := x < 0 ifTrue: [0] ifFalse: [x].
	y0 := y < 0 ifTrue: [0] ifFalse: [y].
	x1 := x + w > width ifTrue: [width] ifFalse: [x + w].
	y1 := y + h > height ifTrue: [height] ifFalse: [y + h].
	(x1 <= x0 or: [y1 <= y0]) ifTrue: [^self].
	y0 to: y1 - 1 do: [:row |
		src := shadow + ((row * width + x0) * 4).
		dst := frameBuffer + (row * stride) + (x0 * 4).
		rgb
			ifTrue: [
				0 to: x1 - x0 - 1 do: [:i |
					dst at: i * 4 put: (src at: i * 4 + 2).
					dst at: i * 4 + 1 put: (src at: i * 4 + 1).
					dst at: i * 4 + 2 put: (src at: i * 4).
					dst at: i * 4 + 3 put: 0]]
			ifFalse: [libc memcpy: dst from: src size: ((x1 - x0) * 4) asUInt64]]
!
moveCursorTo: x y: y
	<function>
	<var: #x type: 'int32_t'>
	<var: #y type: 'int32_t'>
	frameBuffer isNull ifTrue: [^self].
	(x = cursorX and: [y = cursorY and: [cursorShown]]) ifTrue: [^self].
	cursorShown ifTrue: [self copyToScreen: cursorX y: cursorY width: CURSOR_W height: CURSOR_H].
	cursorX := x.
	cursorY := y.
	self drawCursor
!
drawCursor
	"The arrow at the pointer, straight into the framebuffer: X black, o white."
	<function>
	| shape c p v |
	shape := self cString: 'X...........XX..........XoX.........XooX........XoooX.......XooooX......XoooooX.....XooooooX....XoooooooX...XooooooooX..XoooooooooX.XooooooXXXXXXoooXooX....XooXXooX....XoX..XooX...XX...XooX...X.....XooX.........XooX..........XX...'.
	0 to: CURSOR_H - 1 do: [:row |
		0 to: CURSOR_W - 1 do: [:col |
			c := shape at: row * CURSOR_W + col.
			(c ~= $. value and: [cursorX + col < width and: [cursorY + row < height]]) ifTrue: [
				p := frameBuffer + ((cursorY + row) * stride) + ((cursorX + col) * 4).
				v := c = $X value ifTrue: [0] ifFalse: [255].
				p at: 0 put: v.
				p at: 1 put: v.
				p at: 2 put: v.
				p at: 3 put: 0]]].
	cursorShown := true
! !

UefiModule subclass: #UefiInput
	instanceVariableNames: 'keyboard absolute relative timer'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiInput comment: 'The keyboard (the console''s extended text input: key strokes with modifiers, no key releases) and the pointer (an absolute one, a USB tablet or a touch screen, else a relative one, a mouse) of the firmware; waiting for either or for a timeout.'!

!UefiInput class methodsFor: 'declaring'!
declarations
	^#((keyboard 'EfiTextInputEx *') (absolute 'EfiAbsolutePointer *') (relative 'EfiSimplePointer *') (timer 'void *'))
! !

!UefiInput methodsFor: 'starting'!
start
	<function>
	| guid p |
	guid := self local: 'EfiGuid'.
	p := self local: 'void *'.
	firmware guid: guid data1: 16rDD9E7534 data2: 16r7762 data3: 16r4698 data4: 16r8C14F58517A625AA.
	(self efiFailed: (self efi: self boot handleProtocol with: firmware conInHandle with: guid with: p))
		ifFalse: [keyboard := self cCoerce: p value to: 'EfiTextInputEx *'].
	firmware guid: guid data1: 16r8D59D32B data2: 16rC655 data3: 16r4AE9 data4: 16r9B15F25904992A43.
	(self efiFailed: (self efi: self boot locateProtocol with: guid with: self null with: p))
		ifFalse: [absolute := self cCoerce: p value to: 'EfiAbsolutePointer *'].
	firmware guid: guid data1: 16r31878C87 data2: 16r0B75 data3: 16r11D5 data4: 16r9A4F0090273FC14D.
	(self efiFailed: (self efi: self boot locateProtocol with: guid with: self null with: p))
		ifFalse: [relative := self cCoerce: p value to: 'EfiSimplePointer *'].
	(self efiFailed: (self efi: self boot createEvent with: EFI_EVT_TIMER with: 0 with: self null with: self null with: p))
		ifFalse: [timer := p value]
! !

!UefiInput methodsFor: 'reading'!
readKey: data
	"The next key stroke, if there is one."
	<function>
	<var: #data type: 'EfiKeyData *'>
	<returns: 'bool'>
	keyboard isNull ifTrue: [^false].
	^(self efiFailed: (self efi: keyboard readKeyStrokeEx with: keyboard with: data)) not
!
absoluteState: s
	"The absolute pointer's state, if it changed."
	<function>
	<var: #s type: 'EfiAbsolutePointerState *'>
	<returns: 'bool'>
	absolute isNull ifTrue: [^false].
	^(self efiFailed: (self efi: absolute getState with: absolute with: s)) not
!
relativeState: s
	"The relative pointer's movement since the last call, if any."
	<function>
	<var: #s type: 'EfiSimplePointerState *'>
	<returns: 'bool'>
	relative isNull ifTrue: [^false].
	^(self efiFailed: (self efi: relative getState with: relative with: s)) not
!
absoluteMode
	<function>
	<returns: 'EfiAbsolutePointerMode *'>
	absolute isNull ifTrue: [^self null].
	^absolute mode
! !

!UefiInput methodsFor: 'waiting'!
wait: us
	"Until a key, the pointer, or us microseconds (no timeout if negative)."
	<function>
	<var: #us type: 'int64_t'>
	| events n index |
	events := self local: 'void *[4]'.
	n := 0.
	(timer notNull and: [us >= 0]) ifTrue: [
		self efi: self boot setTimer with: timer with: EFI_TIMER_RELATIVE with: (us * 10) + 1.
		events at: n put: timer.
		n := n + 1].
	keyboard notNull ifTrue: [
		events at: n put: keyboard waitForKeyEx.
		n := n + 1].
	absolute notNull ifTrue: [
		events at: n put: absolute waitForInput.
		n := n + 1].
	relative notNull ifTrue: [
		events at: n put: relative waitForInput.
		n := n + 1].
	n = 0 ifTrue: [^self].
	index := self local: 'uint64_t'.
	self efi: self boot waitForEvent with: n with: events with: index
! !

VMStruct subclass: #EfiGraphicsOutput
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiGraphicsOutput comment: 'EFI_GRAPHICS_OUTPUT_PROTOCOL (UEFI 2.10, 12.9).'!

!EfiGraphicsOutput class methodsFor: 'declaring'!
fields
	^#((queryMode 'void *') (setMode 'void *') (blt 'void *') (mode 'EfiGraphicsMode *'))
! !

VMStruct subclass: #EfiGraphicsMode
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

!EfiGraphicsMode class methodsFor: 'declaring'!
fields
	^#((maxMode uint32_t) (currentMode uint32_t) (info 'EfiGraphicsModeInfo *') (sizeOfInfo uint64_t) (frameBufferBase uint64_t) (frameBufferSize uint64_t))
! !

VMStruct subclass: #EfiGraphicsModeInfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

!EfiGraphicsModeInfo class methodsFor: 'declaring'!
fields
	^#((infoVersion uint32_t) (horizontalResolution uint32_t) (verticalResolution uint32_t) (pixelFormat uint32_t)
		(redMask uint32_t) (greenMask uint32_t) (blueMask uint32_t) (reservedMask uint32_t) (pixelsPerScanLine uint32_t))
! !

VMStruct subclass: #EfiTextInputEx
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiTextInputEx comment: 'EFI_SIMPLE_TEXT_INPUT_EX_PROTOCOL (UEFI 2.10, 12.2).'!

!EfiTextInputEx class methodsFor: 'declaring'!
fields
	^#((resetEx 'void *') (readKeyStrokeEx 'void *') (waitForKeyEx 'void *') (setState 'void *') (registerKeyNotify 'void *') (unregisterKeyNotify 'void *'))
! !

VMStruct subclass: #EfiKeyData
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiKeyData comment: 'EFI_KEY_DATA: the key (scan code, character) and the shift and toggle state.'!

!EfiKeyData class methodsFor: 'declaring'!
fields
	^#((scanCode uint16_t) (unicodeChar uint16_t) (keyShiftState uint32_t) (keyToggleState uint8_t))
! !

VMStruct subclass: #EfiAbsolutePointer
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiAbsolutePointer comment: 'EFI_ABSOLUTE_POINTER_PROTOCOL (UEFI 2.10, 12.7).'!

!EfiAbsolutePointer class methodsFor: 'declaring'!
fields
	^#((resetPointer 'void *') (getState 'void *') (waitForInput 'void *') (mode 'EfiAbsolutePointerMode *'))
! !

VMStruct subclass: #EfiAbsolutePointerMode
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

!EfiAbsolutePointerMode class methodsFor: 'declaring'!
fields
	^#((minX uint64_t) (minY uint64_t) (minZ uint64_t) (maxX uint64_t) (maxY uint64_t) (maxZ uint64_t) (attributes uint32_t))
! !

VMStruct subclass: #EfiAbsolutePointerState
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

!EfiAbsolutePointerState class methodsFor: 'declaring'!
fields
	^#((currentX uint64_t) (currentY uint64_t) (currentZ uint64_t) (activeButtons uint32_t))
! !

VMStruct subclass: #EfiSimplePointer
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiSimplePointer comment: 'EFI_SIMPLE_POINTER_PROTOCOL (UEFI 2.10, 12.5).'!

!EfiSimplePointer class methodsFor: 'declaring'!
fields
	^#((resetPointer 'void *') (getState 'void *') (waitForInput 'void *') (mode 'void *'))
! !

VMStruct subclass: #EfiSimplePointerState
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

!EfiSimplePointerState class methodsFor: 'declaring'!
fields
	^#((relativeX int32_t) (relativeY int32_t) (relativeZ int32_t) (leftButton uint8_t) (rightButton uint8_t))
! !

VMStruct subclass: #EfiSerialIo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiSerialIo comment: 'EFI_SERIAL_IO_PROTOCOL (UEFI 2.10, 12.8), up to Write.'!

!EfiSerialIo class methodsFor: 'declaring'!
fields
	^#((revision uint32_t) (resetSerial 'void *') (setAttributes 'void *') (setControl 'void *') (getControl 'void *') (writeSerial 'void *'))
! !

UefiModule subclass: #UefiVirtioInput
	instanceVariableNames: 'pci commonBar commonOffset notifyBar notifyOffset deviceBar deviceOffset ring ringDevice size lastUsed absMaxX absMaxY absX absY relX relY buttons wheel absolute cpu'
	classVariableNames: 'VQ_AVAIL VQ_BUFFERS VQ_SIZE VQ_USED'
	package: 'VM-UEFI'!

UefiVirtioInput comment: 'A virtio input device (QEMU''s virtio-tablet or virtio-mouse; virtio 1.x over PCI) driven through the firmware''s PCI I/O protocol, for machines whose firmware has no pointer driver (OVMF has none). One event queue of VQ_SIZE 8-byte buffers in one DMA page, polled: the events (Linux evdev: absolute X and Y, relative X, Y and wheel, buttons) accumulate into the pointer''s state, which UefiEvents reads.'!

!UefiVirtioInput class methodsFor: 'declaring'!
declarations
	^#((pci 'EfiPciIo *') (commonBar uint8_t) (commonOffset uint64_t) (notifyBar uint8_t) (notifyOffset uint64_t)
		(deviceBar uint8_t) (deviceOffset uint64_t) (ring 'uint8_t *') (ringDevice uint64_t) (size int32_t) (lastUsed uint16_t)
		(absMaxX int64_t) (absMaxY int64_t) (absX int64_t -1) (absY int64_t -1) (relX int64_t) (relY int64_t) (buttons int32_t) (wheel int64_t)
		(absolute bool) (cpu UefiCpu))
!
initialize
	"The ring's page: descriptors, the available ring, the used ring, the event buffers."
	VQ_SIZE := 64.
	VQ_AVAIL := 1024.
	VQ_USED := 2048.
	VQ_BUFFERS := 3072
! !

!UefiVirtioInput methodsFor: 'PCI'!
config: offset width: w
	"PCI configuration space, w bytes (1, 2, 4)."
	<function>
	<var: #offset type: 'uint32_t'>
	<var: #w type: 'int32_t'>
	<returns: 'uint32_t'>
	| v |
	v := self local: 'uint32_t'.
	self efi: pci pciRead with: pci with: (w = 1 ifTrue: [0] ifFalse: [w = 2 ifTrue: [1] ifFalse: [2]]) with: offset with: 1 with: v.
	^v value
!
read: bar offset: offset width: w
	<function>
	<var: #bar type: 'uint8_t'>
	<var: #offset type: 'uint64_t'>
	<var: #w type: 'int32_t'>
	<returns: 'uint32_t'>
	| v |
	v := self local: 'uint32_t'.
	self efi: pci memRead with: pci with: (w = 1 ifTrue: [0] ifFalse: [w = 2 ifTrue: [1] ifFalse: [2]]) with: bar with: offset with: 1 with: v.
	^v value
!
write: bar offset: offset width: w value: value
	<function>
	<var: #bar type: 'uint8_t'>
	<var: #offset type: 'uint64_t'>
	<var: #w type: 'int32_t'>
	<var: #value type: 'uint32_t'>
	| v |
	v := self local: 'uint32_t'.
	v value: value.
	self efi: pci memWrite with: pci with: (w = 1 ifTrue: [0] ifFalse: [w = 2 ifTrue: [1] ifFalse: [2]]) with: bar with: offset with: 1 with: v
!
common: offset width: w
	^self read: commonBar offset: commonOffset + offset width: w
!
common: offset width: w put: value
	self write: commonBar offset: commonOffset + offset width: w value: value
! !

!UefiVirtioInput methodsFor: 'starting'!
start
	"Find a virtio input device (vendor 1AF4, device 1052) and start it; answer whether there is one."
	<function>
	<returns: 'bool'>
	| guid count handles p found |
	pci notNull ifTrue: [^true].
	guid := self local: 'EfiGuid'.
	firmware guid: guid data1: 16r4CF5B200 data2: 16r68B8 data3: 16r4CA5 data4: 16r9EECB23E3F50029A.
	count := self local: 'uint64_t'.
	handles := self local: 'void **'.
	(self efiFailed: (self efi: self boot locateHandleBuffer with: 2 with: guid with: self null with: count with: handles)) ifTrue: [^false].
	p := self local: 'EfiPciIo *'.
	found := false.
	0 to: (count value asInt64) - 1 do: [:i |
		(found not and: [(self efiFailed: (self efi: self boot handleProtocol with: (handles value at: i) with: guid with: p)) not]) ifTrue: [
			pci := p value.
			((self config: 0 width: 2) = 16r1AF4 and: [(self config: 2 width: 2) = 16r1052])
				ifTrue: [found := true]
				ifFalse: [pci := self null]]].
	self efi: self boot freePool with: handles value.
	found ifFalse: [^false].
	(self findCapabilities and: [self startDevice]) ifFalse: [
		pci := self null.
		^false].
	^true
!
findCapabilities
	"The common, notify and device configuration structures (virtio 1.2, 4.1.4)."
	<function>
	<returns: 'bool'>
	| cap type bar offset found |
	found := 0.
	cap := self config: 16r34 width: 1.
	[cap ~= 0] whileTrue: [
		(self config: cap width: 1) = 9 ifTrue: [
			type := self config: cap + 3 width: 1.
			bar := (self config: cap + 4 width: 1) asUInt8.
			offset := (self config: cap + 8 width: 4) asUInt64.
			type = 1 ifTrue: [commonBar := bar. commonOffset := offset. found := found bitOr: 1].
			type = 2 ifTrue: [
				notifyBar := bar.
				notifyOffset := offset.
				found := found bitOr: 2].
			type = 4 ifTrue: [deviceBar := bar. deviceOffset := offset. found := found bitOr: 4]].
		cap := self config: cap + 1 width: 1].
	^found = 7
!
startDevice
	"Reset, negotiate VIRTIO_F_VERSION_1, set up queue 0 with every buffer available, DRIVER_OK."
	<function>
	<returns: 'bool'>
	| supported host bytes mapping devAddr notifyOff mult desc |
	supported := self local: 'uint64_t'.
	self efi: pci attributes with: pci with: 4 with: 0 with: supported.
	self efi: pci attributes with: pci with: 2 with: (supported value bitAnd: 16r0600) with: self null.
	self common: 20 width: 1 put: 0.
	self common: 20 width: 1 put: 3.
	self common: 8 width: 4 put: 1.
	self common: 12 width: 4 put: 1.
	self common: 8 width: 4 put: 0.
	self common: 12 width: 4 put: 0.
	self common: 20 width: 1 put: 11.
	((self common: 20 width: 1) bitAnd: 8) = 0 ifTrue: [^false].
	self common: 22 width: 2 put: 0.
	size := (self common: 24 width: 2) asInt32.
	size > VQ_SIZE ifTrue: [size := VQ_SIZE].
	size = 0 ifTrue: [^false].
	self common: 24 width: 2 put: size asUInt32.
	host := self local: 'void *'.
	(self efiFailed: (self efi: pci allocateBuffer with: pci with: 0 with: 4 with: 1 with: host with: 0)) ifTrue: [^false].
	ring := self cCoerce: host value to: 'uint8_t *'.
	libc memset: ring value: 0 size: 4096.
	bytes := self local: 'uint64_t'.
	bytes value: 4096.
	devAddr := self local: 'uint64_t'.
	mapping := self local: 'void *'.
	(self efiFailed: (self efi: pci map with: pci with: 2 with: ring with: bytes with: devAddr with: mapping)) ifTrue: [^false].
	ringDevice := devAddr value.
	0 to: size - 1 do: [:i |
		desc := ring + (16 * i).
		self uint64At: desc put: ringDevice + VQ_BUFFERS + (8 * i).
		self uint32At: desc + 8 put: 8.
		self uint16At: desc + 12 put: 2.
		self uint16At: ring + VQ_AVAIL + 4 + (2 * i) put: i].
	self uint16At: ring + VQ_AVAIL + 2 put: size.
	self common: 32 width: 4 put: (ringDevice bitAnd: 16rFFFFFFFF) asUInt32.
	self common: 36 width: 4 put: (ringDevice >> 32) asUInt32.
	self common: 40 width: 4 put: ((ringDevice + VQ_AVAIL) bitAnd: 16rFFFFFFFF) asUInt32.
	self common: 44 width: 4 put: ((ringDevice + VQ_AVAIL) >> 32) asUInt32.
	self common: 48 width: 4 put: ((ringDevice + VQ_USED) bitAnd: 16rFFFFFFFF) asUInt32.
	self common: 52 width: 4 put: ((ringDevice + VQ_USED) >> 32) asUInt32.
	self common: 28 width: 2 put: 1.
	notifyOff := self common: 30 width: 2.
	mult := self config: (self notifyCapability + 16) width: 4.
	notifyOffset := notifyOffset + (notifyOff asUInt64 * mult asUInt64).
	self common: 20 width: 1 put: 15.
	absMaxX := self absMaximum: 0.
	absMaxY := self absMaximum: 1.
	self notify.
	^true
!
notifyCapability
	"The configuration offset of the notify capability."
	<function>
	<returns: 'uint32_t'>
	| cap |
	cap := self config: 16r34 width: 1.
	[cap ~= 0] whileTrue: [
		((self config: cap width: 1) = 9 and: [(self config: cap + 3 width: 1) = 2]) ifTrue: [^cap].
		cap := self config: cap + 1 width: 1].
	^0
!
absMaximum: axis
	"VIRTIO_INPUT_CFG_ABS_INFO of axis: its max; 0 if none."
	<function>
	<var: #axis type: 'uint32_t'>
	<returns: 'int64_t'>
	self write: deviceBar offset: deviceOffset width: 1 value: 16r12.
	self write: deviceBar offset: deviceOffset + 1 width: 1 value: axis.
	(self read: deviceBar offset: deviceOffset + 2 width: 1) < 8 ifTrue: [^0].
	^(self read: deviceBar offset: deviceOffset + 12 width: 4) asInt64
!
notify
	<function>
	cpu memoryBarrier.
	self write: notifyBar offset: notifyOffset width: 2 value: 0
! !

!UefiVirtioInput methodsFor: 'polling'!
poll
	"Take the events the device wrote, give their buffers back; answer whether any came."
	<function>
	<returns: 'bool'>
	| used id event type code value avail any |
	pci isNull ifTrue: [^false].
	cpu memoryBarrier.
	used := self uint16At: ring + VQ_USED + 2.
	any := false.
	[lastUsed ~= used] whileTrue: [
		id := self uint32At: ring + VQ_USED + 4 + (8 * (lastUsed rem: size)).
		event := ring + VQ_BUFFERS + (8 * id).
		type := self uint16At: event.
		code := self uint16At: event + 2.
		value := self int32At: event + 4.
		self event: type code: code value: value.
		avail := self uint16At: ring + VQ_AVAIL + 2.
		self uint16At: ring + VQ_AVAIL + 4 + (2 * (avail rem: size)) put: id.
		cpu memoryBarrier.
		self uint16At: ring + VQ_AVAIL + 2 put: (avail + 1) asUInt16.
		lastUsed := (lastUsed + 1) asUInt16.
		any := true].
	any ifTrue: [self notify].
	^any
!
event: type code: code value: value
	"Linux evdev: EV_KEY 1 (BTN_LEFT 110, RIGHT 111, MIDDLE 112 hex), EV_REL 2 (X 0, Y 1, WHEEL 8), EV_ABS 3 (X 0, Y 1)."
	<function>
	<var: #type type: 'uint32_t'>
	<var: #code type: 'uint32_t'>
	<var: #value type: 'int32_t'>
	| mask |
	type = 1 ifTrue: [
		mask := code = 16r110 ifTrue: [1] ifFalse: [code = 16r111 ifTrue: [4] ifFalse: [code = 16r112 ifTrue: [2] ifFalse: [0]]].
		buttons := (value ~= 0 ifTrue: [buttons bitOr: mask] ifFalse: [buttons bitAnd: mask bitInvert]) asInt32].
	type = 2 ifTrue: [
		code = 0 ifTrue: [relX := relX + value].
		code = 1 ifTrue: [relY := relY + value].
		code = 8 ifTrue: [wheel := wheel + value]].
	type = 3 ifTrue: [
		absolute := true.
		code = 0 ifTrue: [absX := value].
		code = 1 ifTrue: [absY := value]]
!
isPresent
	<function>
	<returns: 'bool'>
	^pci notNull
!
state: s
	"The pointer's state since the last call: absolute position as a fraction of the axes (-1 if unknown), relative movement and wheel (then zeroed), buttons."
	<function>
	<var: #s type: 'UefiPointerState *'>
	s absolute: absolute.
	s x: ((absolute and: [absMaxX > 0 and: [absX >= 0]]) ifTrue: [absX asFloat / (absMaxX + 1) asFloat] ifFalse: [-1.0]).
	s y: ((absolute and: [absMaxY > 0 and: [absY >= 0]]) ifTrue: [absY asFloat / (absMaxY + 1) asFloat] ifFalse: [-1.0]).
	s dx: relX.
	s dy: relY.
	s wheel: wheel.
	s buttons: buttons.
	relX := 0.
	relY := 0.
	wheel := 0
! !

VMStruct subclass: #UefiPointerState
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiPointerState comment: 'What UefiVirtioInput>>state: answers.'!

!UefiPointerState class methodsFor: 'declaring'!
fields
	^#((x double) (y double) (dx int64_t) (dy int64_t) (wheel int64_t) (buttons int32_t) (absolute bool))
! !

VMStruct subclass: #EfiPciIo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiPciIo comment: 'EFI_PCI_IO_PROTOCOL (UEFI 2.10, 14.4), up to Attributes.'!

!EfiPciIo class methodsFor: 'declaring'!
fields
	^#((pollMem 'void *') (pollIo 'void *') (memRead 'void *') (memWrite 'void *') (ioRead 'void *') (ioWrite 'void *')
		(pciRead 'void *') (pciWrite 'void *') (copyMem 'void *') (map 'void *') (unmap 'void *') (allocateBuffer 'void *')
		(freeBuffer 'void *') (flushIo 'void *') (getLocation 'void *') (attributes 'void *'))
! !
