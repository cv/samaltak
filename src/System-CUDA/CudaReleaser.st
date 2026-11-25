Object subclass: #CudaReleaser
	instanceVariableNames: 'kind value session'
	classVariableNames: ''
	package: 'System-CUDA'!

CudaReleaser comment: 'I free the device memory or destroy the handle of a CUDA object that was garbage collected unreleased (WeakRegistry default): kind #memory (cudaFree), #event, #stream, #fftPlan (cufftDestroy). I hold the address or handle and its session, never the object; one of an earlier VM process is gone already and left alone.'!

!CudaReleaser class methodsFor: 'instance creation'!
kind: aSymbol value: anInteger session: aSession
	^self new setKind: aSymbol value: anInteger session: aSession
! !

!CudaReleaser methodsFor: 'finalization'!
setKind: aSymbol value: anInteger session: aSession
	kind := aSymbol.
	value := anInteger.
	session := aSession
!
finalize
	(value notNil and: [session = CudaLibraryAPI session]) ifTrue: [
		[kind == #memory ifTrue: [CudaRuntimeAPI cudaFree: value].
		kind == #event ifTrue: [CudaRuntimeAPI cudaEventDestroy: value].
		kind == #stream ifTrue: [CudaRuntimeAPI cudaStreamDestroy: value].
		kind == #fftPlan ifTrue: [CufftAPI cufftDestroy: value]]
			on: CudaError do: [:e | nil]].
	value := nil
! !
