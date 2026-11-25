Object subclass: #NvKernel
	instanceVariableNames: 'name code registerCount frameSize minStackSize sharedSize maxThreads parameters parameterOffset parameterSize constantBanks relocations exitOffsets smVersion bankRelocations globals cubin'
	classVariableNames: ''
	package: 'System-NV'!

NvKernel comment: 'I am one kernel (a __global__ function) of a cubin, as NvCubin read it, with what a launch needs:
- code: its machine code (.text.<name>), which runs from wherever it is put (relocations lists any the ELF has: the CUDA driver applies them when it loads the cubin);
- registerCount, frameSize, minStackSize (per thread), sharedSize (its static __shared__ bytes), maxThreads (the threads per block __launch_bounds__ allows, nil if it says nothing);
- parameters: (ordinal offset size) triples in ordinal order, offsets in the parameter area; parameterOffset is where that area starts in constant bank 0 (after the driver''s part, 16r380 on sm_120 and sm_121), parameterSize its size;
- constantBanks: bank index -> ByteArray of initial contents: 0 is the kernel''s own (the driver''s part, then the parameters), others (3: __constant__ data) are shared by the cubin''s kernels;
- smVersion: the SM the cubin is for (121 for sm_121);
- globals: data section name -> its initial bytes (.nv.global.init: libdevice''s tables), and bankRelocations: (bank offset section value type), the 64-bit addresses into them the constant banks hold (type 2, R_CUDA_64): the CUDA driver places the data and writes the addresses when it loads the cubin;
- cubin: the bytes of the cubin I am from, which NvCudaCompute (System-CUDA) gives the CUDA driver to load.'!

!NvKernel methodsFor: 'accessing'!
name
	^name
!
code
	^code
!
registerCount
	^registerCount
!
frameSize
	^frameSize
!
minStackSize
	^minStackSize
!
sharedSize
	^sharedSize
!
maxThreads
	^maxThreads
!
parameters
	^parameters
!
parameterOffset
	^parameterOffset
!
parameterSize
	^parameterSize
!
constantBanks
	^constantBanks
!
relocations
	^relocations
!
exitOffsets
	^exitOffsets
!
bankRelocations
	^bankRelocations
!
bankRelocations: anArray
	bankRelocations := anArray
!
globals
	^globals
!
smVersion
	^smVersion
!
cubin
	"The cubin's bytes (an ELF file), nil if I was made otherwise."
	^cubin
!
cubin: aByteArray
	cubin := aByteArray
!
printOn: aStream
	aStream nextPutAll: 'NvKernel('; nextPutAll: name; nextPutAll: ', '; print: code size; nextPutAll: ' bytes, ';
		print: registerCount; nextPutAll: ' registers, '; print: parameters size; nextPutAll: ' parameters)'
! !

!NvKernel methodsFor: 'parameters'!
parameterBytes: values
	"The parameter area for values, one per parameter in order: Integers (addresses, counts) stored in the
	parameter''s size, Floats as 32-bit floats (64-bit if the parameter has 8 bytes), ByteArrays as they are."
	| b |
	values size = parameters size ifFalse: [^self error: name, ' takes ', parameters size printString, ' parameters, not ', values size printString].
	b := ByteArray new: parameterSize.
	parameters with: values do: [:p :v | | at n |
		at := (p at: 2) + 1.
		n := p at: 3.
		v isInteger
			ifTrue: [
				v < 0 ifTrue: [^self error: 'negative parameter ', v printString].
				1 to: n do: [:i | b at: at + i - 1 put: ((v bitShift: (i - 1) * -8) bitAnd: 255)]]
			ifFalse: [
				v isFloat
					ifTrue: [n = 8 ifTrue: [b float64At: at put: v] ifFalse: [b float32At: at put: v]]
					ifFalse: [b replaceFrom: at to: at + n - 1 with: v startingAt: 1]]].
	^b
! !

!NvKernel methodsFor: 'initialization'!
setName: aString code: bytes
	name := aString.
	code := bytes.
	registerCount := 0. frameSize := 0. minStackSize := 0. sharedSize := 0.
	parameters := #(). parameterOffset := 0. parameterSize := 0.
	constantBanks := Dictionary new. relocations := #(). exitOffsets := #().
	bankRelocations := #(). globals := Dictionary new
!
registerCount: n
	registerCount := n
!
frameSize: n
	frameSize := n
!
minStackSize: n
	minStackSize := n
!
sharedSize: n
	sharedSize := n
!
maxThreads: n
	maxThreads := n
!
parameters: anArray
	parameters := anArray
!
parameterOffset: offset size: n
	parameterOffset := offset.
	parameterSize := n
!
relocations: anArray
	relocations := anArray
!
exitOffsets: anArray
	exitOffsets := anArray
!
smVersion: n
	smVersion := n
! !
