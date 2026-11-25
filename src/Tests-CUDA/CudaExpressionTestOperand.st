Object subclass: #CudaExpressionTestOperand
	instanceVariableNames: 'type elementShape'
	classVariableNames: ''
	package: 'Tests-CUDA'!

CudaExpressionTestOperand comment: 'A stand-in for a CudaArray in CudaExpressionTest: a type and an elementShape, no device memory.'!

!CudaExpressionTestOperand class methodsFor: 'instance creation'!
type: aSymbol shape: anArray
	^self new setType: aSymbol shape: anArray
! !

!CudaExpressionTestOperand methodsFor: 'accessing'!
setType: aSymbol shape: anArray
	type := aSymbol.
	elementShape := anArray
!
type
	^type
!
elementShape
	^elementShape
! !
