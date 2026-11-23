!PlatformPrims class methodsFor: 'platform'!
testPlatform
	| P buf ev sem path f b srv cli con port sem2 sem3 dev tex cmd pass fence px win i1 i2 i3 |
	P := PlatformPrims.
	buf := Array new: 8.
	self printLine: (P nextEvent: buf).
	sem := Semaphore new.
	i1 := Smalltalk vm registerExternalSemaphore: sem.
	P inputSemaphore: i1.
	P injectEvent: {7. nil. 1.5. 2. 0. 8. 'hello'. nil}.
	P injectEvent: {4. 5. 10. 20. 0. 0. 3 @ -1. 1}.
	sem wait.
	ev := P nextEvent: buf.
	self printLine: (ev at: 1).
	self printLine: (ev at: 3).
	self printLine: (ev at: 6).
	self displayLine: (ev at: 7).
	ev := P nextEvent: buf.
	self printLine: (ev at: 2).
	self printLine: (ev at: 7) x.
	self printLine: (ev at: 7) y.
	self printLine: (ev at: 8).
	self printLine: (P nextEvent: buf).
	self printLine: (P injectEvent: #(1 2)).
	P inputSemaphore: 0.

	path := '/tmp/samaltak-platform-st-test.txt'.
	f := P fileOpen: path mode: 3.
	self printLine: (P fileWrite: f from: 'hello world' start: 1 count: 11).
	P fileSeek: f to: 6.
	b := ByteArray new: 5.
	self printLine: (P fileRead: f into: b start: 1 count: 5).
	self printLine: b.
	P fileClose: f.
	self printLine: ((P fileStat: path) at: 3).
	P fileDelete: path.
	self printLine: ((P fileStat: path) at: 1).
	self printLine: (P fileOpen: path mode: 0).
	self displayLine: P lastError.

	srv := P socketListen: '127.0.0.1' port: 0 backlog: 4.
	port := P socketLocalPort: srv.
	self printLine: (port > 0).
	sem2 := Semaphore new.
	i2 := Smalltalk vm registerExternalSemaphore: sem2.
	P socketSemaphore: srv read: i2.
	self printLine: (P socketAccept: srv).
	cli := P socketConnect: '127.0.0.1' port: port.
	sem2 wait.
	con := P socketAccept: srv.
	self printLine: con isNil.
	sem3 := Semaphore new.
	i3 := Smalltalk vm registerExternalSemaphore: sem3.
	P socketSemaphore: con read: i3.
	self printLine: (P socketRecv: con into: b start: 1 count: 5).
	self printLine: (P socketSend: cli from: 'ping' start: 1 count: 4).
	sem3 wait.
	self printLine: (P socketRecv: con into: b start: 2 count: 4).
	self printLine: b.
	P socketClose: cli.
	sem3 wait.
	self printLine: (P socketRecv: con into: b start: 1 count: 5).
	P socketClose: con.
	P socketClose: srv.

	dev := P gpuCreateDevice: false.
	tex := P gpuCreateTexture: dev w: 8 h: 4 format: 2 usage: 3.
	cmd := P gpuAcquireCommandBuffer: dev.
	pass := P gpuBeginPass: cmd target: tex clear: {1. 0. 0.5. 1}.
	P gpuEndPass: pass.
	fence := P gpuSubmit: cmd fence: true.
	P gpuWaitFence: fence.
	P gpuRelease: fence.
	px := ByteArray new: 128.
	P gpuDownload: tex x: 0 y: 0 w: 8 h: 4 into: px.
	self printLine: (px at: 1).
	self printLine: (px at: 2).
	self printLine: ((px at: 3) between: 127 and: 128).
	self printLine: (px at: 128).
	self printLine: (P gpuDownload: tex x: 0 y: 0 w: 9 h: 4 into: px).
	win := P windowOpen: 400 h: 300 title: 'samaltak test' flags: 5.
	self printLine: (P windowSize: win).
	P windowClose: win.
	P gpuRelease: dev.
	{i1. i2. i3} do: [:i | Smalltalk vm unregisterExternalSemaphore: i]
!
printLine: object
	self displayLine: object printString
!
displayLine: string
	Smalltalk vm stdoutWrite: string, (String with: Character lf)
! !
