!CompiledMethod methodsFor: '*Compiler'!
symbolic
	"Answer a String listing my bytecodes."
	^Disassembler disassemble: self
!
sourceIntervalAt: pc
	"Answer the source Interval of the first mapped instruction (send, store, return, closure) at or after pc, or nil. Use it for the active context."
	| map |
	map := sourceMap.
	map isNil ifTrue: [^nil].
	1 to: map size by: 3 do: [:i |
		(map at: i) >= pc ifTrue: [^(map at: i + 1) to: (map at: i + 2)]].
	^nil
!
sourceIntervalBefore: pc
	"Answer the source Interval of the last mapped instruction before pc, or nil. Use it for sender contexts, whose pc is just after the send they wait for."
	| map result |
	map := sourceMap.
	map isNil ifTrue: [^nil].
	result := nil.
	1 to: map size by: 3 do: [:i |
		(map at: i) < pc ifTrue: [result := (map at: i + 1) to: (map at: i + 2)]].
	^result
!
tempNamesAt: pc
	"Answer the names of the argument and temporary slots of the context that executes pc (the innermost real block containing pc, else the method)."
	| map best bestStart recompiled |
	map := self propertyAt: #tempNames.
	map isNil ifTrue: [
		(source isNil or: [numArgs + numTemps = 0 and: [(bytecodes includes: 16r8F) not]]) ifTrue: [^#()].
		recompiled := [Compiler compileMethod: source in: methodClass classified: category]
			on: Error do: [:e | nil].
		(recompiled isNil or: [recompiled bytecodes ~= bytecodes]) ifTrue: [^#()].
		map := recompiled propertyAt: #tempNames.
		map isNil ifTrue: [^#()]].
	best := #().
	bestStart := -1.
	1 to: map size by: 3 do: [:i |
		((map at: i) <= pc and: [pc < (map at: i + 1) and: [(map at: i) > bestStart]]) ifTrue: [
			best := map at: i + 2.
			bestStart := map at: i]].
	^best
!
isTempSlot: anIndex hiddenAt: pc
	"Whether temporary slot anIndex (0-based) belongs to an inlined block (like | r | in a whileFalse: body) whose code does not contain pc: the name is not in scope there."
	| map |
	map := self propertyAt: #inlinedTemps.
	map isNil ifTrue: [^false].
	1 to: map size by: 3 do: [:i |
		((map at: i + 2) includes: anIndex) ifTrue: [
			^(pc between: (map at: i) and: (map at: i + 1) - 1) not]].
	^false
!
tempNamesForContext: aContext
	"Answer the names of aContext's argument and temporary slots, in slot order."
	| closure |
	closure := aContext closureOrNil.
	closure isNil ifTrue: [^self tempNamesAt: 0].
	^self tempNamesAt: closure startpc
! !
