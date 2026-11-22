Object subclass: #FirmwareScreen
	instanceVariableNames: 'firmware gop frameBuffer blt width height stride rgb shadow sprite scratch cursor lock'
	classVariableNames: 'Arrow'
	package: 'System-Devices'!

FirmwareScreen comment: 'I am the screen: the firmware''s graphics output (EFI_GRAPHICS_OUTPUT_PROTOCOL, UEFI 2.10, 12.9) in its mode of the size the window is opened with, else the mode it booted with, written straight into its linear framebuffer, or, where the mode has none (PixelBltOnly, as edk2''s VirtioGpuDxe on QEMU''s virtio-gpu, which has the large modes such as 1920x1080), through the protocol''s Blt (EfiBltBufferToVideo) from the shadow copy. present:width:height: takes a whole frame (BGRA8 rows), keeps it in a shadow copy and draws the pointer, an arrow, over it; moving the pointer restores what was under it from the shadow copy, so it moves without a new frame. Once I draw, the firmware''s text console is silenced (its OutputString is its TestString): it would draw over me.'!

!FirmwareScreen methodsFor: 'starting'!
setFirmware: aFirmware
	firmware := aFirmware.
	lock := Semaphore forMutualExclusion
!
start: anExtent
	"Find the graphics output, in its mode of anExtent if it has one; answer whether I can draw on it (into its framebuffer, else with Blt)."
	| mode info format |
	width notNil ifTrue: [^true].
	gop := firmware locateProtocol: '9042a9de-23dc-4a38-96fb-7aded080516a'.
	gop isNil ifTrue: [^false].
	self setMode: anExtent.
	mode := Machine uint64At: gop + 24.
	info := Machine uint64At: mode + 8.
	format := Machine uint32At: info + 12.
	blt := format > 1 or: [(Machine uint64At: mode + 24) = 0].
	rgb := blt not and: [format = 0].
	width := Machine uint32At: info + 4.
	height := Machine uint32At: info + 8.
	stride := (Machine uint32At: info + 32) * 4.
	blt ifFalse: [frameBuffer := Machine uint64At: mode + 24].
	shadow := Machine allocate: width * height * 4.
	sprite := Machine allocate: Arrow first size * Arrow size * 4.
	scratch := Machine allocate: Arrow first size * Arrow size * 4.
	Arrow doWithIndex: [:row :y |
		row doWithIndex: [:c :x |
			c = $. ifFalse: [Machine uint32At: sprite + ((y - 1) * row size + x - 1 * 4) put: (c = $X ifTrue: [16rFF000000] ifFalse: [16rFFFFFFFF])]]].
	cursor := (width // 2) @ (height // 2).
	self silenceConsole.
	^true
!
setMode: anExtent
	"The first mode of anExtent, if there is one."
	| maxMode sizeOut infoOut found |
	maxMode := Machine uint32At: (Machine uint64At: gop + 24).
	sizeOut := Machine allocate: 16.
	infoOut := sizeOut + 8.
	found := nil.
	0 to: maxMode - 1 do: [:i |
		found isNil ifTrue: [
			(firmware isError: (Machine call: (firmware function: gop at: 0) with: gop with: i with: sizeOut with: infoOut)) ifFalse: [| info |
				info := Machine uint64At: infoOut.
				((Machine uint32At: info + 4) = anExtent x and: [(Machine uint32At: info + 8) = anExtent y]) ifTrue: [found := i].
				firmware freePool: info]]].
	Machine free: sizeOut.
	found isNil ifFalse: [Machine call: (firmware function: gop at: 8) with: gop with: found]
!
silenceConsole
	"The console's OutputString becomes its TestString (same arguments, no output)."
	| out |
	out := firmware conOut.
	out = 0 ifTrue: [^self].
	Machine uint64At: out + 8 put: (Machine uint64At: out + 16)
! !

!FirmwareScreen methodsFor: 'accessing'!
extent
	^width @ height
!
isStarted
	^width notNil
! !

!FirmwareScreen methodsFor: 'drawing'!
present: pixels width: w height: h
	"A frame of w x h BGRA8 pixels at the address pixels: into the shadow copy and onto the screen, the pointer over it. While StageTimes measures, the copy and the transfer to the screen count as screen.shadow and screen.blt."
	| s t |
	width isNil ifTrue: [^self].
	s := StageTimes current.
	lock critical: [
		s isNil ifFalse: [t := Time microsecondClockValue].
		SoftwareRaster copy: shadow stride: width * 4 from: pixels stride: w * 4 width: (w min: width) height: (h min: height) bytesPerPixel: 4 mode: 0.
		s isNil ifFalse: [t := s add: #'screen.shadow' since: t bytes: (w min: width) * (h min: height) * 4].
		self copyToScreen: (0 @ 0 extent: width @ height).
		s isNil ifFalse: [s add: #'screen.blt' since: t bytes: width * height * 4].
		self drawCursor]
!
copyToScreen: aRectangle
	"Shadow pixels of aRectangle (clipped) to the screen."
	| r |
	r := aRectangle intersect: (0 @ 0 extent: width @ height).
	(r width > 0 and: [r height > 0]) ifFalse: [^self].
	blt ifTrue: [^self bltFrom: shadow x: r left y: r top delta: width * 4 to: r].
	SoftwareRaster
		copy: frameBuffer + (r top * stride) + (r left * 4) stride: stride
		from: shadow + ((r top * width + r left) * 4) stride: width * 4
		width: r width height: r height bytesPerPixel: 4 mode: (rgb ifTrue: [1] ifFalse: [0])
!
moveCursorTo: aPoint
	"The pointer to aPoint (pixels): what was under it back from the shadow copy, the arrow drawn there."
	| s t |
	width isNil ifTrue: [^self].
	s := StageTimes current.
	s isNil ifFalse: [t := Time microsecondClockValue].
	lock critical: [
		aPoint = cursor ifFalse: [
			self copyToScreen: (cursor extent: Arrow first size @ Arrow size).
			cursor := aPoint.
			self drawCursor.
			s isNil ifFalse: [s add: #'screen.pointer' since: t bytes: 0]]]
!
drawCursor
	"The arrow at the pointer: straight into the framebuffer, or with Blt from the shadow pixels under it with the arrow over them."
	| w h |
	w := Arrow first size min: width - cursor x.
	h := Arrow size min: height - cursor y.
	(w > 0 and: [h > 0]) ifFalse: [^self].
	blt ifTrue: [
		SoftwareRaster copy: scratch stride: Arrow first size * 4 from: shadow + ((cursor y * width + cursor x) * 4) stride: width * 4 width: w height: h bytesPerPixel: 4 mode: 0.
		SoftwareRaster copy: scratch stride: Arrow first size * 4 from: sprite stride: Arrow first size * 4 width: w height: h bytesPerPixel: 4 mode: 2.
		^self bltFrom: scratch x: 0 y: 0 delta: Arrow first size * 4 to: (cursor extent: w @ h)].
	SoftwareRaster
		copy: frameBuffer + (cursor y * stride) + (cursor x * 4) stride: stride
		from: sprite stride: Arrow first size * 4
		width: w height: h bytesPerPixel: 4 mode: (rgb ifTrue: [3] ifFalse: [2])
!
bltFrom: buffer x: sx y: sy delta: delta to: aRectangle
	"The pixels of buffer (BGRA8 rows of delta bytes) from sx@sy onto aRectangle of the screen with the protocol's Blt, EfiBltBufferToVideo (2): its pixels are Blue Green Red Reserved, the shadow copy's order."
	Machine call: (firmware function: gop at: 16) with: gop with: buffer with: 2 with: sx with: sy with: aRectangle left with: aRectangle top with: aRectangle width with: aRectangle height with: delta
! !

!FirmwareScreen class methodsFor: 'class initialization'!
initialize
	"The pointer: X black, o white."
	Arrow := #('X...........' 'XX..........' 'XoX.........' 'XooX........' 'XoooX.......' 'XooooX......' 'XoooooX.....' 'XooooooX....' 'XoooooooX...' 'XooooooooX..' 'XoooooooooX.' 'XooooooXXXXX' 'XoooXooX....' 'XooXXooX....' 'XoX..XooX...' 'XX...XooX...' 'X.....XooX..' '.......XooX.' '.........XX.')
! !

!FirmwareScreen class methodsFor: 'instance creation'!
firmware: aFirmware
	^self new setFirmware: aFirmware
! !
