# The CUDA libraries and functions Samaltak binds (tools/cuda/bindgen.py; docs/cuda.md).
#
# Append only: each library's exports are numbered from its key (approvedFFI key = key + 2 + position; key + 0 and
# key + 1 are its availability and status text), and an approved export's ID is never reused. Add functions at the end
# of a library; to drop one, change "fn" to "retired" and keep the line.
#
#   lib NAME SmalltalkClass key K header H [include DIR...]  starts a library (headers from /usr/local/cuda/include)
#   soname S...        dlopen names, tried in SAMALTAK_CUDA_LIBS's directories, then plain, then /usr/local/cuda/lib64
#   status T           the status type the functions return (0 is success)
#   text F G           status name and description: functions of the status (const char * result or out-parameter)
#   text macros M...   or names from these macros
#   text enum E        or from the constants of enum E
#   handle T [null] [alias U]  an opaque handle type (kept in the VM's handle table; null: 0 means NULL; alias: the
#                      same type as U, declared before: CUstream is cudaStream_t)
#   pointers out|dev   what an unannotated T * means: an out-parameter, or a device pointer
#   constants P...     enum constants and integer macros (a trailing * matches a prefix) the class answers
#   fn F [as N] [ok C...] [pack] [param=role...]
#
# Roles: value (a const T * passed by value), out, dev[:EXTENT] (a device pointer in a live allocation, EXTENT elements
# from it; also a CUdeviceptr), devalloc:BYTES, devfree, in:COUNT / outarray:COUNT (a host ByteArray of at least COUNT
# elements), cstr (a String, copied and NUL-terminated), const:VALUE, null (a pointer passed as NULL), params
# (cuLaunchKernel's extra: a ByteArray, the kernel's parameter area), handleout[:TAG] (a new handle remembering the
# integer TAG), free[:T] (the handle is forgotten after the call, and with T the handles of type T whose TAG it is). require=EXPR: a condition the arguments must meet (checked last). Expressions are C over the other parameters, with TAG(h) (the tag of
# handle h), P(a) (host array a, checked before) and MAT(ld,rows,cols) (the extent of a column-major matrix).

lib cudart CudaRuntimeAPI key 805 header cuda_runtime_api.h
soname libcudart.so.13 libcudart.so.12 libcudart.so
status cudaError_t
text cudaGetErrorName cudaGetErrorString
handle cudaStream_t null
handle cudaEvent_t
pointers out
constants cudaSuccess cudaErrorNotReady cudaErrorMemoryAllocation cudaErrorInvalidValue cudaDevAttrMultiProcessorCount cudaDevAttrClockRate cudaDevAttrComputeCapabilityMajor cudaDevAttrComputeCapabilityMinor cudaDevAttrIntegrated cudaDevAttrConcurrentManagedAccess cudaDevAttrPageableMemoryAccess
fn cudaRuntimeGetVersion
fn cudaDriverGetVersion
fn cudaGetDeviceCount
fn cudaSetDevice
fn cudaGetDevice
fn cudaDeviceGetAttribute
fn cudaMemGetInfo
fn cudaDeviceSynchronize
fn cudaMalloc devPtr=devalloc:size
fn cudaFree devPtr=devfree
fn cudaMemcpy as cudaMemcpyHtoD dst=dev:count src=in:count kind=const:cudaMemcpyHostToDevice
fn cudaMemcpy as cudaMemcpyDtoH dst=outarray:count src=dev:count kind=const:cudaMemcpyDeviceToHost
fn cudaMemcpy as cudaMemcpyDtoD dst=dev:count src=dev:count kind=const:cudaMemcpyDeviceToDevice
fn cudaMemset devPtr=dev:count
fn cudaStreamCreate
fn cudaStreamDestroy stream=free
fn cudaStreamSynchronize
fn cudaStreamQuery ok cudaErrorNotReady
fn cudaEventCreate
fn cudaEventDestroy event=free
fn cudaEventRecord
fn cudaEventQuery ok cudaErrorNotReady
fn cudaEventSynchronize
fn cudaEventElapsedTime
fn cudaGetLastError
fn cudaPeekAtLastError
fn cudaMallocHost ptr=devalloc:size
fn cudaFreeHost ptr=devfree

