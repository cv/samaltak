Stream subclass: #TranscriptStream
	instanceVariableNames: 'buffer history listeners echo mutex'
	classVariableNames: ''
	package: 'System-Support'!

TranscriptStream comment: 'I am the Transcript: a write-only stream for messages to the user. Each flush (cr, show:, explicit flush) hands the pending text to standard output (when echo is on, the headless default) and to listeners: one-argument blocks the UI adds to display the text. I keep the recent history for late listeners. I am safe to use from several processes.'!

!TranscriptStream methodsFor: 'initialization'!
initialize
	buffer := WriteStream on: (String new: 256).
	history := WriteStream on: (String new: 1024).
	listeners := OrderedCollection new.
	echo := true.
	mutex := Mutex new
! !

!TranscriptStream methodsFor: 'accessing'!
nextPut: aCharacter
	mutex critical: [buffer nextPut: aCharacter].
	^aCharacter
!
nextPutAll: aString
	mutex critical: [buffer nextPutAll: aString].
	^aString
!
show: anObject
	"Append anObject (a String, or anything via displayString) and flush."
	self nextPutAll: (anObject isString ifTrue: [anObject] ifFalse: [anObject displayString]).
	self flush
!
display: anObject
	self nextPutAll: anObject displayString
!
print: anObject
	self nextPutAll: anObject printString
!
<< anObject
	self nextPutAll: (anObject isString ifTrue: [anObject] ifFalse: [anObject displayString])
!
cr
	"End the line (written as a line feed) and flush."
	self nextPut: Character lf.
	self flush
!
lf
	self cr
!
crShow: anObject
	self cr; show: anObject
!
showCr: anObject
	self show: anObject; cr
!
contents
	"Answer the recent history."
	^mutex critical: [history contents, buffer contents]
!
clear
	mutex critical: [
		buffer resetContents.
		history := WriteStream on: (String new: 1024)]
!
echo
	^echo
!
echo: aBoolean
	"Whether to copy the text to standard output."
	echo := aBoolean
!
addListener: aBlock
	"aBlock receives each flushed piece of text."
	mutex critical: [listeners add: aBlock]
!
removeListener: aBlock
	mutex critical: [listeners remove: aBlock ifAbsent: []]
! !

!TranscriptStream methodsFor: 'flushing'!
flush
	| text receivers |
	mutex critical: [
		text := buffer contents.
		buffer resetContents.
		text isEmpty ifFalse: [
			history nextPutAll: text.
			history size > 100000 ifTrue: [
				| keep |
				keep := history contents last: 50000.
				history := WriteStream on: (String new: 60000).
				history nextPutAll: keep]].
		receivers := listeners copy].
	text isEmpty ifTrue: [^self].
	echo ifTrue: [Smalltalk vm stdoutWrite: text].
	receivers do: [:each | each value: text]
!
endEntry
	self flush
! !

!TranscriptStream methodsFor: 'testing'!
atEnd
	^true
!
isTranscript
	^true
! !
