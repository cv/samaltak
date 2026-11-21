Object subclass: #Asn1Der
	instanceVariableNames: 'bytes position limit depth'
	classVariableNames: ''
	package: 'System-TLS'!

Asn1Der comment: 'I read DER (X.690''s distinguished encoding rules) from a ByteArray: a cursor over a run of elements, as many as are left before my limit. Strict: a length must be definite and minimal and stay within its enclosing element, tags single-byte, INTEGERs minimal, BOOLEANs 00 or FF, BIT STRINGs with zero unused bits, nesting at most maxDepth deep. Anything else signals TLSError (''DER: ...''); reading never goes past my limit.

Entering a constructed element (readSequence, readSet, readExplicit:) answers a reader over its contents, one level deeper; the readers of primitive elements answer Smalltalk values:

	r := (Asn1Der on: bytes) readSequence.
	n := r readInteger.	"an Integer"
	oid := r readOid.	"''1.2.840.113549.1.1.11''"
	t := r readTime.	"UTCTime or GeneralizedTime: seconds since 1970 UTC"
	r expectEnd

readElementBytes answers the whole next element as encoded (to verify a signature over it); peekTag, atEnd, skip and nextIs: look ahead. Times are Integers of seconds since 1970-01-01 UTC.'!

!Asn1Der methodsFor: 'testing'!
atEnd
	^position > limit
!
peekTag
	"The tag of the next element, nil at the end."
	^self atEnd ifTrue: [nil] ifFalse: [bytes at: position]
!
nextIs: tag
	^self peekTag = tag
! !

!Asn1Der methodsFor: 'reading'!
enter: tag
	"A reader over the contents of the next element, which must be the constructed tag."
	| range |
	(tag bitAnd: 16r20) = 0 ifTrue: [^self error: 'not a constructed tag'].
	depth >= self class maxDepth ifTrue: [^self fail: 'nested too deeply'].
	range := self readHeader: tag.
	^self class basicNew setBytes: bytes from: (range at: 1) to: (range at: 2) depth: depth + 1
!
readSequence
	^self enter: 16r30
!
readSet
	^self enter: 16r31
!
readExplicit: n
	"The reader over the contents of context-specific constructed tag [n]."
	^self enter: 16rA0 + n
!
readOptionalExplicit: n
	"As readExplicit:, nil if the next element is not [n]."
	^(self nextIs: 16rA0 + n) ifTrue: [self readExplicit: n] ifFalse: [nil]
!
readContentsOf: tag
	"The contents of the next element, which must have tag, as a ByteArray."
	| range |
	range := self readHeader: tag.
	^bytes copyFrom: (range at: 1) to: (range at: 2)
!
readElementBytes
	"The next element, whatever its tag, as encoded (header and contents)."
	| start range |
	start := position.
	self atEnd ifTrue: [^self fail: 'no element'].
	range := self readHeader: (bytes at: position).
	^bytes copyFrom: start to: (range at: 2)
!
skip
	"Skip the next element."
	self atEnd ifTrue: [^self fail: 'no element'].
	self readHeader: (bytes at: position)
!
expectEnd
	self atEnd ifFalse: [^self fail: 'unexpected data after the last element']
! !

!Asn1Der methodsFor: 'reading values'!
readInteger
	^self readIntegerTagged: 2
!
readIntegerTagged: tag
	"A two's complement INTEGER (or one with an implicit tag), minimal as DER wants it."
	| c value |
	c := self readContentsOf: tag.
	c isEmpty ifTrue: [^self fail: 'empty INTEGER'].
	(c size > 1 and: [((c at: 1) = 0 and: [(c at: 2) < 128]) or: [(c at: 1) = 255 and: [(c at: 2) >= 128]]])
		ifTrue: [^self fail: 'INTEGER not minimal'].
	value := 0.
	c do: [:b | value := (value bitShift: 8) + b].
	(c at: 1) >= 128 ifTrue: [value := value - (1 bitShift: 8 * c size)].
	^value
