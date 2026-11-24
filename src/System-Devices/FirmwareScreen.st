Object subclass: #FirmwareScreen
	instanceVariableNames: 'firmware gop frameBuffer blt width height stride rgb shadow sprite scratch cursor lock tap'
	classVariableNames: 'Arrow'
	package: 'System-Devices'!

FirmwareScreen comment: 'I am the screen: the firmware''s graphics output (EFI_GRAPHICS_OUTPUT_PROTOCOL, UEFI 2.10, 12.9) in its mode of the size the window is opened with, else the mode it booted with, written straight into its linear framebuffer, or, where the mode has none (PixelBltOnly, as edk2''s VirtioGpuDxe on QEMU''s virtio-gpu, which has the large modes such as 1920x1080), through the protocol''s Blt (EfiBltBufferToVideo) from the shadow copy. present:width:height: takes a whole frame (BGRA8 rows), keeps it in a shadow copy and draws the pointer, an arrow, over it (present:width:height:rects: only the rectangles that changed since the last frame: copies them into the shadow copy and Blts each, the firmware then transfers only them); moving the pointer restores what was under it from the shadow copy, so it moves without a new frame. Once I draw, the firmware''s text console is silenced (its OutputString is its TestString): it would draw over me. After each present my FrameTap (frameTap) hears which rectangles changed, and reads them from the shadow copy, without the pointer.'!

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
	self allocateShadow.
	self silenceConsole.
	^true
