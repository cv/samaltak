VMPlatformModule subclass: #PlatformVsync
	instanceVariableNames: 'displayLink pending vsyncSem'
	classVariableNames: ''
	package: 'VM-Platform'!

PlatformVsync comment: 'The display-refresh semaphore: a CVDisplayLink thread flags each refresh; the next platform_poll signals the semaphore (the compositor''s frame clock). Signaled at most once per poll, so a late compositor skips refreshes.'!

!PlatformVsync class methodsFor: 'declaring'!
cPreamble
	"CVDisplayLink is deprecated (CADisplayLink needs a view)."
	^'#pragma clang diagnostic ignored "-Wdeprecated-declarations"'
!
declarations
	^#((displayLink CVDisplayLinkRef) (pending atomic_int) (vsyncSem int32_t))
! !

!PlatformVsync methodsFor: 'vsync'!
onRefresh: link now: now output: outputTime flags: flagsIn flagsOut: flagsOut context: context
	"The display link's thread: flag the refresh, wake the VM once."
	<c: 'CVReturn on_refresh(CVDisplayLinkRef link, const CVTimeStamp *now, const CVTimeStamp *output_time, CVOptionFlags flags_in, CVOptionFlags *flags_out, void *context)'>
	(self atomicExchange: #pending value: 1) = 0 ifTrue: [
		scheduler requestInterruptCheck.
		sdlPlatform wake].
	^coreVideo kCVReturnSuccess
!
semaphore: index
	"Signal external semaphore index once per display refresh; 0 = stop."
	<c: 'bool pf_vsync_semaphore(int index)'>
	<export>
	| link |
	platform init.
	vsyncSem := index.
	(index ~= 0 and: [displayLink isNull]) ifTrue: [
		link := self local: 'CVDisplayLinkRef'.
		(coreVideo createWithActiveCGDisplays: link) ~= coreVideo kCVReturnSuccess ifTrue: [
			common setError: 'CVDisplayLinkCreateWithActiveCGDisplays failed'.
			^false].
		displayLink := link value.
		coreVideo setOutputCallback: displayLink callback: (self functionPointer: #onRefresh:now:output:flags:flagsOut:context:) userInfo: self null.
		coreVideo start: displayLink.
		^true].
	(index = 0 and: [displayLink notNull]) ifTrue: [
		coreVideo stop: displayLink.
		coreVideo release: displayLink.
		displayLink := self null].
	^true
!
poll
	<c: 'void pf_vsync_poll(void)'>
	(vsyncSem ~= 0 and: [(self atomicExchange: #pending value: 0) ~= 0]) ifTrue: [
		scheduler signalExternalSemaphore: vsyncSem]
!
pending
	<c: 'bool pf_vsync_pending(void)'>
	^vsyncSem ~= 0 and: [(self atomicLoad: #pending) ~= 0]
! !