lib driver CudaDriverAPI key 845 header cuda.h
soname libcuda.so.1 libcuda.so
status CUresult
text cuGetErrorName cuGetErrorString
pointers out
constants CU_DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT CU_DEVICE_ATTRIBUTE_CLOCK_RATE CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR CU_DEVICE_ATTRIBUTE_L2_CACHE_SIZE
fn cuInit
fn cuDriverGetVersion
fn cuDeviceGetCount
fn cuDeviceGet
fn cuDeviceGetName name=outarray:len
fn cuDeviceTotalMem
fn cuDeviceGetAttribute
handle CUmodule
handle CUfunction
handle CUstream null alias cudaStream_t
constants CU_FUNC_ATTRIBUTE_MAX_THREADS_PER_BLOCK CU_FUNC_ATTRIBUTE_SHARED_SIZE_BYTES CU_FUNC_ATTRIBUTE_LOCAL_SIZE_BYTES CU_FUNC_ATTRIBUTE_NUM_REGS
fn cuModuleLoadData image=in:l_image require=cudalib_module_image_ok(P(image),l_image)
fn cuModuleUnload hmod=free:CUfunction
fn cuModuleGetFunction hfunc=handleout:hmod
fn cuFuncGetAttribute
fn cuLaunchKernel kernelParams=null extra=params
fn cuStreamWriteValue64_v2 as cuStreamWriteValue64 addr=dev:1

lib cublas CublasAPI key 870 header cublas_v2.h
soname libcublas.so.13 libcublas.so.12 libcublas.so
status cublasStatus_t
text cublasGetStatusName cublasGetStatusString
handle cublasHandle_t
handle cudaStream_t null
pointers dev
constants CUBLAS_OP_N CUBLAS_OP_T CUBLAS_DEFAULT_MATH CUBLAS_TF32_TENSOR_OP_MATH CUBLAS_PEDANTIC_MATH CUBLAS_SIDE_LEFT CUBLAS_SIDE_RIGHT CUBLAS_FILL_MODE_LOWER CUBLAS_FILL_MODE_UPPER CUBLAS_DIAG_NON_UNIT CUBLAS_DIAG_UNIT
fn cublasCreate
fn cublasDestroy handle=free
fn cublasGetVersion version=out
fn cublasSetStream
fn cublasSetMathMode
fn cublasSgemm alpha=value beta=value A=dev:MAT(lda,transa==0?m:k,transa==0?k:m) B=dev:MAT(ldb,transb==0?k:n,transb==0?n:k) C=dev:MAT(ldc,m,n)
fn cublasDgemm alpha=value beta=value A=dev:MAT(lda,transa==0?m:k,transa==0?k:m) B=dev:MAT(ldb,transb==0?k:n,transb==0?n:k) C=dev:MAT(ldc,m,n)
fn cublasSnrm2 x=dev:MAT(incx,1,n) result=out
fn cublasDnrm2 x=dev:MAT(incx,1,n) result=out
fn cublasSaxpy alpha=value x=dev:MAT(incx,1,n) y=dev:MAT(incy,1,n)
fn cublasDaxpy alpha=value x=dev:MAT(incx,1,n) y=dev:MAT(incy,1,n)
fn cublasSgeam alpha=value beta=value A=dev:MAT(lda,transa==0?m:n,transa==0?n:m) B=dev:MAT(ldb,transb==0?m:n,transb==0?n:m) C=dev:MAT(ldc,m,n)
fn cublasDgeam alpha=value beta=value A=dev:MAT(lda,transa==0?m:n,transa==0?n:m) B=dev:MAT(ldb,transb==0?m:n,transb==0?n:m) C=dev:MAT(ldc,m,n)
fn cublasScopy x=dev:MAT(incx,1,n) y=dev:MAT(incy,1,n)
fn cublasDcopy x=dev:MAT(incx,1,n) y=dev:MAT(incy,1,n)
fn cublasStrmm alpha=value A=dev:MAT(lda,side==CUBLAS_SIDE_LEFT?m:n,side==CUBLAS_SIDE_LEFT?m:n) B=dev:MAT(ldb,m,n) C=dev:MAT(ldc,m,n)
fn cublasDtrmm alpha=value A=dev:MAT(lda,side==CUBLAS_SIDE_LEFT?m:n,side==CUBLAS_SIDE_LEFT?m:n) B=dev:MAT(ldb,m,n) C=dev:MAT(ldc,m,n)
fn cublasSscal alpha=value x=dev:MAT(incx,1,n)
fn cublasDscal alpha=value x=dev:MAT(incx,1,n)
fn cublasCsscal alpha=value x=dev:MAT(incx,1,n)
fn cublasZdscal alpha=value x=dev:MAT(incx,1,n)

