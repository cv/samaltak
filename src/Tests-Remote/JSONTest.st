TestCase subclass: #JSONTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Remote'!

JSONTest comment: 'Tests JSON, JSONReader and JSONWriter.'!

!JSONTest methodsFor: 'tests'!
testParseLiterals
	self assert: (JSON parse: 'true') == true.
	self assert: (JSON parse: ' false ') == false.
	self assert: (JSON parse: 'null') isNil.
	self assert: (JSON parse: '0') equals: 0.
	self assert: (JSON parse: '-12') equals: -12.
	self assert: (JSON parse: '12345678901234567890') equals: 12345678901234567890.
	self assert: (JSON parse: '3.5') equals: 3.5.
	self assert: (JSON parse: '0.1') equals: 0.1.
	self assert: (JSON parse: '-2.5e-3') equals: -0.0025.
	self assert: (JSON parse: '1E3') equals: 1000.0.
	self assert: (JSON parse: '1e3') isFloat.
	self assert: (JSON parse: '1e999') isInfinite
!
testParseStrings
	| s |
	self assert: (JSON parse: '""') equals: ''.
	self assert: (JSON parse: '"a\"b\\c\/d"') equals: 'a"b\c/d'.
	self assert: (JSON parse: '"x\ny\tz"') equals: 'x', (String with: Character lf), 'y', (String with: Character tab), 'z'.
	s := JSON parse: '"éλ"'.
	self assert: s size equals: 2.
	self assert: (s at: 1) value equals: 233.
	self assert: (s at: 2) value equals: 955.
	s := JSON parse: '"😀!!"'.
	self assert: s size equals: 2.
	self assert: s first value equals: 16r1F600
!
testParseStructures
	| v |
	v := JSON parse: ' { "a" : [1, 2, {"b": null}], "c": {}, "d": [] } '.
	self assert: v isDictionary.
	self assert: (v at: 'a') size equals: 3.
	self assert: ((v at: 'a') at: 3) isDictionary.
	self assert: (((v at: 'a') at: 3) includesKey: 'b').
	self assert: (v at: 'c') isEmpty.
	self assert: (v at: 'd') equals: #().
	self assert: (v at: 'a') class equals: Array
!
testParseErrors
	#('' '{' '[1,]' '[1 2]' '"abc' 'tru' '1 2' '{"a" 1}' '{a: 1}' '01' '-' '1.' '"\x"' '"\ud800"' 'nul')
		do: [:bad | self should: [JSON parse: bad] raise: JSONError]
!
testRenderScalars
	self assert: (JSON render: nil) equals: 'null'.
	self assert: (JSON render: true) equals: 'true'.
	self assert: (JSON render: false) equals: 'false'.
	self assert: (JSON render: 42) equals: '42'.
	self assert: (JSON render: -7) equals: '-7'.
	self assert: (JSON render: 2.5) equals: '2.5'.
	self assert: (JSON render: 1/2) equals: '0.5'.
	self assert: (JSON render: Float nan) equals: 'null'.
	self assert: (JSON render: Float infinity) equals: 'null'.
	self assert: (JSON render: #sym) equals: '"sym"'.
	self assert: (JSON render: $a) equals: '"a"'
!
testRenderStrings
	self assert: (JSON render: 'a"b\c') equals: '"a\"b\\c"'.
	self assert: (JSON render: (String with: Character lf with: Character tab with: (Character value: 1))) equals: '"\n\t\u0001"'.
	self assert: (JSON render: (String with: (Character value: 955))) equals: (String with: $" with: (Character value: 955) with: $")
!
testRenderStructures
	| d |
	d := Dictionary new.
	d at: 'b' put: #(1 true nil); at: 'a' put: 'x'; at: 'c' put: Dictionary new.
	self assert: (JSON render: d) equals: '{"a":"x","b":[1,true,null],"c":{}}'.
	self assert: (JSON render: (OrderedCollection with: 1 with: 2)) equals: '[1,2]'.
	self assert: (JSON render: #()) equals: '[]'
!
testRoundTrip
	| d back |
	d := Dictionary new.
	d at: 'id' put: 17;
		at: 'cmd' put: 'eval';
		at: 'source' put: '3 + 4 "comment" \ ', (String with: Character lf);
		at: 'nested' put: (Array with: 1.5 with: -0.25 with: 12345678901234567890 with: (Dictionary new at: 'k' put: nil; yourself));
		at: 'wide' put: (String with: (Character value: 955) with: (Character value: 16r1F600)).
	back := JSON parse: (JSON render: d).
	self assert: back equals: d.
	self assert: (JSON render: back) equals: (JSON render: d)
!
testRoundTripFloats
	#(0.1 1.0 -3.75 1.0e100 2.5e-7 123456.789 0.3333333333333333) do: [:f |
		self assert: (JSON parse: (JSON render: f)) equals: f]
! !
