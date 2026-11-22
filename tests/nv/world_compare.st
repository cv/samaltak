"tests/nv/world_test.sh: compare the World's screenshots on the NvComputeGPU and on the SoftwareGPU (NV_DIR: world-nv.png, world-software.png and their .txt: the device, the compositor's last error, the Process Browser's bounds). Exits 1 unless each ran on its device without an error and every pixel outside the top bar and the Process Browser's CPU column is equal within 2 levels a channel: on the SoftwareGPU, which composes only when something changed, a cross-fade (a layer's opacity) may still be a step from its end, a level off. The pixels themselves are compared exactly by replay.st."
| dir info nv sw pb n off w h ok out |
dir := (Smalltalk vm getenv: 'NV_DIR') ifNil: ['build/nv'].
info := #('nv' 'software') collect: [:g | (FileStream readOnlyFileNamed: dir, '/world-', g, '.txt' do: [:f | f contents]) lines].
ok := ((info first first includesSubstring: 'NvComputeGPU') and: [info first first includesSubstring: 'nil'])
	& ((info last first includesSubstring: 'SoftwareGPU') and: [info last first includesSubstring: 'nil']).
nv := PNGReader formFromFile: dir, '/world-nv.png'.
sw := PNGReader formFromFile: dir, '/world-software.png'.
pb := ((info first at: 2) reject: [:c | c = $']) substrings collect: [:s | s asNumber].
w := nv width. h := nv height.
n := off := 0.
(nv extent = sw extent) ifFalse: [ok := false] ifTrue: [
	0 to: h - 1 do: [:y | 0 to: w - 1 do: [:x | | i live |
		i := y * w + x + 1.
		(nv bits at: i) = (sw bits at: i) ifFalse: [
			"the top bar's statistics; the Process Browser's CPU column (its rightmost 120 points)"
			live := y < 30 or: [pb size = 4 and: [x >= ((pb at: 3) - 120) and: [x < (pb at: 3) and: [y >= (pb at: 2) and: [y < (pb at: 4)]]]]].
			live ifFalse: [| a b |
				off := off + 1.
				a := nv bits at: i. b := sw bits at: i.
				(0 to: 3) do: [:k | (((a bitShift: k * -8) bitAnd: 255) - ((b bitShift: k * -8) bitAnd: 255)) abs > 2 ifTrue: [n := n + 1]]]]]]].
out := 'world: ', info first first, ' | ', info last first, ' | ', nv extent printString, ', ', off printString, ' pixels differ outside the live statistics, ', n printString, ' channels by more than 2'.
Smalltalk vm stderrWrite: out, (String with: Character lf).
(ok and: [n = 0]) ifFalse: [Smalltalk quit: 1].
'world: passed'
