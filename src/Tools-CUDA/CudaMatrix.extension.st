!CudaMatrix methodsFor: '*Tools-CUDA'!
inspectorForm
	"My heat map, for the Inspector (CudaHeatMap)."
	^self isAlive ifTrue: [CudaTrace quietly: [CudaHeatMap formOf: self]] ifFalse: [nil]
! !
