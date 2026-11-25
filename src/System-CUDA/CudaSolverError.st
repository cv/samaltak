CudaError subclass: #CudaSolverError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-CUDA'!

CudaSolverError comment: 'I am signaled when a cuSOLVER routine succeeded as a call but reports in its devInfo that it could not do its job: code is devInfo, function the routine, and messageText says what the library documents devInfo to mean there (a negative one: the parameter of that number was wrong). Subclasses: CudaSingularMatrix (getrf: U(i, i) is exactly zero), CudaNotPositiveDefinite (potrf: the leading minor of order i is not positive definite). gesvd and syevd not converging are CudaSolverErrors.'!

!CudaSolverError class methodsFor: 'signalling'!
check: infoArray in: functionName
	"Read devInfo back from the device (a 1-element #int32 CudaArray) and signal what it means if it is not 0; answer it."
	| v |
	v := infoArray at: 1.
	v = 0 ifTrue: [^0].
	^self signalInfo: v in: functionName
!
signalInfo: anInteger in: functionName
	| class |
	class := self.
	(self == CudaSolverError and: [anInteger > 0]) ifTrue: [
		('*getrf' match: functionName) ifTrue: [class := CudaSingularMatrix].
		('*potrf' match: functionName) ifTrue: [class := CudaNotPositiveDefinite]].
	^(class library: CusolverAPI function: functionName code: anInteger) signal
! !

!CudaSolverError methodsFor: 'accessing'!
devInfo
	^code
!
statusName
	^nil
!
meaning
	"What cuSOLVER's documentation says devInfo means for my routine."
	code < 0 ifTrue: [^'parameter ' , code negated printString , ' is wrong'].
	('*getrf' match: function) ifTrue: [^'the matrix is singular: U(' , code printString , ',' , code printString , ') is exactly zero'].
	('*potrf' match: function) ifTrue: [^'the matrix is not positive definite: its leading minor of order ' , code printString , ' is not'].
	('*gesvd' match: function) ifTrue: [^'no convergence: ' , code printString , ' superdiagonals of an intermediate bidiagonal form did not converge to zero'].
	('*syevd' match: function) ifTrue: [^'no convergence: ' , code printString , ' off-diagonal elements of an intermediate tridiagonal form did not converge to zero'].
	^'the routine failed'
!
messageText
	messageText notNil ifTrue: [^messageText].
	^function , ': ' , self meaning , ' (devInfo ' , code printString , ')'
! !
