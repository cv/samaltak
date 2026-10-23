Object subclass: #ProfileMark
	instanceVariableNames: 'label time process'
	classVariableNames: ''
	package: 'System-Profiling'!

ProfileMark comment: 'I am a labelled point in time (microsecond clock) dropped into the profile with Profiler mark: ''label''; the timeline shows me and the next FrameRecord lists me.'!

!ProfileMark methodsFor: 'accessing'!
label
	^label
!
time
	^time
!
process
	"Answer the Process that dropped me."
	^process
! !

!ProfileMark methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a ProfileMark('; print: label; nextPut: $)
! !

!ProfileMark methodsFor: 'private'!
setLabel: aString time: microseconds process: aProcess
	label := aString.
	time := microseconds.
	process := aProcess
! !

!ProfileMark class methodsFor: 'instance creation'!
label: aString time: microseconds process: aProcess
	^self new setLabel: aString time: microseconds process: aProcess
! !
