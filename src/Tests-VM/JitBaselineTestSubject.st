Object subclass: #JitBaselineTestSubject
	instanceVariableNames: 'a b block'
	classVariableNames: ''
	package: 'Tests-VM'!

JitBaselineTestSubject comment: 'JitBaselineTest compiles methods into me (and into my subclass JitBaselineTestOther); it removes them again. An instance with a block evaluates it when it is added to (+), as a way to run Smalltalk in the middle of an arithmetic slow path.'!

!JitBaselineTestSubject methodsFor: 'accessing'!
block: aBlock
	block := aBlock
!
+ aNumber
	block value.
	^aNumber
! !
