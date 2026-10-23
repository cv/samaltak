Object subclass: #JSON
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Remote'!

JSON comment: 'I am the facade for reading and writing JSON (RFC 8259).

Mapping: object <-> Dictionary (String keys), array <-> Array (any SequenceableCollection when writing), string <-> String (Symbols and Characters write as strings), number <-> Integer / Float (Fractions write as Floats; NaN and infinities write as null), true/false/null <-> true/false/nil.

	JSON parse: ''{"a": [1, 2.5, "x", null]}''
	JSON render: (Dictionary new at: ''ok'' put: true; yourself)

Writing sorts object keys, so the output is deterministic. Other objects are written as their printString.'!

!JSON class methodsFor: 'reading'!
parse: aString
	"Answer the value aString encodes. Signal JSONError if it is not exactly one JSON value (surrounding whitespace allowed)."
	^(JSONReader on: aString) parseDocument
! !

!JSON class methodsFor: 'writing'!
render: anObject
	"Answer anObject as a compact JSON String (one line)."
	^String new: 64 streamContents: [:stream | (JSONWriter on: stream) write: anObject]
!
quote: aString
	"Answer aString as a JSON string literal, including the quotes."
	^String new: aString size + 2 streamContents: [:stream | (JSONWriter on: stream) writeString: aString]
! !
