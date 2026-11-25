CudaError subclass: #CudaUnavailable
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-CUDA'!

CudaUnavailable comment: 'I am signaled when a CUDA library is not here: the VM has no cuda_* exports (UEFI, an older VM), or the library could not be loaded (not installed; SAMALTAK_CUDA_LIBS names more directories to look in), or it lacks the function.'!
