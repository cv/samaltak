Exception subclass: #Warning
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

Warning comment: 'I warn about a questionable situation. Unhandled, I report myself (Transcript or a notifier) and resume with nil.'!

!Warning methodsFor: 'exception description'!
defaultAction
	^Smalltalk handleWarning: self
! !
