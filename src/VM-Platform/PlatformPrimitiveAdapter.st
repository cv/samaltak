Object subclass: #PlatformPrimitiveAdapter
	instanceVariableNames: 'number name receiver target result bindings inputs outputs'
	classVariableNames: ''
	package: 'VM-Platform'!

PlatformPrimitiveAdapter comment: 'I expand one PlatformPrimitives declaration into an ordinary Lowtalk method. The image compiler installs it before translation or simulation; neither needs to understand adapter declarations.

A row is (number name receiver selector result ((local type) ...) [documentation]). List bindings in backend call order; input locals are decoded left to right, out parameters go last, and (true literal) or (false literal) supplies a Boolean constant without consuming a primitive argument. Use handwritten Lowtalk for bespoke validation or ownership. The range policies supply (handle, bytes, count) from the existing four-argument range checker.'!

!PlatformPrimitiveAdapter class methodsFor: 'installing'!
install: groups in: aClass
	"Compile the batch before installing anything. Reinitialization refreshes the generated methods and removes obsolete ones."
	| methods numbers names existing prefix |
	methods := OrderedCollection new.
	numbers := Set new.
	names := Set new.
	existing := Dictionary new.
	prefix := 'adapters - '.
	aClass methodsDo: [:m |
		((m category ifNil: ['']) beginsWith: prefix) ifFalse: [
			(m pragmas detect: [:p | p selector = #vmPrimitive:name:] ifNone: [nil]) ifNotNil: [:p |
				existing at: p arguments first put: m selector]]].
	groups do: [:group |
		group last do: [:row |
			| adapter method id selector |
			adapter := self new setRow: row.
			id := row first.
			selector := adapter selector.
			((numbers includes: id) or: [names includes: selector])
				ifTrue: [self error: 'Duplicate platform adapter: ', selector].
			"Loading into an older image can replace a method with the same primitive identity."
			((existing at: id ifAbsent: [selector]) = selector
				and: [(aClass includesSelector: selector) not or: [
					(((aClass compiledMethodAt: selector) category ifNil: ['']) beginsWith: prefix)
						or: [(existing at: id ifAbsent: [nil]) = selector]]])
				ifFalse: [self error: 'Platform adapter conflicts with existing method: ', selector].
			numbers add: id.
			names add: selector.
			method := Compiler compileMethod: (adapter sourceWithComment: (row at: 7 ifAbsent: ['']))
				in: aClass classified: prefix , group first.
			methods add: method]].
	aClass selectors do: [:sel |
		((names includes: sel) not and: [((aClass compiledMethodAt: sel) category ifNil: ['']) beginsWith: prefix])
			ifTrue: [aClass removeSelector: sel]].
	methods do: [:m | aClass addSelector: m selector withMethod: m]
! !

!PlatformPrimitiveAdapter methodsFor: 'initialization'!
setRow: aRow
	number := aRow first.
	name := aRow second.
	receiver := aRow third.
	target := aRow fourth.
	result := aRow at: 5.
	bindings := aRow at: 6.
	outputs := bindings select: [:b | #(#outInt #outBool) includes: b second].
	inputs := bindings reject: [:b | #(#literal #outInt #outBool) includes: b second].
	(bindings reject: [:b | b second = #literal]) = (inputs , outputs) ifFalse: [self invalid: 'out parameters must come last'].
	(inputs notEmpty and: [inputs allButLast anySatisfy: [:b | b second = #optionalInt32]])
		ifTrue: [self invalid: 'optional argument must come last'].
	(result = #pair or: [result = #wait])
		ifTrue: [
			(outputs collect: [:b | b second]) = (result = #pair ifTrue: [#(outInt outInt)] ifFalse: [#(outInt outBool)])
				ifFalse: [self invalid: 'wrong out parameters']]
		ifFalse: [outputs isEmpty ifFalse: [self invalid: 'unexpected out parameters']]
!
invalid: reason
	^self error: 'Platform adapter ', name, ': ', reason
! !

!PlatformPrimitiveAdapter methodsFor: 'generating'!
selector
	^('prim', name asString capitalized) asSymbol
!
sourceWithComment: aComment
	| s |
	s := WriteStream on: String new.
	s nextPutAll: self selector.
	aComment isEmpty ifFalse: [
		self lineOn: s.
		s nextPut: $"; nextPutAll: aComment; nextPut: $"].
	self lineOn: s.
	s nextPutAll: '<vmPrimitive: '; print: number; nextPutAll: ' name: '; print: name asString; nextPut: $>.
	(#(readSize writeSize readCount writeCount) includes: result)
		ifTrue: [self emitBufferAdapterOn: s]
		ifFalse: [self emitCallAdapterOn: s].
	^s contents
!
lineOn: s
	s nextPut: Character lf; nextPut: Character tab
!
callWith: arguments
	"Build a Lowtalk send, not a runtime call through an address."
	target numArgs = arguments size ifFalse: [self invalid: 'call arity does not match bindings'].
	arguments isEmpty ifTrue: [^receiver , ' ' , target].
	^(receiver , (String new: 64 streamContents: [:s |
		target keywords with: arguments do: [:key :arg |
			s space; nextPutAll: key; space; nextPutAll: arg]]))
!
emitLocals: names on: s
	names isEmpty ifTrue: [^self].
	(Set withAll: names) size = names size ifFalse: [self invalid: 'duplicate local'].
	self lineOn: s.
	s nextPut: $|.
	names do: [:each | s space; nextPutAll: each].
	s nextPutAll: ' |'
!
emitBufferAdapterOn: s
	| call reading size |
	bindings isEmpty ifFalse: [self invalid: 'buffer policies supply their own bindings'].
	reading := result = #readSize or: [result = #readCount].
	size := result = #readSize or: [result = #writeSize].
	call := self callWith: #('h value asInt32' 'p' 'n value asUInt64').
	self emitLocals: #(h n p) on: s.
	self lineOn: s.
	s nextPutAll: 'h := self local: ''int64_t''.'.
	self lineOn: s.
	s nextPutAll: 'n := self local: ''int64_t''.'.
	self lineOn: s.
	s nextPutAll: 'p := self rangeArgs: '; print: reading; nextPutAll: ' handle: h count: n.'.
	self lineOn: s.
	s nextPutAll: (size ifTrue: ['self answerSize: '] ifFalse: ['self answerCount: ']);
		nextPutAll: '(p notNull ifTrue: ['; nextPutAll: call;
		nextPutAll: '] ifFalse: ['; print: (size ifTrue: [-1] ifFalse: [-2]); nextPutAll: '])'
!
emitCallAdapterOn: s
	| locals call |
	locals := ((inputs , outputs) collect: [:b | b first]) , self resultLocals.
	call := self callWith: (bindings collect: [:b |
		b second = #literal
			ifTrue: [
				(b first == true or: [b first == false]) ifFalse: [self invalid: 'only Boolean literals are supported'].
				b first printString]
			ifFalse: [b first , (self castFor: b second)]]).
	self emitLocals: locals on: s.
	self emitArgumentsOn: s.
	inputs isEmpty ifFalse: [
		self lineOn: s.
		s nextPutAll: 'bad ifTrue: [^self fail].'].
	outputs do: [:b |
		self lineOn: s.
		s nextPutAll: b first; nextPutAll: ' := self local: ';
			print: (b second = #outInt ifTrue: ['int'] ifFalse: ['bool']); nextPut: $.].
	self emitResultOf: call on: s
!
castFor: type
	(#(int32 optionalInt32) includes: type) ifTrue: [^' asInt32'].
	type = #uint32 ifTrue: [^' asUInt32'].
	^''
!
decoderFor: type
	(#(int32 uint32 int64 optionalInt32) includes: type) ifTrue: [^'intArg: '].
	type = #float ifTrue: [^'floatArg: '].
	type = #address ifTrue: [^'addressArg: '].
	^self invalid: 'unknown input type ', type
!
emitArgumentsOn: s
	| count optional |
	count := inputs size.
	optional := inputs notEmpty and: [inputs last second = #optionalInt32].
	self lineOn: s.
	optional
		ifTrue: [
			s nextPutAll: 'bad := false.'.
			self lineOn: s.
			s nextPutAll: '(self argCount = '; print: count - 1; nextPutAll: ' or: [self argCount = ';
				print: count; nextPutAll: ']) ifFalse: [^self fail].']
		ifFalse: [s nextPutAll: '(self args: '; print: count; nextPutAll: ') ifFalse: [^self fail].'].
	inputs doWithIndex: [:b :i |
		self lineOn: s.
		s nextPutAll: b first; nextPutAll: ' := '.
		b second = #optionalInt32 ifTrue: [
			s nextPutAll: 'self argCount = '; print: count; nextPutAll: ' ifTrue: ['].
		s nextPutAll: 'self '; nextPutAll: (self decoderFor: b second); print: i - 1.
		b second = #optionalInt32 ifTrue: [s nextPutAll: '] ifFalse: [0]'].
		s nextPut: $.]
!
resultLocals
	result = #pair ifTrue: [^#(ok)].
	(#(nonNegativeInt64 bool ready) includes: result) ifTrue: [^#(r)].
	^#()
!
emitResultOf: call on: s
	| answer expression |
	self lineOn: s.
	result = #receiver ifTrue: [
		s nextPutAll: call; nextPut: $..
		self lineOn: s.
		^s nextPutAll: 'self answerSelf'].
	result = #pair ifTrue: [
		s nextPutAll: 'ok := '; nextPutAll: call; nextPut: $..
		self lineOn: s.
		^s nextPutAll: 'self answerPair: ok first: '; nextPutAll: outputs first first;
			nextPutAll: ' value second: '; nextPutAll: outputs second first; nextPutAll: ' value'].
	result = #wait ifTrue: [
		s nextPut: $(; nextPutAll: call; nextPutAll: ') ifFalse: [^self fail].'.
		self lineOn: s.
		^s nextPutAll: 'self answer: ('; nextPutAll: outputs second first;
			nextPutAll: ' value ifTrue: [self intOop: '; nextPutAll: outputs first first;
			nextPutAll: ' value] ifFalse: [memory nilOop])'].
	result = #int64 ifTrue: [
		^s nextPutAll: 'self answer: (memory int64Oop: '; nextPutAll: call; nextPut: $)].
	(#(nonNegativeInt64 bool ready) includes: result) ifTrue: [^self emitCheckedResultOf: call on: s].
	answer := #(ok 'Ok' handle 'Handle' nonNegative 'NonNegative' string 'String')
		indexOf: result.
	answer = 0 ifTrue: [self invalid: 'unknown result policy ', result].
	expression := target numArgs = 0 ifTrue: [call] ifFalse: ['(', call, ')'].
	s nextPutAll: 'self answer';
		nextPutAll: (#(ok 'Ok' handle 'Handle' nonNegative 'NonNegative' string 'String') at: answer + 1);
		nextPutAll: ': '; nextPutAll: expression
!
emitCheckedResultOf: call on: s
	| answer |
	s nextPutAll: 'r := '; nextPutAll: call; nextPut: $..
	self lineOn: s.
	s nextPutAll: 'r < 0 ifTrue: [^self fail].'.
	self lineOn: s.
	answer := result = #bool
		ifTrue: ['self answerBool: r ~= 0']
		ifFalse: [result = #ready
			ifTrue: ['self answer: (r > 0 ifTrue: [memory trueOop] ifFalse: [memory nilOop])']
			ifFalse: ['self answer: (memory int64Oop: r)']].
	s nextPutAll: answer
! !
