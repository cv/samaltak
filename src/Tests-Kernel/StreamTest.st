TestCase subclass: #StreamTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

StreamTest comment: 'Tests ReadStream, WriteStream and ReadWriteStream.'!

!StreamTest methodsFor: 'tests'!
testReadStream
	| s |
	s := ReadStream on: #(1 2 3 4 5).
	self assert: s next = 1.
	self assert: s peek = 2.
	self assert: (s next: 2) = #(2 3).
	self deny: s atEnd.
	self assert: s upToEnd = #(4 5).
	self assert: s atEnd.
	self assert: s next isNil.
	s reset.
	self assert: (s upTo: 3) = #(1 2).
	self assert: s next = 4.
	s position: 1.
	self assert: s next = 2.
	s skip: 1.
	self assert: s next = 4.
	s reset.
	self assert: (s peekFor: 1).
	self deny: (s peekFor: 5).
	self assert: (s skipTo: 4).
	self assert: s next = 5
!
testReadStreamOnString
	| s |
	s := 'hello world foo' readStream.
	self assert: (s upTo: $ ) = 'hello'.
	self assert: s nextWord = 'world'.
	s skipSeparators.
	self assert: s upToEnd = 'foo'.
	s := ReadStream on: ('a', (String with: Character lf), 'b').
	self assert: s nextLine = 'a'.
	self assert: s nextLine = 'b'.
	self assert: s nextLine isNil
!
testWriteStream
	| s |
	s := WriteStream on: (String new: 1).
	s nextPutAll: 'abc'; nextPut: $d; print: 42; space; tab; << 'e'; << 3.
	self assert: s contents = ('abcd42 ', (String with: Character tab), 'e3').
	s := WriteStream on: (Array new: 0).
	1 to: 100 do: [:i | s nextPut: i].
	self assert: s contents size = 100.
	self assert: s contents last = 100.
	s := WriteStream with: 'abc' copy.
	s nextPutAll: 'def'.
	self assert: s contents = 'abcdef'.
	s := WriteStream on: String new.
	s nextPutAll: 'abc'; reset; nextPutAll: 'X'.
	self assert: s contents = 'X'
!
testReadWriteStream
	| s |
	s := ReadWriteStream on: String new.
	s nextPutAll: 'hello'.
	s reset.
	self assert: (s next: 3) = 'hel'.
	self assert: s upToEnd = 'lo'.
	self assert: s contents = 'hello'
!
testStreamContents
	self assert: (Array streamContents: [:s | s nextPut: 1; nextPut: 2]) = #(1 2).
	self assert: (String new: 0 streamContents: [:s | s print: 1 / 2]) = '(1/2)'.
	self assert: (String streamContents: [:s | #(1 2 3) do: [:x | s print: x] separatedBy: [s nextPutAll: ', ']]) = '1, 2, 3'
! !
