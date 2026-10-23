Object subclass: #CompilerTestSubject
	instanceVariableNames: 'a b c'
	classVariableNames: 'Shared'
	package: 'Tests-Compiler'!

CompilerTestSubject comment: 'I am the receiver class into which CompilerTest compiles and runs methods.'!

!CompilerTestSubject methodsFor: 'accessing'!
a
	^a
!
b
	^b
!
greeting
	^'hello'
! !
