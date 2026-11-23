!FFIPairedBench class methodsFor: 'GPU fixtures (display CI only)'!
gpuPass
	| gpu dev pipeline tex cmd pass reset |
	gpu := GPUPrimitives.
	dev := GPUDevice default.
	"Reuse one real device, pipeline and render target across both arms."
	pipeline := (Renderer on: dev) pipeline.
	pipeline handle.
	tex := gpu createTexture: dev handle width: 64 height: 64 format: 2 usage: 2.
	reset := [
		cmd ifNotNil: [
			gpu endPass: pass.
			gpu submit: cmd fence: false.
			cmd := nil.
			gpu waitIdle: dev handle].
		cmd := gpu acquireCommandBuffer: dev handle.
		pass := gpu beginPass: cmd target: tex clear: #(0 0 0 1).
		gpu bindPipeline: pass pipeline: pipeline handle].
	[
		self case: 'gpu-pass' repeat: nil
			direct: [:n | | result |
				n timesRepeat: [
					gpu setViewport: pass x: 1.0 y: 2.0 width: 60.0 height: 61.0.
					result := gpu setScissor: pass x: 1 y: 2 width: 60 height: 61].
				result]
			candidate: [:n | | result |
				n timesRepeat: [
					gpu ffiCandidateSetViewport: pass x: 1.0 y: 2.0 width: 60.0 height: 61.0.
					result := gpu ffiCandidateSetScissor: pass x: 1 y: 2 width: 60 height: 61].
				result]
			reset: reset
			expect: [:result | result == gpu]
	] ensure: [
		cmd ifNotNil: [
			gpu endPass: pass.
			gpu submit: cmd fence: false.
			gpu waitIdle: dev handle].
		gpu release: tex.
		pipeline release]
! !
