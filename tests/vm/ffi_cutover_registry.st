Object subclass: #FFICutoverProbe
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'FFICutoverProbe'!

!FFICutoverProbe methodsFor: 'checking'!
check: slots mode: mode platform: hasPlatform
	| names |
	self require: Smalltalk vm jitMode = mode because: 'VM did not select the requested tier'.
	names := Smalltalk vm primitiveNames.
	self require: ((names at: 401 ifAbsent: [nil]) notNil = hasPlatform)
		because: 'wrong backend (unmigrated windowClose slot)'.
	#((call platform platform_process_spawn (bytesWithLength) i64)
	  (call platform platform_process_wait (i64 i32 writableBytesWithLength) i32)
	  (call platform platform_process_exec (bytesWithLength) i32)
	  (call platform platform_pty_spawn (bytesWithLength i32 i32 writableBytesWithLength) i32))
		do: [:spec | self require: ((PlatformFFI bind: spec) notNil = hasPlatform)
			because: 'wrong backend availability: ', spec third].
	"Check all rows before trying a numeric header: never call a live primitive with probe arguments."
	slots do: [:row |
		self require: ((names at: row first ifAbsent: [nil]) isNil)
			because: 'retired slot still dispatchable: ', row first printString.
		self require: (names noneSatisfy: [:n | n = row second])
			because: 'retired name still dispatchable: ', row second].
	slots do: [:row | self staleHeader: row first named: row second mode: mode].
	Smalltalk vm garbageCollect.
	self require: self drive = 35625 because: 'stale header failed after GC'.
	^#ffiCutoverRegistryOK
!
staleHeader: slot named: oldName mode: mode
	| method |
	self require: ([Compiler compileMethod: 'probe: x <primitive: ''', oldName, '''> ^x'
		in: self class classified: 'checking'. false]
		on: SyntaxError do: [:e | e messageText includesSubstring: 'Unknown primitive'])
		because: 'compiler admitted retired name: ', oldName.
	self require: (thisContext tryPrimitive: slot receiver: self args: #(1)) == #primitiveFailed
		because: 'tryPrimitive still dispatches: ', oldName.
	"Numeric pragmas preserve the CompiledMethod header that persisted images can contain."
	method := Compiler compile: 'probe: x <primitive: ', slot printString, ' error: ec>
		ec ifNotNil: [self error: ''missing primitive supplied an error code''].
		^x + 17' in: self class.
	self require: method primitiveNumber = slot because: 'numeric header changed'.
	32 timesRepeat: [self require: (self probe: 25) = 42 because: 'stale header lost its body'].
	mode == #baseline ifTrue: [
		self require: method jitSendSites notNil because: 'numeric probe lacked installed baseline code']
!
drive
	| sum |
	sum := 0.
	1 to: 250 do: [:i | sum := sum + (self probe: i)].
	^sum
!
probe: x
	^x + 17
!
require: aBoolean because: reason
	aBoolean ifFalse: [self error: reason]
! !
