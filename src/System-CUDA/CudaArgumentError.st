CudaError subclass: #CudaArgumentError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-CUDA'!

CudaArgumentError comment: 'I am signaled when the VM refuses a CUDA call''s arguments before making it (vm/native/cudalib.h): a handle that is not a live one of its type, a device pointer outside the live allocations or an extent past the end of one (a matrix''s leading dimension times its columns), a host ByteArray too short for the count, a table full. code is the VM''s rejection (-3 to -7), not a library status.'!