lib curand CurandAPI key 900 header curand.h
soname libcurand.so.10 libcurand.so
status curandStatus_t
text enum curandStatus
handle curandGenerator_t
handle cudaStream_t null
pointers dev
constants CURAND_RNG_PSEUDO_DEFAULT CURAND_RNG_PSEUDO_XORWOW CURAND_RNG_PSEUDO_PHILOX4_32_10 CURAND_RNG_QUASI_SOBOL32
fn curandCreateGenerator
fn curandDestroyGenerator generator=free
fn curandGetVersion version=out
fn curandSetStream
fn curandSetPseudoRandomGeneratorSeed
fn curandGenerateUniform outputPtr=dev:num
fn curandGenerateUniformDouble outputPtr=dev:num
fn curandGenerateNormal outputPtr=dev:n
fn curandGenerateNormalDouble outputPtr=dev:n

lib cuopt CuOptAPI key 930 header cuopt/mathematical_optimization/cuopt_c.h include $CUOPT_PREFIX/libcuopt_mathopt/include $CUOPT_PREFIX/libcuopt_client/include
soname libcuopt_mathopt.so
status cuopt_int_t
text macros CUOPT_SUCCESS CUOPT_INVALID_ARGUMENT CUOPT_MPS_FILE_ERROR CUOPT_MPS_PARSE_ERROR CUOPT_VALIDATION_ERROR CUOPT_OUT_OF_MEMORY CUOPT_RUNTIME_ERROR
handle cuOptOptimizationProblem
handle cuOptSolverSettings
handle cuOptSolution
pointers out
constants CUOPT_MINIMIZE CUOPT_MAXIMIZE CUOPT_TERMINATION_STATUS_* CUOPT_METHOD_CONCURRENT CUOPT_METHOD_PDLP CUOPT_METHOD_DUAL_SIMPLEX CUOPT_METHOD_BARRIER
fn cuOptGetVersion
fn cuOptCreateProblem pack require=num_constraints>=0&&num_variables>=0 require=cudalib_csr_ok(P(constraint_matrix_row_offsets),num_constraints,P(constraint_matrix_column_indices),num_variables) objective_coefficients=in:num_variables constraint_matrix_row_offsets=in:num_constraints+1 constraint_matrix_column_indices=in:P(constraint_matrix_row_offsets)[num_constraints] constraint_matrix_coefficent_values=in:P(constraint_matrix_row_offsets)[num_constraints] constraint_sense=in:num_constraints rhs=in:num_constraints lower_bounds=in:num_variables upper_bounds=in:num_variables variable_types=in:num_variables problem_ptr=handleout:num_variables
fn cuOptDestroyProblem problem_ptr=free
fn cuOptGetNumVariables
fn cuOptCreateSolverSettings
fn cuOptDestroySolverSettings settings_ptr=free
fn cuOptSetParameter
fn cuOptSetIntegerParameter
fn cuOptSetFloatParameter
fn cuOptSolve solution_ptr=handleout:TAG(problem)
fn cuOptDestroySolution solution_ptr=free
fn cuOptGetTerminationStatus
fn cuOptGetErrorStatus
fn cuOptGetObjectiveValue
fn cuOptGetSolveTime
fn cuOptGetPrimalSolution solution_values=outarray:TAG(solution)

