FirmwareScreen subclass: #KmsScreen
	instanceVariableNames: 'path fd driver connector crtc crtcIndex modes mode handle fbId mapSize saved dirty pending retrying clips needsDirty plane fbProperty damageProperty failure counts'
	classVariableNames: ''
	package: 'System-Devices'!

KmsScreen comment: 'I am the screen on Linux without a window system (the appliance, docs/linux-appliance.md): a DRM device''s KMS output (/dev/dri/card*, linux/drm_mode.h) through PosixDevice, drawn as FirmwareScreen draws on a linear framebuffer. probe opens the device and finds a connected connector with modes and the CRTC that drives it; start: picks the mode (the --window-size one if the World was given it and the connector has it, else the connector''s preferred mode: the screen''s), makes a dumb buffer of it (CREATE_DUMB, MAP_DUMB and mmap), a framebuffer of that (ADDFB2, XRGB8888: the bytes Blue Green Red X, the shadow copy''s order) and shows it (SETCRTC). Frames go into the shadow copy and from there into the mapped buffer, only the damaged rectangles (present:width:height:rects:, FirmwareScreen), which are then flushed to the kernel: where the driver has atomic modesetting and damage clips (virtio-gpu), as a non-blocking atomic commit of the same framebuffer with them as its FB_DAMAGE_CLIPS (the driver transfers only them, in its own time: the VM does not wait; while the last commit is still being done, EBUSY, the rectangles wait for the next flush, 4 ms later at the latest), else in one DIRTYFB, which can block for a refresh (a driver that scans out the buffer as it is answers ENOSYS and is not asked again). The device is DRM master while I have it open (the first to open it is); stop shows what the CRTC showed before and closes it. counts: how many presents, whole frames, flushed rectangles and their pixels (the damage-limited path at work).'!

!KmsScreen methodsFor: 'starting'!
setPath: aPath
	path := aPath.
	lock := Semaphore forMutualExclusion.
	dirty := OrderedCollection new.
	pending := OrderedCollection new.
	retrying := false.
	needsDirty := true.
	counts := Dictionary new.
	failure := 'not probed'
!
probe
	"Open my device and find a connected output: answer whether there is one (the descriptor stays open)."
	| ok |
	fd isNil ifFalse: [^modes notNil].
	fd := [PosixDevice open: path flags: (PosixDevice O_RDWR bitOr: PosixDevice O_CLOEXEC)] on: OSError do: [:e | failure := e messageText. e return: nil].
	fd isNil ifTrue: [^false].
	ok := [self findOutput] on: OSError do: [:e | failure := e messageText. e return: false].
	ok ifFalse: [self closeDevice].
	^ok
!
findOutput
	"The driver's name, dumb buffers, a connected connector with modes and a CRTC for it."
	| resources |
	driver := self driverName.
	(self capability: 1) = 1 ifFalse: [failure := driver, ' has no dumb buffers'. ^false].
	resources := self resources.
	resources first do: [:id |
		modes isNil ifTrue: [
			(self connector: id) ifNotNil: [:info |
				(self crtcFor: info crtcs: resources last) ifNotNil: [:c |
					connector := id.
					crtc := c.
					crtcIndex := resources last indexOf: c.
					modes := info first]]]].
	modes isNil ifTrue: [failure := driver, ': no connected output'].
	^modes notNil
!
start: anExtent
	"Show a framebuffer in the mode for anExtent (modeFor:); answer whether I can draw."
	width notNil ifTrue: [^true].
	self probe ifFalse: [^false].
	[self setUp: (self modeFor: anExtent)] on: OSError do: [:e |
		failure := e messageText.
		self stop.
		^false].
	self allocateShadow.
	^true
!
modeFor: anExtent
	"The mode of anExtent if --window-size asked for it and the connector has it, else the preferred one (DRM_MODE_TYPE_PREFERRED), else the first."
	(Smalltalk argumentAfter: '--window-size') notNil ifTrue: [
		modes do: [:m | ((self class u16: m at: 4) = anExtent x and: [(self class u16: m at: 14) = anExtent y]) ifTrue: [^m]]].
	^modes detect: [:m | ((self class u32: m at: 32) bitAnd: 8) ~= 0] ifNone: [modes first]
