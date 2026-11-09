Object subclass: #TenureRun
	instanceVariableNames: 'age points fullGCs firstFullGCs'
	classVariableNames: ''
	package: 'Tools'!

TenureRun comment: 'I am one run of the Tenure Test: the VM''s TENURE_AGE, and old space (MB, against seconds since the run began) as it was sampled, with the sample index of each full GC.'!

!TenureRun methodsFor: 'initialization'!
setAge: anInteger
	age := anInteger.
	points := OrderedCollection new.
	fullGCs := OrderedCollection new
! !

!TenureRun methodsFor: 'accessing'!
age
	^age
!
points
	"seconds @ MB of old space, oldest first."
	^points
!
fullGCs
	"The indices in points of the full GCs."
	^fullGCs
!
addSeconds: seconds old: oldBytes fullGCs: fullGCCount
	"A sample of the counters; a full GC since the last one is marked on it."
	firstFullGCs isNil ifTrue: [firstFullGCs := fullGCCount].
	fullGCCount - firstFullGCs > fullGCs size ifTrue: [fullGCs add: points size + 1].
	points add: seconds @ (oldBytes / 1048576.0)
!
summary
	"What old space did, as read off the lane's header."
	points isEmpty ifTrue: [^''].
	^'old space ' , points first y rounded printString , ' → ' , points last y rounded printString , ' MB   ·   ' ,
		fullGCs size printString , ' full GC' , (fullGCs size = 1 ifTrue: [''] ifFalse: ['s'])
! !
