Object subclass: #PlatformPrims
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Platform-Tests'!

!PlatformPrims class methodsFor: 'input'!
nextEvent: array
	^GPUPrimitives nextEvent: array
!
injectEvent: array
	^[GPUPrimitives injectEvent: array] on: GPUError do: [:e | #failed]
!
inputSemaphore: index
	^GPUPrimitives inputSemaphore: index
!
lastError
	^GPUPrimitives lastError
!
windowOpen: w h: h title: t flags: f
	^GPUPrimitives openWindow: w height: h title: t flags: f
!
windowSize: win
	^GPUPrimitives windowSize: win
!
windowClose: win
	^GPUPrimitives closeWindow: win
! !

!PlatformPrims class methodsFor: 'files'!
fileOpen: path mode: m
	^(File primOpen: path mode: m) ifNil: [#failed]
!
fileRead: f into: b start: s count: n
	^File primRead: f into: b startingAt: s count: n
!
fileWrite: f from: b start: s count: n
	^File primWrite: f from: b startingAt: s count: n
!
fileSeek: f to: pos
	^File primSeek: f to: pos
!
fileClose: f
	^File primClose: f
!
fileStat: path
	^File stat: path
!
fileDelete: path
	^File delete: path
! !

!PlatformPrims class methodsFor: 'sockets'!
socketListen: host port: p backlog: b
	^RemoteSocket primListen: host port: p backlog: b
!
socketConnect: host port: p
	^RemoteSocket primConnect: host port: p
!
socketAccept: s
	^RemoteSocket primAccept: s
!
socketRecv: s into: b start: st count: n
	^RemoteSocket primRecv: s into: b start: st count: n
!
socketSend: s from: b start: st count: n
	^RemoteSocket primSend: s from: b start: st count: n
!
socketClose: s
	^RemoteSocket primClose: s
!
socketSemaphore: s read: i
	^RemoteSocket primSemaphore: s read: i write: 0
!
socketLocalPort: s
	^RemoteSocket primLocalPort: s
! !

!PlatformPrims class methodsFor: 'gpu'!
gpuCreateDevice: debug
	^GPUPrimitives createDevice: debug
!
gpuCreateTexture: dev w: w h: h format: f usage: u
	^GPUPrimitives createTexture: dev width: w height: h format: f usage: u
!
gpuAcquireCommandBuffer: dev
	^GPUPrimitives acquireCommandBuffer: dev
!
gpuBeginPass: cmd target: tex clear: rgba
	^GPUPrimitives beginPass: cmd target: tex clear: rgba
!
gpuEndPass: pass
	^GPUPrimitives endPass: pass
!
gpuSubmit: cmd fence: aBoolean
	^GPUPrimitives submit: cmd fence: aBoolean
!
gpuWaitFence: f
	^GPUPrimitives waitFence: f
!
gpuDownload: tex x: x y: y w: w h: h into: bytes
	^[GPUPrimitives download: tex x: x y: y width: w height: h into: bytes] on: GPUError do: [:e | #failed]
!
gpuRelease: h
	^GPUPrimitives release: h
! !
