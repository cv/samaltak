CudaSolverError subclass: #CudaSingularMatrix
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-CUDA'!

CudaSingularMatrix comment: 'I am signaled when solving with, or inverting, a matrix whose LU factorization (cuSOLVER getrf) has an exactly zero pivot: devInfo i > 0, U(i, i) = 0, so the matrix is singular.'!
