Object subclass: #CuOptProgram
	instanceVariableNames: 'sense variables objective rows rowNames senses rhs integers binaries free result'
	classVariableNames: ''
	package: 'System-CUDA'!

CuOptProgram comment: 'I am a linear (or mixed-integer) program written as text, as the cuOpt window edits one, and solved by cuOpt (CuOpt). The text: the objective on the first line, then a constraint a line, then declarations; variables are names, at least 0 unless declared otherwise; # starts a comment.

	maximize 3 chairs + 5 tables
	wood: chairs <= 4
	labor: 2 tables <= 12
	3 chairs + 2 tables <= 18
	integer chairs tables        "or binary x y: integers 0 or 1; free z: no lower bound"

fromText: parses (a CuOptSyntaxError says where it stopped); solve answers the CuOptResult; valueOf: a variable, activityOf: a constraint (its left side at the solution).

	(CuOptProgram fromText: ''maximize 3x + 5y
x <= 4
2y <= 12
3x + 2y <= 18'') solve'!

!CuOptProgram class methodsFor: 'instance creation'!
fromText: aString
	^self new parse: aString
!
examples
	"name -> text of the cuOpt window's examples."
	^{'Production' -> '# A workshop makes chairs and tables: maximize the profit
maximize 3 chairs + 5 tables
wood: chairs <= 4
labor: 2 tables <= 12
machines: 3 chairs + 2 tables <= 18
'.
	'Diet' -> '# The cheapest diet with enough protein and energy
minimize 2 bread + 3 milk
protein: bread + 2 milk >= 8
energy: 3 bread + milk >= 9
'.
	'Knapsack' -> '# Pack the most value in 14 kg: a mixed-integer program
maximize 10 tent + 13 stove + 7 food + 8 water + 4 book
weight: 5 tent + 7 stove + 4 food + 5 water + 2 book <= 14
binary tent stove food water book
'.
	'Transport' -> '# Ship from two plants to three cities at the least cost
minimize 4 a1 + 6 a2 + 9 a3 + 5 b1 + 4 b2 + 7 b3
plantA: a1 + a2 + a3 <= 70
plantB: b1 + b2 + b3 <= 60
city1: a1 + b1 = 40
city2: a2 + b2 = 50
city3: a3 + b3 = 30
'}
! !

!CuOptProgram methodsFor: 'accessing'!
sense
	^sense
!
variables
	^variables
!
objective
	^objective
!
rows
	^rows
!
rowNames
	^rowNames
!
senses
	^senses
!
rhs
	^rhs
!
isInteger: aName
	^(integers includes: aName) or: [binaries includes: aName]
!
isMixedInteger
	^integers notEmpty or: [binaries notEmpty]
!
result
	^result
!
valueOf: aName
	| i |
	(result isNil or: [result values isNil]) ifTrue: [^nil].
	i := variables indexOf: aName.
	^i = 0 ifTrue: [nil] ifFalse: [result values at: i]
!
activityOf: index
	"The left side of constraint index at the solution."
	| row |
	(result isNil or: [result values isNil]) ifTrue: [^nil].
	row := rows at: index.
	^(1 to: variables size) inject: 0 into: [:s :j | s + ((row at: j) * (result values at: j))]
!
summary
	"MILP 5 variables x 1 constraint"
	^(self isMixedInteger ifTrue: ['MILP '] ifFalse: ['LP ']) , variables size printString , (variables size = 1 ifTrue: [' variable x '] ifFalse: [' variables x ']) ,
		rows size printString , (rows size = 1 ifTrue: [' constraint'] ifFalse: [' constraints'])
! !

!CuOptProgram methodsFor: 'solving'!
solve
	| lower upper types |
	lower := variables collect: [:v | (free includes: v) ifTrue: [Float infinity negated] ifFalse: [0]].
	upper := variables collect: [:v | (binaries includes: v) ifTrue: [1] ifFalse: [Float infinity]].
	types := String withAll: (variables collect: [:v | (self isInteger: v) ifTrue: [$I] ifFalse: [$C]]).
	result := CuOpt solve: objective sense: sense rows: (rows collect: [:r | r asArray]) senses: senses rhs: rhs
		lower: lower upper: upper types: types timeLimit: 10.
	^result
! !

!CuOptProgram methodsFor: 'parsing'!
parse: aString
	| lines |
	variables := OrderedCollection new.
	objective := OrderedCollection new.
	rows := OrderedCollection new.
	rowNames := OrderedCollection new.
	senses := String new.
	rhs := OrderedCollection new.
	integers := Set new.
	binaries := Set new.
	free := Set new.
	lines := aString lines.
	lines doWithIndex: [:line :n | self parseLine: (self withoutComment: line) number: n].
	sense isNil ifTrue: [^self syntaxError: 'no objective: start with maximize or minimize' line: 1].
	variables isEmpty ifTrue: [^self syntaxError: 'no variables' line: 1].
	objective := self padded: objective.
	rows := rows collect: [:r | self padded: r].
	variables := variables asArray.
	rhs := rhs asArray.
	rowNames := rowNames asArray
!
withoutComment: aLine
	| i |
	i := aLine indexOf: $#.
	^(i = 0 ifTrue: [aLine] ifFalse: [aLine copyFrom: 1 to: i - 1]) trimBoth
!
parseLine: line number: n
	| words first name rest op i |
	line isEmpty ifTrue: [^self].
	words := line substrings: ' 	,'.
	first := words first asLowercase.
	(#('subject' 'st' 's.t.' 'such') includes: first) ifTrue: [^self].
	(#('integer' 'integers' 'int' 'general' 'binary' 'binaries' 'bin' 'free') includes: first) ifTrue: [
		words allButFirst do: [:v |
			(self isName: v) ifFalse: [^self syntaxError: 'not a variable: ' , v line: n].
			self variableIndex: v.
			(first beginsWith: 'bin') ifTrue: [binaries add: v] ifFalse: [first = 'free' ifTrue: [free add: v] ifFalse: [integers add: v]]].
		^self].
	(#('maximize' 'maximise' 'max' 'minimize' 'minimise' 'min') includes: (first copyWithout: $:)) ifTrue: [
		sense notNil ifTrue: [^self syntaxError: 'a second objective' line: n].
		sense := (first beginsWith: 'max') ifTrue: [#maximize] ifFalse: [#minimize].
		rest := line copyFrom: words first size + 1 to: line size.
		rest := rest trimBoth.
		(rest notEmpty and: [rest first = $:]) ifTrue: [rest := rest allButFirst].
		objective := (self parseExpression: rest line: n) first.
		^self].
	sense isNil ifTrue: [^self syntaxError: 'start with maximize or minimize' line: n].
	"name: expression op number"
	name := nil.
	i := line indexOf: $:.
	(i > 0 and: [self isName: (line copyFrom: 1 to: i - 1) trimBoth]) ifTrue: [
		name := (line copyFrom: 1 to: i - 1) trimBoth.
		rest := line copyFrom: i + 1 to: line size]
		ifFalse: [rest := line].
	op := #('<=' '>=' '=<' '=>' '==' '<' '>' '=') detect: [:o | (rest indexOfSubCollection: o) > 0] ifNone: [nil].
	op isNil ifTrue: [^self syntaxError: 'a constraint needs <=, >= or =' line: n].
	i := rest indexOfSubCollection: op.
	self addRow: (rest copyFrom: 1 to: i - 1) op: op right: (rest copyFrom: i + op size to: rest size) name: name line: n
!
addRow: left op: op right: right name: aName line: n
	"left op right, both linear: (left - right) op 0, the constants on the right."
	| l r coeffs constant s |
	l := self parseExpression: left line: n.
	r := self parseExpression: right line: n.
	coeffs := OrderedCollection new.
	1 to: variables size do: [:j | coeffs add: (self at: j of: l first) - (self at: j of: r first)].
	constant := r last - l last.
	(coeffs allSatisfy: [:c | c = 0]) ifTrue: [^self syntaxError: 'a constraint without variables' line: n].
	s := (#('<=' '=<' '<') includes: op) ifTrue: [$L] ifFalse: [(#('>=' '=>' '>') includes: op) ifTrue: [$G] ifFalse: [$E]].
	rows add: coeffs.
	senses := senses , (String with: s).
	rhs add: constant.
	rowNames add: (aName ifNil: ['c' , rows size printString])
!
at: j of: aCollection
	^j <= aCollection size ifTrue: [aCollection at: j] ifFalse: [0]
!
padded: aCollection
	^(1 to: variables size) collect: [:j | self at: j of: aCollection]
!
parseExpression: aString line: n
	"{coefficients by variable index. constant} of a linear expression such as 3 x - 2.5 y + 4 or 3*x+y."
	| stream coeffs constant sign number name c |
	coeffs := OrderedCollection new.
	constant := 0.
	stream := ReadStream on: aString.
	[self skipSpaceIn: stream. stream atEnd] whileFalse: [
		sign := 1.
		[self skipSpaceIn: stream. stream atEnd not and: ['+-' includes: stream peek]] whileTrue: [
			stream next = $- ifTrue: [sign := sign negated]].
		self skipSpaceIn: stream.
		stream atEnd ifTrue: [^self syntaxError: 'an expression ends with a sign' line: n].
		number := nil.
		stream peek isDigit | (stream peek = $.) ifTrue: [number := self readNumberFrom: stream line: n].
		self skipSpaceIn: stream.
		(stream atEnd not and: [stream peek = $*]) ifTrue: [stream next. self skipSpaceIn: stream].
		(stream atEnd not and: [stream peek isLetter | (stream peek = $_)])
			ifTrue: [
				name := WriteStream on: String new.
				[stream atEnd not and: [(c := stream peek) isLetter or: [c isDigit or: [c = $_]]]] whileTrue: [name nextPut: stream next].
				name := name contents.
				[coeffs size < (self variableIndex: name)] whileTrue: [coeffs add: 0].
				coeffs at: (self variableIndex: name) put: (coeffs at: (self variableIndex: name)) + (sign * (number ifNil: [1]))]
			ifFalse: [
				number isNil ifTrue: [^self syntaxError: 'unexpected ' , (String with: stream peek) line: n].
				constant := constant + (sign * number)]].
	^{coeffs. constant}
!
skipSpaceIn: aStream
	[aStream atEnd not and: [aStream peek isSeparator]] whileTrue: [aStream next]
!
readNumberFrom: aStream line: n
	| s |
	s := WriteStream on: String new.
	[aStream atEnd not and: [aStream peek isDigit or: [aStream peek = $.]]] whileTrue: [s nextPut: aStream next].
	(aStream atEnd not and: [aStream peek = $e or: [aStream peek = $E]]) ifTrue: [
		s nextPut: aStream next.
		(aStream atEnd not and: ['+-' includes: aStream peek]) ifTrue: [s nextPut: aStream next].
		[aStream atEnd not and: [aStream peek isDigit]] whileTrue: [s nextPut: aStream next]].
	s := s contents.
	^[Number readFrom: s] on: Error do: [:e | e return: (self syntaxError: 'not a number: ' , s line: n)]
!
isName: aString
	^aString notEmpty and: [(aString first isLetter or: [aString first = $_]) and: [aString allSatisfy: [:c | c isLetter or: [c isDigit or: [c = $_]]]]]
!
variableIndex: aName
	| i |
	i := variables indexOf: aName.
	i > 0 ifTrue: [^i].
	variables add: aName.
	^variables size
!
syntaxError: aString line: n
	^(CuOptSyntaxError new line: n) signal: 'line ' , n printString , ': ' , aString
! !
