Error subclass: #GPUError
	instanceVariableNames: 'operation platformLastError'
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPUError comment: 'I am signaled when a GPU or window primitive fails. I carry the failed operation and the platform''s own explanation (platformLastError), e.g. a Metal shader compile log.'!

!GPUError methodsFor: 'accessing'!
operation
	^operation
!
operation: aString
	operation := aString
!
platformLastError
	^platformLastError
!
platformLastError: aString
	platformLastError := aString
!
messageText
	^messageText ifNil: [
		(operation ifNil: ['GPU operation']), ' failed',
			((platformLastError isNil or: [platformLastError isEmpty])
				ifTrue: ['']
				ifFalse: [': ', platformLastError])]
! !