!
setUp: aMode
	"A dumb buffer of aMode's size, mapped, as a framebuffer on my CRTC."
	| w h offset |
	w := self class u16: aMode at: 4.
	h := self class u16: aMode at: 14.
	[self ioctl: 16r641E at: 0] on: OSError do: [:e | e return: nil].
	saved := self with: 104 do: [:c |
		Machine uint32At: c + 12 put: crtc.
		self ioctl: 16rC06864A1 at: c.
		Machine bytesAt: c count: 104].
	self with: 32 do: [:d |
		Machine uint32At: d put: h; uint32At: d + 4 put: w; uint32At: d + 8 put: 32.
		self ioctl: 16rC02064B2 at: d.
		handle := Machine uint32At: d + 16.
		stride := Machine uint32At: d + 20.
		mapSize := Machine uint64At: d + 24].
	fbId := self addFramebuffer: w height: h.
	offset := self with: 16 do: [:d |
		Machine uint32At: d put: handle.
		self ioctl: 16rC01064B3 at: d.
		Machine uint64At: d + 8].
	frameBuffer := PosixDevice mmap: mapSize protection: (PosixDevice PROT_READ bitOr: PosixDevice PROT_WRITE) flags: PosixDevice MAP_SHARED fd: fd offset: offset.
	width := w.
	height := h.
	blt := false.
	rgb := false.
	mode := aMode.
	self setCrtc: fbId mode: aMode.
	[self findPlane] on: OSError do: [:e | e return: (plane := nil)]
!
findPlane
	"For atomic commits with damage: the plane that shows my framebuffer now (the primary of my CRTC, after SETCRTC) and its FB_ID and FB_DAMAGE_CLIPS properties; plane stays nil (DIRTYFB then) where the driver has no atomic modesetting or no damage clips."
	| ids |
	plane := nil.
	self setClientCapability: 2 to: 1.
	self setClientCapability: 3 to: 1.
	ids := self with: 16 do: [:r | | n buffer |
		self ioctl: 16rC01064B5 at: r.
		n := Machine uint32At: r + 8.
		buffer := Machine allocate: (n max: 1) * 4.
		[Machine uint64At: r put: buffer.
		self ioctl: 16rC01064B5 at: r.
		(1 to: (n min: (Machine uint32At: r + 8))) collect: [:i | Machine uint32At: buffer + (i - 1 * 4)]]
			ensure: [Machine free: buffer]].
	ids do: [:id |
		(plane isNil and: [(self with: 32 do: [:p | Machine uint32At: p put: id. self ioctl: 16rC02064B6 at: p. Machine uint32At: p + 8]) = fbId]) ifTrue: [| props |
			props := self propertiesOfPlane: id.
			((props includesKey: 'FB_ID') and: [props includesKey: 'FB_DAMAGE_CLIPS']) ifTrue: [
				plane := id.
				fbProperty := props at: 'FB_ID'.
				damageProperty := props at: 'FB_DAMAGE_CLIPS']]].
	^plane
!
propertiesOfPlane: id
	"The plane's properties: name -> id (DRM_IOCTL_MODE_OBJ_GETPROPERTIES, GETPROPERTY)."
	| result |
	result := Dictionary new.
	self with: 32 do: [:o | | n ids values |
		Machine uint32At: o + 20 put: id; uint32At: o + 24 put: 16rEEEEEEEE.
		self ioctl: 16rC02064B9 at: o.
		n := Machine uint32At: o + 16.
		ids := Machine allocate: (n max: 1) * 4.
		values := Machine allocate: (n max: 1) * 8.
		[Machine uint64At: o put: ids; uint64At: o + 8 put: values.
		self ioctl: 16rC02064B9 at: o.
		1 to: (n min: (Machine uint32At: o + 16)) do: [:i | | p |
			p := Machine uint32At: ids + (i - 1 * 4).
			self with: 64 do: [:g | | name |
				Machine uint32At: g + 16 put: p.
				self ioctl: 16rC04064AA at: g.
				name := Machine bytesAt: g + 24 count: 32.
				result at: (name copyFrom: 1 to: ((name indexOf: 0) - 1 max: 0)) asString put: p]]]
			ensure: [Machine free: ids. Machine free: values]].
	^result