# cuSOLVER's dense API. The 64-bit (X) functions take the data type and the workspace sizes as arguments, so their
# extents are checkable: a matrix is MAT(...) elements of its cudaDataType, a workspace the bytes its _bufferSize
# answered. The legacy functions where the X API has none (orgqr) or would take more than 16 slots (gesvd, syevd).
# devInfo is a 1-element int array on the device: the image reads it back (CudaSolverError).
lib cusolver CusolverAPI key 960 header cusolverDn.h
soname libcusolver.so.12 libcusolver.so.11 libcusolver.so
status cusolverStatus_t
text enum cusolverStatus_t
handle cusolverDnHandle_t
handle cusolverDnParams_t
handle cudaStream_t null
pointers dev
constants CUDA_R_32F CUDA_R_64F CUDA_C_32F CUDA_C_64F CUBLAS_OP_N CUBLAS_OP_T CUBLAS_FILL_MODE_LOWER CUBLAS_FILL_MODE_UPPER CUSOLVER_EIG_MODE_NOVECTOR CUSOLVER_EIG_MODE_VECTOR
fn cusolverGetVersion version=out
fn cusolverDnCreate
fn cusolverDnDestroy handle=free
fn cusolverDnSetStream
fn cusolverDnCreateParams
fn cusolverDnDestroyParams params=free
fn cusolverDnXgetrf_bufferSize as cusolverDnXgetrfBufferSize A=dev:cudalib_dtype_bytes(MAT(lda,m,n),dataTypeA) workspaceInBytesOnDevice=out workspaceInBytesOnHost=out
fn cusolverDnXgetrf A=dev:cudalib_dtype_bytes(MAT(lda,m,n),dataTypeA) ipiv=dev:m<n?m:n bufferOnDevice=dev:workspaceInBytesOnDevice bufferOnHost=outarray:workspaceInBytesOnHost info=dev:1
fn cusolverDnXgetrs A=dev:cudalib_dtype_bytes(MAT(lda,n,n),dataTypeA) ipiv=dev:n B=dev:cudalib_dtype_bytes(MAT(ldb,n,nrhs),dataTypeB) info=dev:1
fn cusolverDnXpotrf_bufferSize as cusolverDnXpotrfBufferSize A=dev:cudalib_dtype_bytes(MAT(lda,n,n),dataTypeA) workspaceInBytesOnDevice=out workspaceInBytesOnHost=out
fn cusolverDnXpotrf A=dev:cudalib_dtype_bytes(MAT(lda,n,n),dataTypeA) bufferOnDevice=dev:workspaceInBytesOnDevice bufferOnHost=outarray:workspaceInBytesOnHost info=dev:1
fn cusolverDnXpotrs A=dev:cudalib_dtype_bytes(MAT(lda,n,n),dataTypeA) B=dev:cudalib_dtype_bytes(MAT(ldb,n,nrhs),dataTypeB) info=dev:1
fn cusolverDnXgeqrf_bufferSize as cusolverDnXgeqrfBufferSize A=dev:cudalib_dtype_bytes(MAT(lda,m,n),dataTypeA) tau=dev:cudalib_dtype_bytes(m<n?m:n,dataTypeTau) workspaceInBytesOnDevice=out workspaceInBytesOnHost=out
fn cusolverDnXgeqrf A=dev:cudalib_dtype_bytes(MAT(lda,m,n),dataTypeA) tau=dev:cudalib_dtype_bytes(m<n?m:n,dataTypeTau) bufferOnDevice=dev:workspaceInBytesOnDevice bufferOnHost=outarray:workspaceInBytesOnHost info=dev:1
fn cusolverDnSorgqr_bufferSize as cusolverDnSorgqrBufferSize require=m>=n&&n>=k&&k>=0 A=dev:MAT(lda,m,n) tau=dev:k lwork=out
fn cusolverDnSorgqr require=m>=n&&n>=k&&k>=0 A=dev:MAT(lda,m,n) tau=dev:k work=dev:lwork info=dev:1
fn cusolverDnDorgqr_bufferSize as cusolverDnDorgqrBufferSize require=m>=n&&n>=k&&k>=0 A=dev:MAT(lda,m,n) tau=dev:k lwork=out
fn cusolverDnDorgqr require=m>=n&&n>=k&&k>=0 A=dev:MAT(lda,m,n) tau=dev:k work=dev:lwork info=dev:1
fn cusolverDnSgesvd_bufferSize as cusolverDnSgesvdBufferSize lwork=out
fn cusolverDnDgesvd_bufferSize as cusolverDnDgesvdBufferSize lwork=out
fn cusolverDnSgesvd require=m>=n A=dev:MAT(lda,m,n) S=dev:n U=dev:jobu==65?MAT(ldu,m,m):jobu==83?MAT(ldu,m,n):0 VT=dev:jobvt==65||jobvt==83?MAT(ldvt,n,n):0 work=dev:lwork rwork=dev:n-1 info=dev:1
fn cusolverDnDgesvd require=m>=n A=dev:MAT(lda,m,n) S=dev:n U=dev:jobu==65?MAT(ldu,m,m):jobu==83?MAT(ldu,m,n):0 VT=dev:jobvt==65||jobvt==83?MAT(ldvt,n,n):0 work=dev:lwork rwork=dev:n-1 info=dev:1
fn cusolverDnSsyevd_bufferSize as cusolverDnSsyevdBufferSize A=dev:MAT(lda,n,n) W=dev:n lwork=out
fn cusolverDnDsyevd_bufferSize as cusolverDnDsyevdBufferSize A=dev:MAT(lda,n,n) W=dev:n lwork=out
fn cusolverDnSsyevd A=dev:MAT(lda,n,n) W=dev:n work=dev:lwork info=dev:1
fn cusolverDnDsyevd A=dev:MAT(lda,n,n) W=dev:n work=dev:lwork info=dev:1

