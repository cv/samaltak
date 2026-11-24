[:name :n :warmup :tree |
	| vm emit once repeat run last expected validate descriptor binding x y pty h ready deadline |
	vm := Smalltalk vm.
	emit := [:phase :count :us :bytes |
		vm stdoutWrite: ('ffi-bench,', phase, ',', count printString, ',', us printString, ',', bytes printString, (String with: Character lf))].
	once := [:phase :call | | t us |
		t := Time microsecondClockValue.
		last := call value.
		us := Time microsecondClockValue - t.
		emit value: phase value: 1 value: us value: -1].
	repeat := [:phase :call | | before t us bytes |
		warmup timesRepeat: [last := call value].
		before := vm statistics bytesAllocated.
		t := Time microsecondClockValue.
		n timesRepeat: [last := call value].
		us := Time microsecondClockValue - t.
		bytes := vm statistics bytesAllocated - before.
		emit value: phase value: n value: us value: bytes].
	run := [:call :facade :rejectFallback |
		once value: 'first' value: call.
		validate value: last.
		repeat value: 'steady' value: call.
		validate value: last.
		"Check the measured branch is not silently using its compatibility path. No image is saved."
		(tree == #branch and: [rejectFallback notNil]) ifTrue: [
			Compiler compile: rejectFallback, ' self error: ''unexpected legacy fallback''' in: facade class.
			validate value: call value]].

	[
		name = #control ifTrue: [
			x := 17.
			validate := [:v | v = 17 ifFalse: [self error: 'control returned the wrong result']].
			run value: [x] value: nil value: nil].
		(#(scale ime) includes: name) ifTrue: [
			validate := [:v |
				v = 'bad window handle -1' ifFalse: [self error: 'expected the native missing-window error']].
			"The negative handle cannot name a window. The platform rejects it before any SDL video call."
			name = #scale
				ifTrue: [run value: [[GPUPrimitives windowDisplayScale: -1]
					on: GPUError do: [:e | e platformLastError]]
					value: GPUPrimitives value: 'legacyWindowDisplayScale: window']
				ifFalse: [run value: [[GPUPrimitives window: -1 textInputAreaX: 2 y: 3 width: 4 height: 5 cursor: 1]
					on: GPUError do: [:e | e platformLastError]]
					value: GPUPrimitives value: 'legacyWindow: win textInputAreaX: x y: y width: w height: h cursor: c']].
		name = #close ifTrue: [ | spawn check |
			spawn := [PseudoTerminal spawn: #('/bin/sh' '-c' 'exit 0')
				environment: nil directory: nil rows: 24 columns: 80].
			check := [(pty isOpen or: [(vm platformHandleCounts at: #ptys) ~= 0])
				ifTrue: [self error: 'PTY close left a live handle']].
			pty := spawn value.
			pty waitForExit.
			once value: 'first' value: [pty close].
			check value.
			tree == #branch ifTrue: [
				Compiler compile: 'legacyClose: h self error: ''unexpected legacy fallback''' in: PseudoTerminal class.
				pty := spawn value.
				pty waitForExit.
				pty close.
				check value]].
		(#(foreground resize) includes: name) ifTrue: [ | args ffi |
			pty := PseudoTerminal spawn: #('/bin/sh' '-c' 'printf X; read line')
				environment: nil directory: nil rows: 24 columns: 80.
			[
				h := pty instVarNamed: 'handle'.
				ready := ByteArray new: 1.
				deadline := Time millisecondClockValue + 3000.
				[(pty readInto: ready) = 1 or: [Time millisecondClockValue > deadline]]
					whileFalse: [pty semaphore waitTimeoutMSecs: 20].
				ready first = $X asciiValue ifFalse: [self error: 'PTY child not ready'].
				expected := name = #foreground ifTrue: [pty pid] ifFalse: [tree == #branch ifTrue: [1] ifFalse: [PseudoTerminal]].
				validate := [:v | v = expected ifFalse: [self error: 'PTY operation failed']].
				tree == #base
					ifTrue: [
						name = #foreground
							ifTrue: [run value: [PseudoTerminal primForeground: h] value: nil value: nil]
							ifFalse: [run value: [PseudoTerminal primResize: h rows: 24 columns: 80] value: nil value: nil]]
					ifFalse: [
						ffi := Smalltalk at: #FFI.
						name = #foreground
							ifTrue: [descriptor := #(call 'platform' 'pty_foreground' (i64) i32). args := {h}]
							ifFalse: [descriptor := #(call 'platform' 'pty_resize' (i64 i64 i64) i32). args := {h. 24. 80}].
						once value: 'first' value: [binding := ffi bind: descriptor. binding invoke: args].
						validate value: last.
						repeat value: 'steady' value: [binding invoke: args].
						validate value: last]
			] ensure: [pty nextPutAll: (String with: Character lf). pty waitForExit. pty close]].
		name = #dynamic ifTrue: [ | ffi bindingClass |
			ffi := Smalltalk at: #FFI.
			bindingClass := Smalltalk at: #FFIBinding.
			descriptor := #(call 'ffibench' 'bench_add' (i32 i32) i32).
			x := 17.
			y := -20.
			once value: 'first_bind' value: [ffi bind: descriptor].
			binding := last.
			validate := [:v | v = -3 ifFalse: [self error: 'dynamic invoke returned the wrong result']].
			once value: 'first_invoke' value: [binding invoke: #(17 -20)].
			validate value: last.
			repeat value: 'invoke_reused' value: [binding invoke: #(17 -20)].
			validate value: last.
			repeat value: 'invoke_fresh' value: [binding invoke: {x. y}].
			validate value: last.
			repeat value: 'bind' value: [ffi bind: descriptor].
			last class == bindingClass ifFalse: [self error: 'dynamic bind returned the wrong result']].
		'success'
	] on: Error do: [:e | vm stderrWrite: e messageText, (String with: Character lf). Smalltalk quit: 1]
]
