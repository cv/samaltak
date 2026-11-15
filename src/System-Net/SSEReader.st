Object subclass: #SSEReader
	instanceVariableNames: 'buffer eventName data handler'
	classVariableNames: ''
	package: 'System-Net'!

SSEReader comment: 'I decode a text/event-stream (server-sent events) fed to me in pieces of any size: for each event I evaluate my handler with its name (''message'' if it has none) and its data (data lines joined with line feeds). Lines end in CR LF, LF or CR; comments and other fields are ignored.

	reader := SSEReader do: [:event :data | Transcript showln: event, '' '', data].
	reader feed: ''event: ping'', String lf; feed: ''data: 1'', String lf, String lf'!

!SSEReader methodsFor: 'initialization'!
setHandler: aBlock
	handler := aBlock.
	buffer := ''.
	data := OrderedCollection new
! !

!SSEReader methodsFor: 'reading'!
feed: aString
	| line |
	buffer := buffer, aString.
	[(line := self nextLine) notNil] whileTrue: [self processLine: line]
! !

!SSEReader methodsFor: 'private'!
nextLine
	"Remove the first complete line from buffer and answer it, or nil (a CR at the end may be the start of a CR LF)."
	| i line |
	i := buffer findFirst: [:c | c = Character cr or: [c = Character lf]].
	(i = 0 or: [i = buffer size and: [(buffer at: i) = Character cr]]) ifTrue: [^nil].
	line := buffer copyFrom: 1 to: i - 1.
	((buffer at: i) = Character cr and: [(buffer at: i + 1) = Character lf]) ifTrue: [i := i + 1].
	buffer := buffer copyFrom: i + 1 to: buffer size.
	^line
!
processLine: line
	| colon field value |
	line isEmpty ifTrue: [^self dispatch].
	colon := line indexOf: $:.
	colon = 1 ifTrue: [^self].
	colon = 0
		ifTrue: [
			field := line.
			value := '']
		ifFalse: [
			field := line copyFrom: 1 to: colon - 1.
			value := line copyFrom: colon + 1 to: line size.
			(value notEmpty and: [value first = Character space]) ifTrue: [value := value copyFrom: 2 to: value size]].
	field = 'event' ifTrue: [^eventName := value].
	field = 'data' ifTrue: [^data add: value]
!
dispatch
	| name text |
	name := eventName ifNil: ['message'].
	eventName := nil.
	data isEmpty ifTrue: [^self].
	text := String new: 64 streamContents: [:s | data do: [:each | s nextPutAll: each] separatedBy: [s lf]].
	data := OrderedCollection new.
	handler value: name value: text
! !

!SSEReader class methodsFor: 'instance creation'!
do: aBlock
	"A reader that evaluates aBlock with the name and data of each event."
	^self new setHandler: aBlock
! !
