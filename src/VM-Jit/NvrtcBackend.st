CLibrary subclass: #NvrtcBackend
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

NvrtcBackend comment: 'NVIDIA''s runtime CUDA compiler, NVRTC, behind dlopen (vm/native/nvrtc.h: loaded on first use where the CUDA toolkit is installed; stubs on UEFI). FFIPrimitives exports it to the image as core_nvrtc_* (FFIPrimitives-nvrtc); System-NV''s NvRtc uses them. docs/nv-shaders.md. Not simulated.'!

!NvrtcBackend class methodsFor: 'declaring'!
headers
	^#('"nvrtc.h"')
! !

!NvrtcBackend methodsFor: 'calls'!
version
	<c: 'int64_t samaltak_nvrtc_version(void)'>
	^-1
!
start: src length: srcLen options: opts length: optsLen
	<c: 'int64_t samaltak_nvrtc_start(const uint8_t *src, uint64_t srcLen, const uint8_t *opts, uint64_t optsLen)'>
	^-1
!
poll: job
	<c: 'int64_t samaltak_nvrtc_poll(int64_t job)'>
	^-1
!
output: job kind: kind into: out length: outLen
	<c: 'int64_t samaltak_nvrtc_output(int64_t job, int64_t kind, uint8_t *out, uint64_t outLen)'>
	^-1
!
free: job
	<c: 'int64_t samaltak_nvrtc_free(int64_t job)'>
	^-1
! !