!
setClientCapability: n to: value
	"DRM_IOCTL_SET_CLIENT_CAP: 2 universal planes, 3 atomic."
	self with: 16 do: [:c |
		Machine uint64At: c put: n; uint64At: c + 8 put: value.
		self ioctl: 16r4010640D at: c]
!
addFramebuffer: w height: h
	"ADDFB2 of my buffer as XRGB8888, else (an older driver) ADDFB at 32 bits, depth 24: the framebuffer's id."
	^[self with: 104 do: [:f |
		Machine uint32At: f + 4 put: w; uint32At: f + 8 put: h; uint32At: f + 12 put: 16r34325258; uint32At: f + 20 put: handle; uint32At: f + 36 put: stride.
		self ioctl: 16rC06864B8 at: f.
		Machine uint32At: f]]
		on: OSError do: [:e | e return: (self with: 28 do: [:f |
			Machine uint32At: f + 4 put: w; uint32At: f + 8 put: h; uint32At: f + 12 put: stride; uint32At: f + 16 put: 32; uint32At: f + 20 put: 24; uint32At: f + 24 put: handle.
			self ioctl: 16rC01C64AE at: f.
			Machine uint32At: f])]
!
setCrtc: aFramebuffer mode: aMode
	"SETCRTC: my CRTC shows aFramebuffer at 0@0 in aMode on my connector."
	self with: 108 do: [:c |
		Machine uint32At: c + 104 put: connector.
		Machine uint64At: c put: c + 104.
		Machine uint32At: c + 8 put: 1; uint32At: c + 12 put: crtc; uint32At: c + 16 put: aFramebuffer; uint32At: c + 32 put: 1.
		Machine bytesAt: c + 36 put: aMode.
		self ioctl: 16rC06864A2 at: c]
!
stop
	"Show what the CRTC showed before me, let go of the buffer, close the device."
	fd isNil ifTrue: [^self].
	lock critical: [
		[saved notNil ifTrue: [self with: 104 do: [:c |
			Machine bytesAt: c put: saved.
			Machine uint32At: c put: 0; uint32At: c + 4 put: 0; uint32At: c + 8 put: 0.
			(Machine uint32At: c + 16) = 0 ifFalse: [
				Machine uint32At: c + 104 put: connector.
				Machine uint64At: c put: c + 104.
				Machine uint32At: c + 8 put: 1].
			self ioctl: 16rC06864A2 at: c]]] on: OSError do: [:e | e return: nil].
		frameBuffer isNil ifFalse: [[PosixDevice munmap: frameBuffer length: mapSize] on: OSError do: [:e | e return: nil]].
		fbId isNil ifFalse: [self with: 4 do: [:f | Machine uint32At: f put: fbId. [self ioctl: 16rC00464AF at: f] on: OSError do: [:e | e return: nil]]].
		handle isNil ifFalse: [self with: 4 do: [:d | Machine uint32At: d put: handle. [self ioctl: 16rC00464B4 at: d] on: OSError do: [:e | e return: nil]]].
		clips isNil ifFalse: [Machine free: clips].
		shadow isNil ifFalse: [Machine free: shadow. Machine free: sprite. Machine free: scratch].
		frameBuffer := fbId := handle := clips := saved := shadow := sprite := scratch := width := height := nil].
	self closeDevice
!
closeDevice
	fd isNil ifFalse: [[PosixDevice close: fd] on: OSError do: [:e | e return: nil]].
	fd := nil
!
abandon
	"Forget the device without closing it: it was the previous VM process's."
	fd := frameBuffer := fbId := handle := clips := saved := shadow := sprite := scratch := width := height := nil
! !

!KmsScreen methodsFor: 'accessing'!
path
	^path
!
isInMemory
	"A screen of memory (inMemory:, offscreen:), no device: nothing to flush to."
	^fd isNil and: [frameBuffer notNil]
!
driver
	"The DRM driver's name (virtio_gpu, nvidia-drm, simpledrm, ...)."
	^driver
!
failure
	"Why the last probe or start failed."
	^failure
