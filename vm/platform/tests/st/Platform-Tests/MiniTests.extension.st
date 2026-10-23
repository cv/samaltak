!MiniTests methodsFor: 'platform'!
testPlatform
	| P buf ev sem path f b srv cli con port sem2 sem3 dev tex cmd pass fence px win |
	P := PlatformPrims.
	buf := Array new: 8.
	(P nextEvent: buf) printNl.
	sem := Semaphore new.
	Smalltalk registerExternal: sem at: 3.
	P inputSemaphore: 3.
	P injectEvent: {7. nil. 1.5. 2. 0. 8. 'hello'. nil}.
	P injectEvent: {4. 5. 10. 20. 0. 0. 3 @ -1. 1}.
	sem wait.
	ev := P nextEvent: buf.
	(ev at: 1) printNl.
	(ev at: 3) printNl.
	(ev at: 6) printNl.
	(ev at: 7) displayNl.
	ev := P nextEvent: buf.
	(ev at: 2) printNl.
	(ev at: 7) x printNl.
	(ev at: 7) y printNl.
	(ev at: 8) printNl.
	(P nextEvent: buf) printNl.
	(P injectEvent: #(1 2)) printNl.
	P inputSemaphore: 0.

	path := '/tmp/samaltak-platform-st-test.txt'.
	f := P fileOpen: path mode: 3.
	(P fileWrite: f from: 'hello world' start: 1 count: 11) printNl.
	P fileSeek: f to: 6.
	b := ByteArray new: 5.
	(P fileRead: f into: b start: 1 count: 5) printNl.
	b printNl.
	P fileClose: f.
	((P fileStat: path) at: 3) printNl.
	P fileDelete: path.
	((P fileStat: path) at: 1) printNl.
	(P fileOpen: path mode: 0) printNl.
	P lastError displayNl.

	srv := P socketListen: '127.0.0.1' port: 0 backlog: 4.
	port := P socketLocalPort: srv.
	(port > 0) printNl.
	sem2 := Semaphore new.
	Smalltalk registerExternal: sem2 at: 4.
	P socketSemaphore: srv read: 4.
	(P socketAccept: srv) printNl.
	cli := P socketConnect: '127.0.0.1' port: port.
	sem2 wait.
	con := P socketAccept: srv.
	con isNil printNl.
	sem3 := Semaphore new.
	Smalltalk registerExternal: sem3 at: 5.
	P socketSemaphore: con read: 5.
	(P socketRecv: con into: b start: 1 count: 5) printNl.
	(P socketSend: cli from: 'ping' start: 1 count: 4) printNl.
	sem3 wait.
	(P socketRecv: con into: b start: 2 count: 4) printNl.
	b printNl.
	P socketClose: cli.
	sem3 wait.
	(P socketRecv: con into: b start: 1 count: 5) printNl.
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
	(px at: 1) printNl.
	(px at: 2) printNl.
	((px at: 3) between: 127 and: 128) printNl.
	(px at: 128) printNl.
	(P gpuDownload: tex x: 0 y: 0 w: 9 h: 4 into: px) printNl.
	win := P windowOpen: 400 h: 300 title: 'samaltak test' flags: 5.
	(P windowSize: win) printNl.
	P windowClose: win.
	P gpuRelease: dev
! !
