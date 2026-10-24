CLibrary subclass: #CoreVideo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

CoreVideo comment: 'The CVDisplayLink functions of the vsync semaphore (deprecated in macOS 15, hence the pragma). Not simulated.

CVDisplayLink is deprecated; PlatformVsync, its only user, turns off the deprecation warnings.'!

!CoreVideo class methodsFor: 'declaring'!
headers
	^#('<CoreVideo/CoreVideo.h>')
!
typedefs
	^#((CVDisplayLinkRef 'void *') (CVReturn int32_t) (CVOptionFlags uint64_t) (CVTimeStamp opaque)
		(CVDisplayLinkOutputCallback 'CVReturn (*)(CVDisplayLinkRef, const CVTimeStamp *, const CVTimeStamp *, CVOptionFlags, CVOptionFlags *, void *)'))
! !

!CoreVideo methodsFor: 'simulation'!
notSimulated
	^self error: 'CoreVideo is not simulated'
! !

!CoreVideo methodsFor: 'display links'!
createWithActiveCGDisplays: displayLinkOut
	<c: 'CVReturn CVDisplayLinkCreateWithActiveCGDisplays(CVDisplayLinkRef *displayLinkOut)'>
	^self notSimulated
!
setOutputCallback: displayLink callback: callback userInfo: userInfo
	<c: 'CVReturn CVDisplayLinkSetOutputCallback(CVDisplayLinkRef displayLink, CVDisplayLinkOutputCallback callback, void *userInfo)'>
	^self notSimulated
!
start: displayLink
	<c: 'CVReturn CVDisplayLinkStart(CVDisplayLinkRef displayLink)'>
	^self notSimulated
!
stop: displayLink
	<c: 'CVReturn CVDisplayLinkStop(CVDisplayLinkRef displayLink)'>
	^self notSimulated
!
release: displayLink
	<c: 'void CVDisplayLinkRelease(CVDisplayLinkRef displayLink)'>
	^self notSimulated
!
kCVReturnSuccess
	<cMacro: 'CVReturn kCVReturnSuccess'>
	^self notSimulated
! !
