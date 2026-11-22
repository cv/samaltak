"Record what a SoftwareGPU gets and produces for the first frames of the World (tests/nv/README.md): the default desktop of the Tools (text, a Form image, the Mandelbrot's image, lists, the halftone desk, lines) at 1920x1080. Evaluated by tests/nv/record.sh as the --eval of a headless image; NV_RECORD (default build/nv/world.nvrec), NV_FRAMES (default 6)."
| path frames rec deadline |
path := (Smalltalk vm getenv: 'NV_RECORD') ifNil: ['build/nv/world.nvrec'].
frames := ((Smalltalk vm getenv: 'NV_FRAMES') ifNil: ['6']) asNumber.
rec := SoftwareGPURecorder width: 1920 height: 1080 path: path.
rec maxFrames: frames.
rec install.
World openExtent: 1920 @ 1080 hidden: false.
Tools startUp.
deadline := Time millisecondClockValue + 120000.
[rec isRecording and: [Time millisecondClockValue < deadline]] whileTrue: [
	(Delay forMilliseconds: 300) wait.
	World current toast: 'frame ', rec frames printString].
rec stop.
'recorded ', rec frames printString, ' frames into ', path
