CudaSolverError subclass: #CudaNotPositiveDefinite
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-CUDA'!

CudaNotPositiveDefinite comment: 'I am signaled when a Cholesky factorization (cuSOLVER potrf) finds the matrix not positive definite: devInfo i > 0, the leading minor of order i is not.'!