!
readBoolean
	| c |
	c := self readContentsOf: 1.
	(c size = 1 and: [(c at: 1) = 0 or: [(c at: 1) = 255]]) ifFalse: [^self fail: 'bad BOOLEAN'].
	^(c at: 1) = 255
!
readNull
	(self readContentsOf: 5) isEmpty ifFalse: [^self fail: 'bad NULL'].
	^nil
!
readOid
	"An OBJECT IDENTIFIER in dotted form, e.g. '2.5.4.3'."
	| c out value first |
	c := self readContentsOf: 6.
	c isEmpty ifTrue: [^self fail: 'empty OBJECT IDENTIFIER'].
	(c last bitAnd: 128) = 0 ifFalse: [^self fail: 'truncated OBJECT IDENTIFIER'].
	out := WriteStream on: (String new: c size * 3).
	value := 0.
	first := true.
	c doWithIndex: [:b :i |
		(value = 0 and: [b = 128]) ifTrue: [^self fail: 'OBJECT IDENTIFIER not minimal'].
		value := (value bitShift: 7) + (b bitAnd: 127).
		b < 128 ifTrue: [
			first
				ifTrue: [
					value < 80
						ifTrue: [out print: value // 40; nextPut: $.; print: value \\ 40]
						ifFalse: [out nextPutAll: '2.'; print: value - 80].
					first := false]
				ifFalse: [out nextPut: $.; print: value].
			value := 0]].
	^out contents
!
readOctetString
	^self readContentsOf: 4
!
readBitString
	"The bytes of a BIT STRING that is a whole number of bytes (keys, signatures)."
	| c |
	c := self readContentsOf: 3.
	(c notEmpty and: [(c at: 1) = 0]) ifFalse: [^self fail: 'BIT STRING not a whole number of bytes'].
	^c copyFrom: 2 to: c size
!
readNamedBits
	"A BIT STRING of named bits as an Integer: bit n of the string (0 = the first) is (1 bitShift: n)."
	| c unused mask value |
	c := self readContentsOf: 3.
	c isEmpty ifTrue: [^self fail: 'empty BIT STRING'].
	unused := c at: 1.
	(unused <= 7 and: [c size > 1 or: [unused = 0]]) ifFalse: [^self fail: 'bad BIT STRING'].
	(c size > 1 and: [((c at: c size) bitAnd: (1 bitShift: unused) - 1) ~= 0]) ifTrue: [^self fail: 'BIT STRING unused bits not zero'].
	value := 0.
	2 to: c size do: [:i |
		mask := c at: i.
		0 to: 7 do: [:bit |
			((mask bitShift: bit - 7) bitAnd: 1) = 1 ifTrue: [value := value bitOr: (1 bitShift: (i - 2) * 8 + bit)]]].
	^value
!
readString
	"A character string of the kinds X.509 names use, as a String: UTF8String, PrintableString, IA5String, VisibleString, NumericString, TeletexString (taken as Latin-1), BMPString, UniversalString."
	| tag c |
	tag := self peekTag.
	c := self readContentsOf: tag.
	tag = 12 ifTrue: [^[c utf8Decoded] on: Error do: [:e | self fail: 'bad UTF8String']].
	(#(18 19 20 22 26) includes: tag) ifTrue: [^c asString].
	tag = 30 ifTrue: [^self decodeWide: c width: 2].
	tag = 28 ifTrue: [^self decodeWide: c width: 4].
	^self fail: 'not a string (tag ', tag printString, ')'
!
readTime
	"A UTCTime or GeneralizedTime in DER's form (seconds, Z, no fraction), as seconds since 1970 UTC."
	| tag s year i |
	tag := self peekTag.
	s := (self readContentsOf: tag) asString.
	tag = 23
		ifTrue: [
			s size = 13 ifFalse: [^self fail: 'bad UTCTime'].
			year := self digits: s from: 1 to: 2.
			year := year < 50 ifTrue: [2000 + year] ifFalse: [1900 + year].
			i := 3]
		ifFalse: [
			(tag = 24 and: [s size = 15]) ifFalse: [^self fail: 'bad time'].
			year := self digits: s from: 1 to: 4.
			i := 5].
	s last = $Z ifFalse: [^self fail: 'time not in UTC'].
	^self class
		secondsForYear: year
		month: (self digits: s from: i to: i + 1)
		day: (self digits: s from: i + 2 to: i + 3)
		hour: (self digits: s from: i + 4 to: i + 5)
		minute: (self digits: s from: i + 6 to: i + 7)
		second: (self digits: s from: i + 8 to: i + 9)
		ifInvalid: [self fail: 'bad time']
! !

!Asn1Der methodsFor: 'private'!
setBytes: aByteArray from: start to: stop depth: n
	bytes := aByteArray.
	position := start.
	limit := stop.
	depth := n
!
fail: aString
	^TLSError signal: 'DER: ', aString
!
readHeader: tag
	"Read the next element's header, which must have tag, and skip it; answer the first and last index of its contents."
	| first length n start |
	self atEnd ifTrue: [^self fail: 'expected tag ', tag printString, ', found the end'].
	(bytes at: position) = tag ifFalse: [^self fail: 'expected tag ', tag printString, ', found ', (bytes at: position) printString].
	(tag bitAnd: 31) = 31 ifTrue: [^self fail: 'multi-byte tag'].
	position + 1 > limit ifTrue: [^self fail: 'truncated'].
	first := bytes at: position + 1.
	position := position + 2.
	first < 128
		ifTrue: [length := first]
		ifFalse: [
			n := first - 128.
			(n between: 1 and: 4) ifFalse: [^self fail: 'unsupported length'].
			position + n - 1 > limit ifTrue: [^self fail: 'truncated'].
			(bytes at: position) = 0 ifTrue: [^self fail: 'length not minimal'].
			length := 0.
			1 to: n do: [:k | length := (length bitShift: 8) + (bytes at: position + k - 1)].
			length < 128 ifTrue: [^self fail: 'length not minimal'].
			position := position + n].
	length > (limit - position + 1) ifTrue: [^self fail: 'length beyond the enclosing element'].
	start := position.
	position := position + length.
	^{start. start + length - 1}
!
digits: aString from: start to: stop
	| v |
	v := 0.
	start to: stop do: [:i |
		(aString at: i) isDigit ifFalse: [^self fail: 'bad time'].
		v := v * 10 + (aString at: i) digitValue].
	^v
!
decodeWide: aByteArray width: n
	| out code |
	aByteArray size \\ n = 0 ifFalse: [^self fail: 'bad wide string'].
	out := WriteStream on: (String new: aByteArray size // n).
	1 to: aByteArray size by: n do: [:i |
		code := 0.
		i to: i + n - 1 do: [:k | code := (code bitShift: 8) + (aByteArray at: k)].
		(code > 16r10FFFF or: [code between: 16rD800 and: 16rDFFF]) ifTrue: [^self fail: 'bad wide string'].
		out nextPut: (Character value: code)].
	^out contents
! !

!Asn1Der class methodsFor: 'instance creation'!
on: aByteArray
	"A reader over all of aByteArray."
	^self basicNew setBytes: aByteArray from: 1 to: aByteArray size depth: 0
! !

!Asn1Der class methodsFor: 'constants'!
maxDepth
	"How deep constructed elements may nest. X.509 needs about 10."
	^32
! !

!Asn1Der class methodsFor: 'time'!
secondsForYear: year month: month day: day hour: hour minute: minute second: second ifInvalid: aBlock
	"Seconds since 1970-01-01 00:00 UTC, or aBlock's value if a field is out of range."
	((month between: 1 and: 12) and: [(day between: 1 and: (Date daysInMonth: month forYear: year))
		and: [(hour between: 0 and: 23) and: [(minute between: 0 and: 59) and: [second between: 0 and: 59]]]])
			ifFalse: [^aBlock value].
	^(((Date year: year month: month day: day) daysSinceEpoch * 24 + hour) * 60 + minute) * 60 + second
! !
