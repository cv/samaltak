Object subclass: #UIRemote
	instanceVariableNames: ''
	classVariableNames: 'IdleCondition StateProvider FrameWaits'
	package: 'UI-Windows'!

UIRemote comment: 'I connect the window system to remote control (System-Remote): the World is the snapshot root, my pointResolver maps refs to screen points (raising a covered window), the World being settled is an idle condition, and I register the screenshot and record commands and the frames wait condition.

	screenshot {path, target?, scale?, pointer?}   PNG of the screen (with the remote pointer only if pointer: true), a window''s layer or a widget''s part of it, at scale 1 or 2 (default: the display scale)
	record {action: start, path: fifo, w, h, fps} / {action: stop}   raw RGBA frames, downsampled on the GPU, written to a FIFO (ffmpeg -f rawvideo -pix_fmt rgba -s WxH -r FPS -i fifo ...)
	wait {frames: n}                    until n more frames were presented'!

!UIRemote class methodsFor: 'installing'!
installOn: aWorld
	RemoteControl root: [World current].
	RemoteControl pointResolver: [:node | self pointFor: node].
	RemoteControl registerCommand: 'screenshot' handler: [:r | self screenshot: r].
	RemoteControl registerCommand: 'record' handler: [:r | self record: r].
	IdleCondition isNil ifTrue: [
		IdleCondition := [World current isNil or: [World current isSettled]].
		RemoteControl addIdleCondition: IdleCondition].
	StateProvider isNil ifTrue: [
		StateProvider := [:d | self addStateTo: d].
		RemoteControl addStateProvider: StateProvider].
	FrameWaits := IdentityDictionary new.
	RemoteControl registerWaitCondition: 'frames' with: [:n :r | self frames: n for: r].
	"Remote control is an input device: the input dispatcher serves its sockets."
	(ControlServer current notNil and: [aWorld dispatcher notNil]) ifTrue: [aWorld dispatcher addService: ControlServer current].
	RemoteInputDevice default windowId: aWorld displayWindow windowId.
	RemoteInputDevice default pointer isNil ifTrue: [RemoteInputDevice default pointer: aWorld extent / 2].
	aWorld remotePointer ignore: RemoteInputDevice default pointer
!
uninstall
	(ControlServer current notNil and: [World current notNil and: [World current dispatcher notNil]])
		ifTrue: [World current dispatcher removeService: ControlServer current].
	IdleCondition isNil ifFalse: [RemoteControl removeIdleCondition: IdleCondition].
	StateProvider isNil ifFalse: [RemoteControl removeStateProvider: StateProvider].
	IdleCondition := nil.
	StateProvider := nil.
	RemoteControl unregisterWaitCondition: 'frames'.
	RemoteControl unregisterCommand: 'screenshot'.
	RemoteControl unregisterCommand: 'record'.
	RemoteControl pointResolver: nil.
	RemoteControl root: nil
! !

