Object subclass: #RemoteRequest
	instanceVariableNames: 'arguments connection afterResponse'
	classVariableNames: ''
	package: 'System-Remote'!

RemoteRequest comment: 'I am one command received by the ControlServer: the decoded JSON object (arguments, e.g. {"id": 4, "cmd": "click", "target": "@w1.ok"}) and the ControlConnection it came from (nil in tests). Command handlers read their arguments through me.'!

!RemoteRequest methodsFor: 'accessing'!
arguments
	^arguments
!
connection
	^connection
!
command
	^(arguments at: 'cmd' ifAbsent: [nil]) ifNotNil: [:c | c asString]
!
id
	^arguments at: 'id' ifAbsent: [nil]
!
at: key
	^arguments at: key ifAbsent: [nil]
!
at: key ifAbsent: aBlock
	^arguments at: key ifAbsent: aBlock
!
includesKey: key
	^arguments includesKey: key
!
at: key put: value
	^arguments at: key put: value
! !

!RemoteRequest methodsFor: 'typed access'!
stringAt: key
	"Answer the String argument key; fail with a RemoteError if it is missing."
	| value |
	value := arguments at: key ifAbsent: [nil].
	value isNil ifTrue: [^RemoteError signal: self command, ': missing "', key, '"'].
	^value isString ifTrue: [value] ifFalse: [value printString]
!
numberAt: key ifAbsent: aBlock
	| value |
	value := arguments at: key ifAbsent: [nil].
	value isNil ifTrue: [^aBlock value].
	value isNumber ifTrue: [^value].
	(value isString and: [value notEmpty]) ifTrue: [
		^Number readFrom: value ifFail: [RemoteError signal: self command, ': "', key, '" must be a number']].
	^RemoteError signal: self command, ': "', key, '" must be a number'
!
booleanAt: key
	| value |
	value := arguments at: key ifAbsent: [nil].
	^value == true or: [value = 'true']
!
timeoutMilliseconds: default
	^self numberAt: 'timeout' ifAbsent: [default]
!
targetAt: key
	"Answer the target argument key: a ref String (with or without @), a Point (from an object with x and y, a pair [x, y], or the String x,y), or nil."
	| value comma |
	value := arguments at: key ifAbsent: [nil].
	value isNil ifTrue: [^nil].
	value isDictionary ifTrue: [^(value at: 'x' ifAbsent: [0]) @ (value at: 'y' ifAbsent: [0])].
	(value isString not and: [value isSequenceable and: [value size = 2]]) ifTrue: [^value first @ value last].
	value isString ifFalse: [^RemoteError signal: self command, ': bad target ', value printString].
	comma := value indexOf: $,.
	(comma > 1 and: [(value first = $@) not]) ifTrue: [
		^[(Number readFrom: (value copyFrom: 1 to: comma - 1) trimBoth)
			@ (Number readFrom: (value copyFrom: comma + 1 to: value size) trimBoth)]
				on: Error do: [:e | e return: value]].
	^value
!
target
	^self targetAt: 'target'
! !

!RemoteRequest methodsFor: 'responding'!
afterResponse
	^afterResponse
!
afterResponseDo: aBlock
	"Run aBlock after the response has been sent (e.g. quit)."
	afterResponse := aBlock
! !

!RemoteRequest methodsFor: 'initialization'!
setArguments: aDictionary connection: aConnection
	arguments := aDictionary.
	connection := aConnection
! !

!RemoteRequest methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a RemoteRequest '; nextPutAll: (JSON render: arguments)
! !

!RemoteRequest class methodsFor: 'instance creation'!
on: aDictionary
	^self on: aDictionary connection: nil
!
on: aDictionary connection: aConnection
	^self new setArguments: aDictionary connection: aConnection
!
command: aString
	^self on: (Dictionary new at: 'cmd' put: aString; yourself)
! !