!
modeList
	"The connector's modes: {width. height. refresh}, preferred first."
	modes isNil ifTrue: [^#()].
	^(modes asSortedCollection: [:a :b | ((self class u32: a at: 32) bitAnd: 8) >= ((self class u32: b at: 32) bitAnd: 8)]) asArray
		collect: [:m | {self class u16: m at: 4. self class u16: m at: 14. self class u32: m at: 24}]
!
refreshRate
	"The mode's vertical refresh in Hz (60 if it says none)."
	| r |
	mode isNil ifTrue: [^60.0].
	r := self class u32: mode at: 24.
	^r = 0 ifTrue: [60.0] ifFalse: [r asFloat]
!
counts
	"presents (of damaged rectangles) and us (the microseconds they took: the copies and the flush), full (whole frames), rects and pixels written to the buffer (the frames' and the pointer's), commits, busy and commitUs (the atomic commits, those refused for now, their time), flushes and dirtyfbUs (the DIRTYFB calls and their time); how: #atomic, #dirtyfb or #none."
	^counts copy at: #how put: (plane notNil ifTrue: [#atomic] ifFalse: [needsDirty ifTrue: [#dirtyfb] ifFalse: [#none]]); yourself
!
description
	"What I show on: the device, driver, mode."
	^path, ' (', (driver ifNil: ['?']), ')', (width isNil ifTrue: [''] ifFalse: [' ', width printString, 'x', height printString, '@', self refreshRate rounded printString])
! !

!KmsScreen methodsFor: 'drawing'!
present: pixels width: w height: h
	self count: #full by: 1.
	super present: pixels width: w height: h
!
present: pixels width: w height: h rects: anArray
	| t |
	t := Time microsecondClockValue.
	self count: #presents by: 1.
	super present: pixels width: w height: h rects: anArray.
	self count: #us by: Time microsecondClockValue - t
!
touched: aRectangle
	dirty add: aRectangle.
	self count: #rects by: 1.
	self count: #pixels by: aRectangle area
!
flushScreen
	"Tell the kernel which rectangles of the buffer changed (with those an earlier commit could not take yet): an atomic commit with them as damage, else DIRTYFB; at most 16 rectangles, more go as their bounds."
	| rects n r t |
	(dirty isEmpty and: [pending isEmpty]) ifTrue: [^self].
	rects := pending, dirty.
	dirty := OrderedCollection new.
	pending := OrderedCollection new.
	rects size > 16 ifTrue: [rects := OrderedCollection with: (rects inject: rects first into: [:a :b | a merge: b])].
	plane isNil ifFalse: [^self commit: rects].
	(needsDirty and: [fd notNil]) ifFalse: [^self].
	t := Time microsecondClockValue.
	clips isNil ifTrue: [clips := Machine allocate: 24 + (16 * 8)].
	n := 0.
	rects do: [:each |
		r := each intersect: (0 @ 0 extent: width @ height).
		(r width > 0 and: [r height > 0]) ifTrue: [
			Machine uint16At: clips + 24 + (n * 8) put: r left; uint16At: clips + 26 + (n * 8) put: r top;
				uint16At: clips + 28 + (n * 8) put: r right; uint16At: clips + 30 + (n * 8) put: r bottom.
			n := n + 1]].
	n = 0 ifTrue: [^self].
	Machine uint32At: clips put: fbId; uint32At: clips + 4 put: 0; uint32At: clips + 8 put: 0; uint32At: clips + 12 put: n.
	Machine uint64At: clips + 16 put: clips + 24.
	[self ioctl: 16rC01864B1 at: clips] on: OSError do: [:e |
		(#(38 95) includes: e errno) ifTrue: [needsDirty := false].
		e return: nil].
	self count: #flushes by: 1.
	self count: #dirtyfbUs by: Time microsecondClockValue - t
!
commit: rects
	"A non-blocking atomic commit (DRM_MODE_ATOMIC_NONBLOCK) of my framebuffer on my plane again, rects (within the screen) as its FB_DAMAGE_CLIPS (a blob of drm_mode_rects). While the last commit is still being done (EBUSY) they wait for the next flush, one in 4 ms at the latest; a driver that refuses the commit otherwise gets DIRTYFB from now on."
	| t blob clipped |
	t := Time microsecondClockValue.
	clipped := (rects collect: [:each | each intersect: (0 @ 0 extent: width @ height)]) select: [:each | each width > 0 and: [each height > 0]].
	clipped isEmpty ifTrue: [^self].
	blob := self with: clipped size * 16 do: [:data |
		clipped doWithIndex: [:each :i | | at |
			at := data + (i - 1 * 16).
			Machine uint32At: at put: each left; uint32At: at + 4 put: each top; uint32At: at + 8 put: each right; uint32At: at + 12 put: each bottom].
		self with: 16 do: [:b |
			Machine uint64At: b put: data; uint32At: b + 8 put: clipped size * 16.
			self ioctl: 16rC01064BD at: b.
			Machine uint32At: b + 12]].
	"struct drm_mode_atomic (56 bytes), then the object, its property count, the two properties and their values."
	[self with: 88 do: [:a |
		Machine uint32At: a put: 16r0200; uint32At: a + 4 put: 1.
		Machine uint64At: a + 8 put: a + 56; uint64At: a + 16 put: a + 60; uint64At: a + 24 put: a + 64; uint64At: a + 32 put: a + 72.
		Machine uint32At: a + 56 put: plane; uint32At: a + 60 put: 2; uint32At: a + 64 put: fbProperty; uint32At: a + 68 put: damageProperty.
		Machine uint64At: a + 72 put: fbId; uint64At: a + 80 put: blob.
		self ioctl: 16rC03864BC at: a].
	 self count: #commits by: 1]
		on: OSError do: [:e |
			e errno = 16
				ifTrue: [
					self count: #busy by: 1.
					pending addAll: clipped.
					self retryFlush]
				ifFalse: [plane := nil. pending addAll: clipped. self retryFlush].
			e return: nil].
	self with: 4 do: [:b | Machine uint32At: b put: blob. [self ioctl: 16rC00464BE at: b] on: OSError do: [:e | e return: nil]].
	self count: #commitUs by: Time microsecondClockValue - t
!
retryFlush
	"Flush what is pending 4 ms from now (unless a present does it first)."
	retrying ifTrue: [^self].
	retrying := true.
	[(Delay forMilliseconds: 4) wait.
	 lock critical: [
		retrying := false.
		width isNil ifFalse: [self flushScreen]]] forkAt: Processor highIOPriority + 5 named: 'kms flush'
!
count: aSymbol by: n
	counts at: aSymbol put: (counts at: aSymbol ifAbsent: [0]) + n
! !

!KmsScreen methodsFor: 'private'!
with: size do: aBlock
	"aBlock's value for the address of size zeroed bytes outside the heap, freed after."
	| a |
	a := Machine allocate: size.
	^[aBlock value: a] ensure: [Machine free: a]
!
ioctl: request at: address
	^PosixDevice ioctl: fd request: request argument: address
!
capability: n
	"DRM_IOCTL_GET_CAP n."
	^self with: 16 do: [:c |
		Machine uint64At: c put: n.
		self ioctl: 16rC010640C at: c.
		Machine uint64At: c + 8]
!
driverName
	"DRM_IOCTL_VERSION's name."
	^self with: 64 do: [:v | | n name |
		self ioctl: 16rC0406400 at: v.
		n := (Machine uint64At: v + 16) min: 64.
		name := Machine allocate: n + 1.
		[Machine bytesAt: v put: (ByteArray new: 64).
		Machine uint64At: v + 16 put: n; uint64At: v + 24 put: name.
		self ioctl: 16rC0406400 at: v.
		(Machine bytesAt: name count: n) asString]
			ensure: [Machine free: name]]
!
resources
	"{the connectors' ids. the CRTCs' ids} (DRM_IOCTL_MODE_GETRESOURCES twice: the counts, then the arrays)."
	^self with: 64 do: [:r | | nCrtcs nConnectors crtcs connectors |
		self ioctl: 16rC04064A0 at: r.
		nCrtcs := Machine uint32At: r + 36.
		nConnectors := Machine uint32At: r + 40.
		crtcs := Machine allocate: (nCrtcs max: 1) * 4.
		connectors := Machine allocate: (nConnectors max: 1) * 4.
		[Machine bytesAt: r put: (ByteArray new: 64).
		Machine uint64At: r + 8 put: crtcs; uint64At: r + 16 put: connectors; uint32At: r + 36 put: nCrtcs; uint32At: r + 40 put: nConnectors.
		self ioctl: 16rC04064A0 at: r.
		{(1 to: (nConnectors min: (Machine uint32At: r + 40))) collect: [:i | Machine uint32At: connectors + (i - 1 * 4)].
		 (1 to: (nCrtcs min: (Machine uint32At: r + 36))) collect: [:i | Machine uint32At: crtcs + (i - 1 * 4)]}]
			ensure: [Machine free: crtcs. Machine free: connectors]]
!
connector: id
	"{its modes (each the 68 bytes of a drm_mode_modeinfo). its encoder. the encoders it can use} if it is connected and has modes, else nil (DRM_IOCTL_MODE_GETCONNECTOR: the first call probes it)."
	^self with: 80 do: [:c | | nModes nEncoders modesAt encodersAt |
		Machine uint32At: c + 48 put: id.
		self ioctl: 16rC05064A7 at: c.
		nModes := Machine uint32At: c + 32.
		nEncoders := Machine uint32At: c + 40.
		((Machine uint32At: c + 60) = 1 and: [nModes > 0])
			ifFalse: [nil]
			ifTrue: [
				modesAt := Machine allocate: nModes * 68.
				encodersAt := Machine allocate: (nEncoders max: 1) * 4.
				[Machine bytesAt: c put: (ByteArray new: 80).
				Machine uint64At: c put: encodersAt; uint64At: c + 8 put: modesAt; uint32At: c + 32 put: nModes; uint32At: c + 40 put: nEncoders; uint32At: c + 48 put: id.
				self ioctl: 16rC05064A7 at: c.
				nModes := nModes min: (Machine uint32At: c + 32).
				nEncoders := nEncoders min: (Machine uint32At: c + 40).
				{(1 to: nModes) collect: [:i | Machine bytesAt: modesAt + (i - 1 * 68) count: 68].
				 Machine uint32At: c + 44.
				 (1 to: nEncoders) collect: [:i | Machine uint32At: encodersAt + (i - 1 * 4)]}]
					ensure: [Machine free: modesAt. Machine free: encodersAt]]]
!
encoder: id
	"{the CRTC it drives (0: none). the CRTCs it can drive, a bit each in the resources' order} (DRM_IOCTL_MODE_GETENCODER)."
	^self with: 20 do: [:e |
		Machine uint32At: e put: id.
		self ioctl: 16rC01464A6 at: e.
		{Machine uint32At: e + 8. Machine uint32At: e + 12}]
!
crtcFor: info crtcs: crtcIds
	"The CRTC the connector's encoder drives now, else the first one an encoder of it can drive; nil if none."
	(info at: 2) = 0 ifFalse: [
		(self encoder: (info at: 2)) ifNotNil: [:e | e first = 0 ifFalse: [^e first]]].
	(info at: 3) do: [:id | | e |
		e := self encoder: id.
		crtcIds doWithIndex: [:c :i | ((e last bitShift: 1 - i) bitAnd: 1) = 1 ifTrue: [^c]]].
	^nil
! !

!KmsScreen class methodsFor: 'instance creation'!
path: aPath
	^self new setPath: aPath
!
inMemory: anExtent
	"A screen of anExtent in memory, as if a device had that mode (SAMALTAK_SCREEN=memory: tests)."
	^(self path: 'memory') setOffscreen: anExtent; yourself
!
choose: paths
	"The screen of the first of paths (DRM devices) with a connected output, preferring a real driver to simpledrm (the firmware's framebuffer, until a driver takes over); the others closed. nil if none: failures says why."
	| probed best |
	probed := paths collect: [:p | self path: p].
	probed := probed select: [:s | s probe].
	best := probed detect: [:s | s driver ~= 'simpledrm'] ifNone: [probed isEmpty ifTrue: [nil] ifFalse: [probed first]].
	probed do: [:s | s == best ifFalse: [s closeDevice]].
	^best
! !

!KmsScreen class methodsFor: 'bytes'!
u16: bytes at: offset
	"The little-endian uint16 at the 0-based offset of bytes."
	^(bytes at: offset + 1) + ((bytes at: offset + 2) bitShift: 8)
!
u32: bytes at: offset
	^(self u16: bytes at: offset) + ((self u16: bytes at: offset + 2) bitShift: 16)
! !