!UIRemote class methodsFor: 'resolving'!
pointFor: aNode
	"The screen point where input aimed at aNode lands, or nil if it cannot be hit; raises a covered window."
	| widget window point world |
	world := World current.
	widget := aNode widget.
	point := (widget respondsTo: #remoteClickPoint)
		ifTrue: [widget remoteClickPoint]
		ifFalse: [aNode bounds isNil ifFalse: [aNode bounds center]].
	point isNil ifTrue: [^nil].
	(world isNil or: [(world bounds containsPoint: point) not]) ifTrue: [^nil].
	window := self windowOf: aNode.
	(window isNil or: [window isOverlay]) ifTrue: [^point].
	(window isCollapsed and: [(widget isKindOf: WindowControl) not and: [widget ~~ window]]) ifTrue: [^nil].
	(world windowAt: point) == window ifFalse: [
		world activate: window.
		"In the input dispatcher (it hosts remote control) do not wait: the pointer's travel to the point takes frames anyway."
		(world dispatcher notNil and: [world dispatcher process == Processor activeProcess]) ifFalse: [world waitForFrames: 1]].
	^point
!
windowOf: aNode
	| n |
	n := aNode.
	[n notNil] whileTrue: [
		(n widget isWindow) ifTrue: [^n widget].
		(n widget isKindOf: WindowControl) ifTrue: [^n widget window].
		n := n parent].
	^nil
! !

!UIRemote class methodsFor: 'commands'!
screenshot: aRequest
	"Write a PNG; answer its path and pixel size."
	| world path scale target node widget form rect |
	world := World current.
	world isNil ifTrue: [^RemoteError signal: 'screenshot: no World is running'].
	path := aRequest stringAt: 'path'.
	path isNil ifTrue: [^RemoteError signal: 'screenshot: missing path'].
	scale := aRequest numberAt: 'scale' ifAbsent: [world displayScale].
	(aRequest booleanAt: 'now') ifFalse: [world waitUntilSettled: 1000].
	target := aRequest at: 'target'.
	form := target isNil
		ifTrue: [world compositor sync: [:c | c screenshotScale: scale pointer: (aRequest booleanAt: 'pointer')]]
		ifFalse: [
			node := RemoteControl snapshot resolveOrFail: target.
			widget := node widget.
			(widget isKindOf: WindowControl) ifTrue: [widget := widget window].
			(widget isWindow or: [widget isView and: [widget window notNil]])
				ifTrue: [world compositor sync: [:c | c screenshotOf: widget scale: scale]]
				ifFalse: [
					rect := node bounds ifNil: [^RemoteError signal: node atRef, ' has no bounds'].
					world compositor sync: [:c | c screenshotRect: rect scale: scale]]].
	PNGWriter write: form to: path.
	^Dictionary new
		at: 'path' put: path;
		at: 'w' put: form width;
		at: 'h' put: form height;
		yourself
!
record: aRequest
	| world action recorder |
	world := World current.
	world isNil ifTrue: [^RemoteError signal: 'record: no World is running'].
	action := (aRequest at: 'action') ifNil: ['start'].
	action = 'stop' ifTrue: [
		recorder := world compositor recorder.
		recorder isNil ifTrue: [^RemoteError signal: 'record: not recording'].
		world compositor recorder: nil.
		recorder stop.
		^Dictionary new at: 'frames' put: recorder framesWritten; at: 'captured' put: recorder framesCaptured; yourself].
	action = 'start' ifFalse: [^RemoteError signal: 'record: action must be start or stop'].
	world compositor recorder isNil ifFalse: [^RemoteError signal: 'record: already recording'].
	recorder := FrameRecorder
		path: (aRequest stringAt: 'path')
		width: (aRequest numberAt: 'w' ifAbsent: [world extent x rounded])
		height: (aRequest numberAt: 'h' ifAbsent: [world extent y rounded])
		fps: (aRequest numberAt: 'fps' ifAbsent: [30]).
	recorder start.
	world compositor recorder: recorder.
	^Dictionary new at: 'recording' put: true; at: 'w' put: recorder width; at: 'h' put: recorder height; at: 'fps' put: recorder fps; yourself
!
frames: n for: aRequest
	| world start |
	world := World current.
	world isNil ifTrue: [^true].
	start := FrameWaits at: aRequest ifAbsent: [FrameWaits at: aRequest put: world compositor frameCount].
	world changed.
	world compositor frameCount >= (start + n) ifFalse: [^false].
	FrameWaits removeKey: aRequest ifAbsent: [].
	^true
!
addStateTo: aDictionary
	| world |
	world := World current.
	world isNil ifTrue: [^self].
	aDictionary at: 'theme' put: 'blue-book'.
	aDictionary at: 'screen' put: (Dictionary new at: 'w' put: world extent x rounded; at: 'h' put: world extent y rounded; at: 'scale' put: world displayScale; yourself).
	aDictionary at: 'focus' put: (world activeWindow isNil ifFalse: ['@', world activeWindow remoteName]).
	aDictionary at: 'frames' put: world compositor frameCount.
	aDictionary at: 'compositor' put: world topBar statsText
! !