# cuFFT. A plan is an int handle (kept in the handle table like a pointer one) whose tag remembers its type and array
# sizes (cudalib_fft_tag: the full arrays' elements and the half spectrum's, n/2 + 1 in the last dimension), so an exec
# is checked against the plan it runs: the plan's type, each pointer's extent. Complex data is interleaved pairs.
lib cufft CufftAPI key 1010 header cufft.h
soname libcufft.so.12 libcufft.so.11 libcufft.so
status cufftResult
text enum cufftResult_t
handle cufftHandle
handle cudaStream_t null
pointers dev
constants CUFFT_R2C CUFFT_C2R CUFFT_C2C CUFFT_D2Z CUFFT_Z2D CUFFT_Z2Z CUFFT_FORWARD CUFFT_INVERSE
fn cufftGetVersion version=out
fn cufftPlan1d require=cudalib_fft_tag(type,1,nx,batch)>=0 plan=handleout:cudalib_fft_tag(type,1,nx,batch)
fn cufftPlan2d require=cudalib_fft_tag(type,nx,ny,1)>=0 plan=handleout:cudalib_fft_tag(type,nx,ny,1)
fn cufftPlanMany require=rank>=1&&rank<=3 n=in:rank inembed=null istride=const:1 idist=const:0 onembed=null ostride=const:1 odist=const:0 require=cudalib_fft_many_tag(type,rank,P(n),batch)>=0 plan=handleout:cudalib_fft_many_tag(type,rank,P(n),batch)
fn cufftDestroy plan=free
fn cufftSetStream
fn cufftExecC2C require=CUDALIB_FFT_TYPE(TAG(plan))==CUFFT_C2C require=direction==CUFFT_FORWARD||direction==CUFFT_INVERSE idata=dev:CUDALIB_FFT_N(TAG(plan)) odata=dev:CUDALIB_FFT_N(TAG(plan))
fn cufftExecR2C require=CUDALIB_FFT_TYPE(TAG(plan))==CUFFT_R2C idata=dev:CUDALIB_FFT_N(TAG(plan)) odata=dev:CUDALIB_FFT_HALF(TAG(plan))
fn cufftExecC2R require=CUDALIB_FFT_TYPE(TAG(plan))==CUFFT_C2R idata=dev:CUDALIB_FFT_HALF(TAG(plan)) odata=dev:CUDALIB_FFT_N(TAG(plan))
fn cufftExecZ2Z require=CUDALIB_FFT_TYPE(TAG(plan))==CUFFT_Z2Z require=direction==CUFFT_FORWARD||direction==CUFFT_INVERSE idata=dev:CUDALIB_FFT_N(TAG(plan)) odata=dev:CUDALIB_FFT_N(TAG(plan))
fn cufftExecD2Z require=CUDALIB_FFT_TYPE(TAG(plan))==CUFFT_D2Z idata=dev:CUDALIB_FFT_N(TAG(plan)) odata=dev:CUDALIB_FFT_HALF(TAG(plan))
fn cufftExecZ2D require=CUDALIB_FFT_TYPE(TAG(plan))==CUFFT_Z2D idata=dev:CUDALIB_FFT_HALF(TAG(plan)) odata=dev:CUDALIB_FFT_N(TAG(plan))
