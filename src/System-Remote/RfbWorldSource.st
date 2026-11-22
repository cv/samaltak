RfbFrameSource subclass: #RfbWorldSource
	instanceVariableNames: 'poller lastCount lastExtent form formCount'
	classVariableNames: ''
	package: 'System-Remote'!

RfbWorldSource comment: 'I am the World''s screen for an RFB server, read through its compositor (UI-Windows, reached late-bound: it is on a higher layer): its size in device pixels, its pixels from a screenshot (Compositor>>screenshotScale:, kept while no frame was presented since) and, while anyone listens, the whole screen as damage whenever the compositor presented a frame (its presentedCount, looked at every pollMs). A stand-in until the frame tap feeds the compositor''s and the firmware screen''s own damage and pixels: it serves the right pixels, but every change costs a full update.'!

!RfbWorldSource methodsFor: 'screen'!
world
	^(Smalltalk at: #World ifAbsent: [nil]) ifNotNil: [:w | w current]
!
extent
	| w |
	w := self world.
	(w isNil or: [w compositor isNil]) ifTrue: [^nil].
	^(w extent * w displayScale) rounded
!
bgraOf: aRectangle
	| f out w bits |
	f := self currentForm.
	w := aRectangle width.
	out := ByteArray new: w * aRectangle height * 4.
	f isNil ifTrue: [^out].
	bits := f bits.
	0 to: aRectangle height - 1 do: [:y |
		out replaceFrom: y * w * 4 + 1 to: y + 1 * w * 4
			withRawBytesOf: bits startingAt: (aRectangle top + y) * f width + aRectangle left * 4 + 1].
	^self swapRedBlue: out
!
currentForm
	"A screenshot of the World (without the remote pointer), again only once the compositor presented another frame."
	| w count |
	w := self world.
	(w isNil or: [w compositor isNil]) ifTrue: [^nil].
	count := w compositor presentedCount.
	(form notNil and: [formCount = count and: [form width @ form height = self extent]]) ifTrue: [^form].
	form := w compositor sync: [:c | c screenshotScale: w displayScale].
	formCount := count.
	^form
!
swapRedBlue: bytes
	"RGBA (the Form's order) to BGRA, in place."
	| n |
	n := bytes size // 4.
	([SoftwareRaster copy: bytes stride: n * 4 from: bytes stride: n * 4 width: n height: 1 bytesPerPixel: 4 mode: 1. true]
		on: Error do: [:e | e return: false]) ifTrue: [^bytes].
	0 to: n - 1 do: [:i | | r |
		r := bytes at: i * 4 + 1.
		bytes at: i * 4 + 1 put: (bytes at: i * 4 + 3).
		bytes at: i * 4 + 3 put: r].
	^bytes
!
pointScale
	^self world ifNil: [1] ifNotNil: [:w | w displayScale]
! !

!RfbWorldSource methodsFor: 'watching'!
pollMs
	^30
!
attached
	(poller isNil or: [poller isTerminated]) ifFalse: [^self].
	poller := [self poll] forkAt: Processor userSchedulingPriority + 5 named: 'rfb world source'
!
detachedAll
	| p |
	p := poller.
	poller := nil.
	(p notNil and: [p isActiveProcess not]) ifTrue: [p terminate]
!
poll
	[self listeners notEmpty] whileTrue: [
		self check.
		(Delay forMilliseconds: self pollMs) wait].
	poller := nil
!
check
	| w count e |
	w := self world.
	(w isNil or: [w compositor isNil]) ifTrue: [^self].
	e := self extent.
	e = lastExtent ifFalse: [
		lastExtent isNil ifFalse: [self notify: [:each | each resized: e]].
		lastExtent := e].
	count := w compositor presentedCount.
	count = lastCount ifTrue: [^self].
	lastCount := count.
	self notify: [:each | each damagedAll]
! !
