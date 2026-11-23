[:n :warmup :schedule :selectors :prepare :preflight :varying |
	| vm pty target h ready deadline calls run validate counts token command verifySize |
	vm := Smalltalk vm.
	target := PseudoTerminal.
	counts := [vm platformHandleCounts at: #ptys ifAbsent: [0]].
	[
		counts value = 0 ifFalse: [self error: 'expected no PTYs at startup'].
		command := varying
			ifTrue: [#('/bin/sh' '-c' 'printf X; while read line; do case "$line" in size) stty size;; quit) exit 0;; esac; done')]
			ifFalse: [#('/bin/sh' '-c' 'printf X; read line')].
		pty := target spawn: command environment: nil directory: nil rows: 24 columns: 80.
		[
			counts value = 1 ifFalse: [self error: 'expected one real PTY'].
			h := pty instVarNamed: 'handle'.
			ready := ByteArray new: 1.
			deadline := Time millisecondClockValue + 3000.
			[(pty readInto: ready) = 1 or: [Time millisecondClockValue > deadline]]
				whileFalse: [pty semaphore waitTimeoutMSecs: 20].
			ready first = $X asciiValue ifFalse: [self error: 'PTY child not ready'].
			prepare value: h.
			preflight value: h.

			calls := selectors collect: [:pair |
				{Compiler evaluate: '[:target :h | target ', pair first, ' h]'.
				Compiler evaluate: (varying
					ifTrue: ['[:target :h :r :c | target ', pair second, ' h rows: r columns: c]']
					ifFalse: ['[:target :h | target ', pair second, ' h rows: 24 columns: 80]'])}].
			varying ifTrue: [
				verifySize := [:expected |
					| output buffer count |
					pty nextPutAll: 'size', (String with: Character lf).
					output := ''.
					buffer := ByteArray new: 128.
					deadline := Time millisecondClockValue + 3000.
					[(output includesSubstring: expected) or: [Time millisecondClockValue > deadline]]
						whileFalse: [
							count := pty readInto: buffer.
							count isNil
								ifTrue: [pty semaphore waitTimeoutMSecs: 20]
								ifFalse: [output := output, (buffer first: count) asString]].
					(output includesSubstring: expected) ifFalse: [self error: 'wrong PTY dimensions: ', output]].
				{(calls at: 2) second. calls last second} do: [:call |
					call value: target value: h value: 25 value: 81.
					verifySize value: '25 81'.
					call value: target value: h value: 24 value: 80.
					verifySize value: '24 80']].
			validate := [:i :op :result |
				| expected |
				expected := op = 1
					ifTrue: [i = 1 ifTrue: [h] ifFalse: [pty pid]]
					ifFalse: [target].
				result == expected ifFalse: [
					self error: 'PTY operation failed: ', (selectors at: i) printString, ' / ', result printString]].
			run := [:call :count |
				| last before start us bytes |
				before := vm statistics bytesAllocated.
				start := Time microsecondClockValue.
				varying
					ifTrue: [
						count // 2 timesRepeat: [
							last := call value: target value: h value: 24 value: 80.
							last := call value: target value: h value: 25 value: 81]]
					ifFalse: [count timesRepeat: [last := call value: target value: h]].
				us := Time microsecondClockValue - start.
				bytes := vm statistics bytesAllocated - before.
				{last. us. bytes}].
			token := [:x | x printString, ','].
			schedule doWithIndex: [:order :round |
				| count phase |
				phase := round <= 4 ifTrue: ['warmup'] ifFalse: [round = 5 ifTrue: ['discard'] ifFalse: ['steady']].
				count := round <= 4 ifTrue: [warmup // 4] ifFalse: [n].
				order doWithIndex: [:pair :slot |
					| i op result |
					i := pair first.
					op := pair second.
					result := run value: ((calls at: i) at: op) value: count.
					validate value: i value: op value: result first.
					vm stdoutWrite: ('pty-facade,', phase, ',', (token value: round),
						(token value: slot), (token value: i), (token value: op), (token value: count),
						(token value: result second), result third printString, (String with: Character lf))]].
			pty nextPutAll: ((varying ifTrue: ['quit'] ifFalse: ['']), (String with: Character lf)).
			pty waitForExit = 0 ifFalse: [self error: 'PTY child failed']
		] ensure: [pty close].
		counts value = 0 ifFalse: [self error: 'PTY cleanup failed'].
		'pty-facade-ok'
	] on: Error do: [:e | vm stderrWrite: e messageText, (String with: Character lf). Smalltalk quit: 1]
]
