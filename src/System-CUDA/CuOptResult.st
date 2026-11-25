Object subclass: #CuOptResult
	instanceVariableNames: 'status objective values seconds'
	classVariableNames: ''
	package: 'System-CUDA'!

CuOptResult comment: 'I am what cuOpt answered for a linear program (CuOpt): its termination status (statusName: Optimal, Infeasible, ...), the objective''s value, the variables'' values (nil without a solution, e.g. an infeasible problem) and the solver''s seconds.'!

!CuOptResult methodsFor: 'accessing'!
setStatus: anInteger objective: aFloat values: anArray seconds: aNumber
	status := anInteger.
	objective := aFloat.
	values := anArray.
	seconds := aNumber
!
status
	^status
!
objective
	^objective
!
values
	^values
!
seconds
	^seconds
!
isOptimal
	^status = 1
!
statusName
	| c prefix |
	prefix := 'CUOPT_TERMINATION_STATUS_'.
	c := CuOptAPI constants.
	1 to: c size by: 2 do: [:i |
		((c at: i) size > prefix size and: [((c at: i) copyFrom: 1 to: prefix size) = prefix and: [(c at: i + 1) = status]])
			ifTrue: [^(c at: i) copyFrom: prefix size + 1 to: (c at: i) size]].
	^status printString
! !

!CuOptResult methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a CuOptResult: '; nextPutAll: self statusName; nextPutAll: ', objective '; print: objective;
		nextPutAll: ' at '; print: values; nextPutAll: ' in '; print: (seconds * 1000) rounded; nextPutAll: ' ms'
! !