!
allocateShadow
	"The shadow copy of my width and height, the pointer's sprite and its scratch, the pointer in the middle."
	shadow := Machine allocate: width * height * 4.
	sprite := Machine allocate: Arrow first size * Arrow size * 4.
	scratch := Machine allocate: Arrow first size * Arrow size * 4.
	Arrow doWithIndex: [:row :y |
		row doWithIndex: [:c :x |
			c = $. ifFalse: [Machine uint32At: sprite + ((y - 1) * row size + x - 1 * 4) put: (c = $X ifTrue: [16rFF000000] ifFalse: [16rFFFFFFFF])]]].
	cursor := (width // 2) @ (height // 2)
!
setOffscreen: anExtent
	"No firmware: a framebuffer of anExtent BGRA8 pixels in memory (tests)."
	lock := Semaphore forMutualExclusion.
	width := anExtent x.
	height := anExtent y.
	stride := width * 4.
	blt := false.
	rgb := false.
	frameBuffer := Machine allocate: width * height * 4.
	self allocateShadow
!
freeOffscreen
	"Free the memory of a screen made with offscreen:."
	lock critical: [
		frameBuffer isNil ifFalse: [Machine free: frameBuffer. Machine free: shadow. Machine free: sprite. Machine free: scratch].
		frameBuffer := shadow := sprite := scratch := width := height := nil]
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
!
frameBuffer
	"The address of the linear framebuffer (nil when the mode has none: Blt)."
	^frameBuffer
!
cursor
	^cursor
! !

!FirmwareScreen methodsFor: 'frame tap'!
frameTap
	"The FrameTap that hears what each present changes (FrameTap current while I draw)."
	tap isNil ifTrue: [tap := FrameTap source: self extent: (width isNil ifFalse: [width @ height])].
	^tap
!
frameTapPixelOrder
	"The shadow copy's pixels: Blue Green Red Reserved."
	^#bgra
!
frameTapRead: rects into: buffers
	"The shadow copy's pixels of each of rects (Rectangles within my extent) into the matching ByteArray of buffers, rows of width * 4 bytes, all under my lock (no present in between): what is on the screen, without the pointer."
	lock critical: [
		width isNil ifFalse: [
			rects with: buffers do: [:r :bytes |
				(r area > 0 and: [r right <= width and: [r bottom <= height]]) ifTrue: [
					SoftwareRaster copy: bytes stride: r width * 4 from: shadow + ((r top * width + r left) * 4) stride: width * 4
						width: r width height: r height bytesPerPixel: 4 mode: 0]]]]
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
		self drawCursor.
		self flushScreen].
	tap isNil ifFalse: [tap presented: #full extent: width @ height]
!
present: pixels width: w height: h rects: anArray
	"Only the rectangles anArray ({x. y. width. height} pixels) of the frame at pixels changed since the last one presented: copy them into the shadow copy and onto the screen, the pointer again over them where it was. They go as a few Blts (mergeBlts:): the frame at pixels is whole, so a merged rectangle copies pixels that did not change, which is cheaper than another call."
	| s t area rects |
	width isNil ifTrue: [^self].
	s := StageTimes current.
	lock critical: [
		s isNil ifFalse: [t := Time microsecondClockValue].
		area := 0.
		rects := OrderedCollection new.
		anArray do: [:each | | r |
			r := ((each at: 1) @ (each at: 2) extent: (each at: 3) @ (each at: 4)) intersect: (0 @ 0 extent: (w min: width) @ (h min: height)).
			(r width > 0 and: [r height > 0]) ifTrue: [rects add: r]].
		rects := self class mergeBlts: rects.
		rects do: [:r |
				SoftwareRaster
					copy: shadow + ((r top * width + r left) * 4) stride: width * 4
					from: pixels + ((r top * w + r left) * 4) stride: w * 4
					width: r width height: r height bytesPerPixel: 4 mode: 0.
				area := area + r area].
		s isNil ifFalse: [t := s add: #'screen.shadow' since: t bytes: area * 4].
		rects do: [:r | self copyToScreen: r].
		s isNil ifFalse: [s add: #'screen.blt' since: t bytes: area * 4].
		(rects anySatisfy: [:r | r intersects: (cursor extent: Arrow first size @ Arrow size)]) ifTrue: [self drawCursor].
		self flushScreen.
		self checkShadowAgainst: pixels width: w height: h].
	"What the caller damaged, however the Blts went."
	tap isNil ifFalse: [tap presented: anArray extent: width @ height]
!
checkShadowAgainst: pixels width: w height: h
	"While a DamageCheck runs (UI-Windows): the shadow copy, which took only the damaged rectangles, must be the whole frame."
	| check a b same |
	check := (Smalltalk at: #DamageCheck ifAbsent: [nil]) ifNotNil: [:c | c current].
	check isNil ifTrue: [^self].
	a := ByteArray new: (w min: width) * 4.
	b := ByteArray new: a size.
	same := true.
	0 to: (h min: height) - 1 do: [:y |
		same ifTrue: [
			SoftwareRaster copy: a stride: a size from: shadow + (y * width * 4) stride: width * 4 width: (w min: width) height: 1 bytesPerPixel: 4 mode: 0.
			SoftwareRaster copy: b stride: b size from: pixels + (y * w * 4) stride: w * 4 width: (w min: width) height: 1 bytesPerPixel: 4 mode: 0.
			same := (a compareBytes: b) = 0]].
	check notePresent: 'the firmware screen''s shadow copy' same: same
!
copyToScreen: aRectangle
	"Shadow pixels of aRectangle (clipped) to the screen."
	| r |
	r := aRectangle intersect: (0 @ 0 extent: width @ height).
	(r width > 0 and: [r height > 0]) ifFalse: [^self].
	self touched: r.
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
			self flushScreen.
			s isNil ifFalse: [s add: #'screen.pointer' since: t bytes: 0]]]
!
drawCursor
	"The arrow at the pointer: straight into the framebuffer, or with Blt from the shadow pixels under it with the arrow over them."
	| w h |
	w := Arrow first size min: width - cursor x.
	h := Arrow size min: height - cursor y.
	(w > 0 and: [h > 0]) ifFalse: [^self].
	self touched: (cursor extent: w @ h).
	blt ifTrue: [
		SoftwareRaster copy: scratch stride: Arrow first size * 4 from: shadow + ((cursor y * width + cursor x) * 4) stride: width * 4 width: w height: h bytesPerPixel: 4 mode: 0.
		SoftwareRaster copy: scratch stride: Arrow first size * 4 from: sprite stride: Arrow first size * 4 width: w height: h bytesPerPixel: 4 mode: 2.
		^self bltFrom: scratch x: 0 y: 0 delta: Arrow first size * 4 to: (cursor extent: w @ h)].
	SoftwareRaster
		copy: frameBuffer + (cursor y * stride) + (cursor x * 4) stride: stride
		from: sprite stride: Arrow first size * 4
		width: w height: h bytesPerPixel: 4 mode: (rgb ifTrue: [3] ifFalse: [2])
!
touched: aRectangle
	"aRectangle of the screen was just written (under my lock); the firmware's framebuffer needs no telling (KmsScreen collects them)."
	^self
!
flushScreen
	"The rectangles touched: since the last flush are written (under my lock): nothing to do on the firmware's screen (KmsScreen tells the kernel, DIRTYFB)."
	^self
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
!
offscreen: anExtent
	"A screen without firmware, its framebuffer in memory (tests); freeOffscreen frees it."
	^self new setOffscreen: anExtent
! !
!FirmwareScreen class methodsFor: 'damage'!
mergeBlts: rects
	"rects (pixel Rectangles that do not overlap much) as at most four, merged by the waste of their union: a Blt costs about 44 µs a call and 0.6 ns a pixel under QEMU (docs/graphics-damage.md), so two rectangles whose union adds fewer than 40,000 pixels go as one anyway, and beyond four the pair that wastes least merges."
	| result |
	result := rects asOrderedCollection.
	[result size > 1] whileTrue: [| best bestWaste i j |
		1 to: result size - 1 do: [:a |
			a + 1 to: result size do: [:b | | ra rb waste ow oh |
				ra := result at: a.
				rb := result at: b.
				ow := (ra right min: rb right) - (ra left max: rb left).
				oh := (ra bottom min: rb bottom) - (ra top max: rb top).
				waste := (ra merge: rb) area - ra area - rb area + ((ow > 0 and: [oh > 0]) ifTrue: [ow * oh] ifFalse: [0]).
				(bestWaste isNil or: [waste < bestWaste]) ifTrue: [bestWaste := waste. i := a. j := b]]].
		(result size > 4 or: [bestWaste < 40000]) ifFalse: [^result].
		result at: i put: ((result at: i) merge: (result at: j)).
		result removeIndex: j].
	^result
! !
