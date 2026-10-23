Object subclass: #TextMark
	instanceVariableNames: 'start stop style data'
	classVariableNames: ''
	package: 'UI-Widgets'!

TextMark comment: 'I highlight a range of a TextEditor''s text: start and stop are gap positions (0 = before the first character; the characters start + 1 to stop). Styles: #result (a print-it result: soft ultramarine), #error (inverted: white on black), #pc (the debugger''s current statement: white on ultramarine; moving it glides), #pcReturn (underlined in ultramarine), #search (soft ultramarine, underlined). Editing inside me removes me; edits before me shift me; #result and #error marks disappear with any edit. data is free for the tool.'!

!TextMark methodsFor: 'accessing'!
start
	^start
!
stop
	^stop
!
setStart: a stop: b style: aSymbol
	start := a.
	stop := b.
	style := aSymbol
!
start: a stop: b
	start := a.
	stop := b
!
style
	^style
!
data
	^data
!
data: anObject
	data := anObject
!
interval
	"The characters, as a 1-based Interval."
	^start + 1 to: stop
!
isTransient
	^style == #result or: [style == #error]
!
isEmpty
	^stop <= start
! !

!TextMark methodsFor: 'looks'!
backgroundColorIn: aTheme
	style == #result ifTrue: [^aTheme color: #accentSoft].
	style == #error ifTrue: [^aTheme ink].
	style == #pc ifTrue: [^aTheme ultramarine].
	style == #search ifTrue: [^aTheme color: #busySoft].
	^nil
!
textColorIn: aTheme
	"The color that replaces the syntax colors inside me, or nil."
	(style == #error or: [style == #pc]) ifTrue: [^aTheme paper].
	^nil
!
underlineColorIn: aTheme
	style == #pcReturn ifTrue: [^aTheme ultramarine].
	style == #search ifTrue: [^aTheme ultramarine].
	^nil
! !

!TextMark methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a TextMark('; print: style; space; print: start; nextPut: $-; print: stop; nextPut: $)
! !

!TextMark class methodsFor: 'instance creation'!
start: a stop: b style: aSymbol
	^self new setStart: a stop: b style: aSymbol
! !
