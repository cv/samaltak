TestCase subclass: #SSEReaderTest
	instanceVariableNames: 'events reader'
	classVariableNames: ''
	package: 'Tests-Net'!

SSEReaderTest comment: 'Tests SSEReader: line endings, multi-line data, comments, and events split anywhere across pieces.'!

!SSEReaderTest methodsFor: 'running'!
setUp
	events := OrderedCollection new.
	reader := SSEReader do: [:name :data | events add: name -> data]
!
lf
	^String lf
!
crlf
	^String crlf
! !

!SSEReaderTest methodsFor: 'tests'!
testEvents
	reader feed: 'event: a', self lf, 'data: {"x":1}', self lf, self lf, 'data: plain', self lf, self lf.
	self assert: events asArray equals: {'a' -> '{"x":1}'. 'message' -> 'plain'}
!
testCRLFAndMultiLineData
	reader feed: ': comment', self crlf, 'event: b', self crlf, 'data: one', self crlf, 'data:two', self crlf, 'id: 7', self crlf, self crlf.
	self assert: events asArray equals: {'b' -> ('one', self lf, 'two')}
!
testSplitAnywhere
	| text |
	text := 'event: a', self crlf, 'data: 12345', self crlf, self crlf, 'event: b', self crlf, 'data: 6', self crlf, self crlf.
	1 to: text size do: [:i | reader feed: (text copyFrom: i to: i)].
	self assert: events asArray equals: {'a' -> '12345'. 'b' -> '6'}
!
testIncompleteEventWaits
	reader feed: 'event: a', self lf, 'data: x', self lf.
	self assert: events isEmpty.
	reader feed: self lf.
	self assert: events size equals: 1
!
testEventWithoutDataIsDropped
	reader feed: 'event: a', self lf, self lf, 'data: y', self lf, self lf.
	self assert: events asArray equals: {'message' -> 'y'}
! !
