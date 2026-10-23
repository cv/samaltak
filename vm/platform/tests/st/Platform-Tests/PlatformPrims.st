Object subclass: #PlatformPrims
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Platform-Tests'!

!PlatformPrims class methodsFor: 'input'!
nextEvent: anArray
	<primitive: 'nextEvent'>
	^#failed
!
injectEvent: anArray
	<primitive: 'injectEvent'>
	^#failed
!
inputSemaphore: index
	<primitive: 'inputSemaphore'>
	^#failed
!
lastError
	<primitive: 'platformLastError'>
	^#failed
!
windowOpen: w h: h title: t flags: f
	<primitive: 'windowOpen'>
	^#failed
!
windowSize: win
	<primitive: 'windowSize'>
	^#failed
!
windowClose: win
	<primitive: 'windowClose'>
	^#failed
! !

!PlatformPrims class methodsFor: 'files'!
fileOpen: path mode: m
	<primitive: 'fileOpen'>
	^#failed
!
fileRead: f into: b start: s count: n
	<primitive: 'fileRead'>
	^#failed
!
fileWrite: f from: b start: s count: n
	<primitive: 'fileWrite'>
	^#failed
!
fileSeek: f to: pos
	<primitive: 'fileSeek'>
	^#failed
!
fileClose: f
	<primitive: 'fileClose'>
	^#failed
!
fileStat: path
	<primitive: 'fileStat'>
	^#failed
!
fileDelete: path
	<primitive: 'fileDelete'>
	^#failed
! !

!PlatformPrims class methodsFor: 'sockets'!
socketListen: host port: p backlog: b
	<primitive: 'socketListen'>
	^#failed
!
socketConnect: host port: p
	<primitive: 'socketConnect'>
	^#failed
!
socketAccept: s
	<primitive: 'socketAccept'>
	^#failed
!
socketRecv: s into: b start: st count: n
	<primitive: 'socketRecv'>
	^#failed
!
socketSend: s from: b start: st count: n
	<primitive: 'socketSend'>
	^#failed
!
socketClose: s
	<primitive: 'socketClose'>
	^#failed
!
socketSemaphore: s read: i
	<primitive: 'socketSemaphore'>
	^#failed
!
socketLocalPort: s
	<primitive: 'socketLocalPort'>
	^#failed
! !

!PlatformPrims class methodsFor: 'gpu'!
gpuCreateDevice: debug
	<primitive: 'gpuCreateDevice'>
	^#failed
!
gpuCreateTexture: dev w: w h: h format: f usage: u
	<primitive: 'gpuCreateTexture'>
	^#failed
!
gpuAcquireCommandBuffer: dev
	<primitive: 'gpuAcquireCommandBuffer'>
	^#failed
!
gpuBeginPass: cmd target: tex clear: rgba
	<primitive: 'gpuBeginPass'>
	^#failed
!
gpuEndPass: pass
	<primitive: 'gpuEndPass'>
	^#failed
!
gpuSubmit: cmd fence: aBoolean
	<primitive: 'gpuSubmit'>
	^#failed
!
gpuWaitFence: f
	<primitive: 'gpuWaitFence'>
	^#failed
!
gpuDownload: tex x: x y: y w: w h: h into: bytes
	<primitive: 'gpuDownload'>
	^#failed
!
gpuRelease: h
	<primitive: 'gpuRelease'>
	^#failed
! !
