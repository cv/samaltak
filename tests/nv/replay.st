"Replay the record of tests/nv/record.st on an NvComputeGPU and on a SoftwareGPU (tests/nv/README.md): every pass end and frame must be the record's, byte for byte. NV_RECORD (default build/nv/world.nvrec). Prints a line per device; exits 1 if anything differed."
| path failed |
path := (Smalltalk vm getenv: 'NV_RECORD') ifNil: ['build/nv/world.nvrec'].
failed := false.
{NvComputeGPU. SoftwareGPU} do: [:class | | r |
	r := SoftwareGPUReplay replay: path on: class.
	Smalltalk vm stderrWrite: 'replay: ', r summary, (String with: Character lf).
	r mismatches do: [:m | Smalltalk vm stderrWrite: '  ', m, (String with: Character lf)].
	(r mismatches isEmpty and: [r frames > 0]) ifFalse: [failed := true]].
failed ifTrue: [Smalltalk quit: 1].
'replay: passed'
