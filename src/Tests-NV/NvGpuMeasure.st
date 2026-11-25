Object subclass: #NvGpuMeasure
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-NV'!

NvGpuMeasure comment: 'I measure System-NV on a real NVIDIA GPU (needs one; make test-nv does not run me, call report):

	NvGpuMeasure report     "a String: fence round trip, launch latency, launches per second, copy bandwidth, for each backend"
	NvGpuMeasure reportOn: NvCudaDevice     "one: NvDevice (System-NV''s RM client) or NvCudaDevice (libcuda)"

- fence round trip: a semaphore release submitted and waited for, the channel otherwise idle;
- launch latency: launch one block of fill and wait for it, one at a time;
- launch rate: 1000 launches queued back to back, then one wait;
- copy: copy16 moving 64 MB (16 bytes per thread, 256 threads per block), counted as bytes read plus bytes written.
Each is the best of a few runs, in microseconds of the image''s clock.'!

!NvGpuMeasure class methodsFor: 'measuring'!
best: n of: aBlock
	"The fastest of n runs of aBlock, in microseconds."
	^((1 to: n) collect: [:i | Time microsecondsToRun: aBlock]) inject: SmallInteger maxVal into: [:a :b | a min: b]
!
report
	"Both backends, where they open: System-NV's RM client, then libcuda."
	^String streamContents: [:s |
		{NvDevice. NvCudaDevice} do: [:c |
			s nextPutAll: ([self reportOn: c] on: Error do: [:e | c name, ': ', e messageText]); cr]]
!
reportOn: aDeviceClass
	^aDeviceClass during: [:gpu | | compute cubin fill copy m src dst n fence launch rate bytes copyUs |
		cubin := NvTestKernels cubin.
		fill := cubin kernelNamed: 'fill'.
		copy := cubin kernelNamed: 'copy16'.
		compute := gpu newCompute.
		m := gpu allocate: 4096.
		compute run: fill grid: 1 block: 32 arguments: (Array with: m gpuAddress with: 1 with: 32).
		fence := (self best: 5 of: [1 to: 100 do: [:i | compute channel sync]]) / 100.0.
		launch := (self best: 5 of: [1 to: 100 do: [:i | compute run: fill grid: 1 block: 32 arguments: (Array with: m gpuAddress with: i with: 32)]]) / 100.0.
		rate := (self best: 3 of: [| f | 1 to: 1000 do: [:i | f := compute launch: fill grid: 1 block: 32 arguments: (Array with: m gpuAddress with: i with: 32)]. compute wait: f]) / 1000.0.
		bytes := 64 * 1024 * 1024.
		src := gpu allocate: bytes.
		dst := gpu allocate: bytes.
		src fill: bytes bytes: (ByteArray withAll: (0 to: 255)) from: 0.
		n := bytes // 16.
		copyUs := self best: 5 of: [compute run: copy grid: n // 256 block: 256 arguments: (Array with: dst gpuAddress with: src gpuAddress with: n)].
		((dst bytesAt: bytes - 256 count: 256) = (ByteArray withAll: (0 to: 255))) ifFalse: [^'copy16 copied wrong bytes'].
		String streamContents: [:s |
			s nextPutAll: aDeviceClass name; nextPutAll: ': GPU SM version 16r'; nextPutAll: (gpu smVersion printString: 16); nextPutAll: ', ';
				print: gpu smCount; nextPutAll: ' SMs'; cr.
			s nextPutAll: 'fence round trip: '; print: fence rounded; nextPutAll: ' us'; cr.
			s nextPutAll: 'launch + wait: '; print: launch rounded; nextPutAll: ' us'; cr.
			s nextPutAll: 'queued launches: '; print: rate; nextPutAll: ' us each ('; print: (1000000 / rate) rounded; nextPutAll: ' per second)'; cr.
			s nextPutAll: 'copy16 64 MB: '; print: copyUs; nextPutAll: ' us, '; print: (2 * bytes / copyUs / 1000.0) ; nextPutAll: ' GB/s (read + write)']]
! !
