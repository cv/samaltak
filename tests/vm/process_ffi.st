"Display-free process tests; loaded only by process_ffi_test.py into disposable VMs."

Object subclass: #ProcessFFISmoke
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'ProcessFFISmoke'!

!ProcessFFISmoke class methodsFor: 'support'!
check: condition because: description
	condition ifFalse: [self error: description]
!
argv: mode
	^{'process fixture'. mode. 'two words'. ''. '$(";*|&<>\)'. #[255 195 169]}
!
badArgv
	^{{}. #('' 'hold'). 42. {'process fixture'. 42}.
		{'process fixture'. #[97 0 98]}}
!
awaitRead: pty until: marker
	"With marker=nil, drain until EOF instead."
	| buffer out n deadline |
	buffer := ByteArray new: 256.
	out := WriteStream on: (ByteArray new: 256).
	deadline := Time millisecondClockValue + 5000.
	[Time millisecondClockValue < deadline] whileTrue: [
		n := pty readInto: buffer.
		n isNil ifTrue: [pty semaphore waitTimeoutMSecs: 25] ifFalse: [
			n = 0 ifTrue: [^out contents asString].
			out nextPutAll: (buffer first: n).
			(marker notNil and: [out contents asString endsWith: marker])
				ifTrue: [^out contents asString]]].
	self error: 'PTY read timed out'
! !

!ProcessFFISmoke class methodsFor: 'processes'!
spawnAndWait
	| wait pid buf slice args |
	self badArgv do: [:bad |
		self check: (File primSpawn: bad) isNil because: 'spawn admitted malformed argv'].
	self check: (File primSpawn: #('missing process fixture')) isNil because: 'missing spawn'.
	pid := File primSpawn: (self argv: 'hold').
	self check: (pid isInteger and: [pid > 0]) because: 'spawn did not return child PID'.
	Smalltalk vm stdoutWrite: 'vm-hold-pid=', pid printString, (String with: Character lf).

	wait := FFI bind: #(call 'platform' 'platform_process_wait' (i64 i32 writableBytesWithLength) i32).
	buf := #[99 99 99 99 99 99 99] copy.
	slice := {buf. 2. 5}.
	self check: (wait tryInvoke3: pid with: 0 with: slice) = 1 because: 'raw wait pending result'.
	self check: buf = #[99 0 0 0 0 0 99] because: 'raw pending receipt'.
	self check: (File primWait: pid blocking: false) isNil because: 'facade wait pending'.
	self check: (wait tryInvoke3: pid + 16r100000000 with: 0 with: slice) = 0
		because: 'wait truncated an out-of-range PID'.
	self check: buf = #[99 0 0 0 0 0 99] because: 'invalid wait changed receipt'.
	self check: (File primWait: pid blocking: #false) isNil because: 'wait admitted non-Boolean'.
	File writeText: 'release' to: 'release'.
	self check: (wait tryInvoke3: pid with: 1 with: slice) = 1 because: 'raw wait did not reap'.
	self check: buf = #[99 1 37 0 0 0 99] because: 'raw exit receipt'.
	self check: (wait tryInvoke3: pid with: 0 with: slice) = 0 because: 'raw wait must report no child'.
	self check: buf = #[99 1 37 0 0 0 99] because: 'no-child wait changed receipt'.
	self check: (File lastError includesSubstring: 'waitpid') because: 'no-child error was lost'.
	self check: (File primWait: pid blocking: false) isNil because: 'facade wait no child'.

	pid := File primSpawn: #('process fixture' 'signal').
	self check: (pid isInteger and: [pid > 0]) because: 'spawn for signal wait'.
	self check: (File primWait: pid blocking: true) = 143 because: 'normalized signal status'.

	args := Array new: 4100 withAll: ''.
	args at: 1 put: 'process fixture'; at: 2 put: 'large'; at: 4100 put: 'large-tail'.
	pid := File primSpawn: args.
	self check: (pid isInteger and: [pid > 0]) because: 'large representable argv rejected'.
	self check: (File primWait: pid blocking: true) = 0 because: 'large argv mismatched'
!
execInIsolatedVM
	self badArgv do: [:bad |
		self check: (File primExec: bad) isNil because: 'exec admitted malformed argv'].
	self check: (File primExec: #('missing process fixture')) isNil because: 'missing exec returned non-nil'.
	self check: (File lastError includesSubstring: 'execvp') because: 'missing exec error was lost'.
	Smalltalk vm stdoutWrite: 'vm-exec-ready', (String with: Character lf).
	File primExec: (self argv: 'exec').
	self error: 'successful exec returned to the VM'
! !

!ProcessFFISmoke class methodsFor: 'terminal'!
terminal: bin directory: cwd cwdHex: cwdHex inheritedCwdHex: inheritedHex
	| pty env before lines crlf |
	before := Smalltalk vm platformHandleCounts at: #ptys.
	env := {'PATH=', bin. #[80 82 79 67 69 83 83 95 70 70 73 95 66 89 84 69 83 61 255 32 195 169].
		'TERM=fixture-term'. 'LC_ALL=C'}.
	crlf := String with: Character cr with: Character lf.
	pty := PseudoTerminal spawn: #('terminal fixture' 'pty')
		environment: env directory: cwd rows: 24 columns: 80.
	[
		self check: (pty pid isInteger and: [pty pid > 0]) because: 'PTY did not return child PID'.
		lines := (self awaitRead: pty until: 'ready', crlf) lines asArray.
		self check: lines = {'size=24 80'. 'pid=', pty pid printString. 'cwd=', cwdHex.
			'env=ff20c3a9'. 'parent=-'. 'term=666978747572652d7465726d'. 'ready'}
			because: 'explicit PTY launch: ', lines printString.
		self check: pty exitStatus isNil because: 'PTY finished before input'.
		pty rows: 33 columns: 101.
		self check: (pty nextPutAll: #[116 101 115 116 32 36 42 10]) because: 'PTY write failed'.
		lines := (self awaitRead: pty until: nil) lines asArray.
		self check: lines = #('resized=33 101' 'input=7465737420242a0a') because: 'PTY reply: ', lines printString.
		self check: pty waitForExit = 23 because: 'PTY exit status'
	] ensure: [pty close].

	self terminalReportWith: nil cwdHex: inheritedHex parent: 'parent=70726f636573732d706172656e74'.
	self terminalReportWith: #() cwdHex: inheritedHex parent: 'parent=-'.
	self terminalFailures.
	self check: (Smalltalk vm platformHandleCounts at: #ptys) = before because: 'PTY handle leak'
!
terminalReportWith: env cwdHex: cwdHex parent: parentLine
	| pty lines |
	pty := PseudoTerminal spawn: #('process fixture' 'pty-report')
		environment: env directory: nil rows: 25 columns: 81.
	[
		lines := (self awaitRead: pty until: nil) lines asArray.
		self check: lines = {'size=25 81'. 'pid=', pty pid printString. 'cwd=', cwdHex.
			'env=-'. parentLine. 'term=787465726d2d323536636f6c6f72'. 'ready'}
			because: 'default PTY launch: ', lines printString.
		self check: pty waitForExit = 23 because: 'default PTY exit status'
	] ensure: [pty close]
!
terminalFailures
	| argv |
	argv := #('process fixture' 'pty-report').
	self badArgv do: [:bad |
		self check: (PseudoTerminal primSpawn: bad environment: nil directory: nil rows: 24 columns: 80)
			isNil because: 'PTY accepted malformed argv'].
	self check: (PseudoTerminal primSpawn: argv environment: #(42) directory: nil rows: 24 columns: 80)
		isNil because: 'PTY accepted non-text env entry'.
	self check: (PseudoTerminal primSpawn: argv environment: nil directory: #[97 0 98] rows: 24 columns: 80)
		isNil because: 'PTY accepted NUL in cwd'.
	self check: (PseudoTerminal primSpawn: argv environment: nil directory: nil rows: 0 columns: 80)
		isNil because: 'PTY accepted zero rows'.
	self check: (PseudoTerminal primSpawn: argv environment: nil directory: nil rows: 24 columns: 65536)
		isNil because: 'PTY truncated columns'.
	self check: ([PseudoTerminal spawn: #('missing process fixture')
		environment: nil directory: nil rows: 24 columns: 80. false] on: FileError do: [:error | true])
		because: 'missing PTY did not raise FileError'
! !
