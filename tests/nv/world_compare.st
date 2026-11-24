"tests/nv/world_test.sh: compare the World's screenshots on the NvComputeGPU and on the SoftwareGPU (NV_DIR: world-nv.png, world-software.png and their .txt, or with NV_SUFFIX after the device's name, world-nv-kms.png ...: the device, the compositor's last error, the Process Browser's bounds). Exits 1 unless each ran on its device without an error and every pixel outside the top bar (its frame time) is equal within 2 levels a channel (world_test.sh froze the tools' readouts of the machine's speed and load): on the SoftwareGPU, which composes only when something changed, a cross-fade (a layer's opacity) may still be a step from its end, a level off. The pixels themselves are compared exactly by replay.st."
| dir sfx info nv sw pb n off w h ok out |
dir := (Smalltalk vm getenv: 'NV_DIR') ifNil: ['build/nv'].
sfx := (Smalltalk vm getenv: 'NV_SUFFIX') ifNil: [''].
info := #('nv' 'software') collect: [:g | (FileStream readOnlyFileNamed: dir, '/world-', g, sfx, '.txt' do: [:f | f contents]) lines].
ok := ((info first first includesSubstring: 'NvComputeGPU') and: [info first first includesSubstring: 'nil'])
	& ((info last first includesSubstring: 'SoftwareGPU') and: [info last first includesSubstring: 'nil']).
nv := PNGReader formFromFile: dir, '/world-nv', sfx, '.png'.
sw := PNGReader formFromFile: dir, '/world-software', sfx, '.png'.
pb := ((info first at: 2) reject: [:c | c = $']) substrings collect: [:s | s asNumber].
w := nv width. h := nv height.
n := off := 0.
(nv extent = sw extent) ifFalse: [ok := false] ifTrue: [
	0 to: h - 1 do: [:y | 0 to: w - 1 do: [:x | | i live |
		i := y * w + x + 1.
		(nv bits at: i) = (sw bits at: i) ifFalse: [
			"the top bar's statistics"
			live := y < 30.
			live ifFalse: [| a b |
				off := off + 1.
				a := nv bits at: i. b := sw bits at: i.
				(0 to: 3) do: [:k | (((a bitShift: k * -8) bitAnd: 255) - ((b bitShift: k * -8) bitAnd: 255)) abs > 2 ifTrue: [n := n + 1]]]]]]].
out := 'world', sfx, ': ', info first first, ' | ', info last first, ' | ', nv extent printString, ', ', off printString, ' pixels differ outside the live statistics, ', n printString, ' channels by more than 2'.
Smalltalk vm stderrWrite: out, (String with: Character lf).
(ok and: [n = 0]) ifFalse: [Smalltalk quit: 1].
'world: passed'
