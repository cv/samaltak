"Benchmark source fixture, extracted from 3ceae5316bd3cc180b594e989a0752c85df4782c (d124cd9^).
The runner reads these chunks and compiles copies; do not file this in."

!PseudoTerminal class methodsFor: 'benchmark reference'!
primForeground: aHandle
	"Answer the foreground process group of aHandle's terminal, nil on failure."
	| result |
	result := PlatformFFI call: #(call 'platform' 'pty_foreground' (i64) i32)
		with: {aHandle} ifUnavailable: [^self legacyForeground: aHandle].
	^result < 0 ifTrue: [nil] ifFalse: [result]
!
primResize: aHandle rows: rows columns: columns
	| result |
	result := PlatformFFI call: #(call 'platform' 'pty_resize' (i64 i64 i64) i32)
		with: {aHandle. rows. columns} ifUnavailable: [^self legacyResize: aHandle rows: rows columns: columns].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
legacyForeground: aHandle
	<primitive: 'ptyForeground'>
	^nil
!
legacyResize: aHandle rows: rows columns: columns
	<primitive: 'ptyResize'>
	^nil
! !

!PlatformFFI class methodsFor: 'benchmark reference'!
call: descriptor with: arguments ifUnavailable: fallback
	^[(self bindingFor: descriptor) invoke: arguments]
		on: FFIError do: [:error | fallback value]
!
bindingFor: descriptor
	| bindings binding updated |
	bindings := Bindings ifNil: [IdentityDictionary new].
	^bindings at: descriptor ifAbsent: [
		binding := FFI bind: descriptor.
		"Publish a complete copy: another Process may bind while we allocate."
		updated := bindings copy.
		updated at: descriptor put: binding.
		Bindings := updated.
		binding]
! !
