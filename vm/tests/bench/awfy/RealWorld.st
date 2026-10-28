"Real-world workloads (docs/benchmarks.md): each written once against the system's own class library; each answers a checksum that must be the same on every system."!

Object subclass: #RWRandom
	instanceVariableNames: 'seed'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #RWTreeNode
	instanceVariableNames: 'left right'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #RWLink
	instanceVariableNames: 'value next'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #RWOrder
	instanceVariableNames: 'id customer product quantity price'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #RWRecord
	instanceVariableNames: 'name city age score'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #RWMachine
	instanceVariableNames: 'stack sp registers'
	classVariableNames: ''
	package: 'AWFY'!

Error subclass: #RWError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #RWNode
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWNode subclass: #RWConst
	instanceVariableNames: 'value'
	classVariableNames: ''
	package: 'AWFY'!

RWNode subclass: #RWVar
	instanceVariableNames: 'index'
	classVariableNames: ''
	package: 'AWFY'!

RWNode subclass: #RWUnary
	instanceVariableNames: 'child'
	classVariableNames: ''
	package: 'AWFY'!

RWNode subclass: #RWBinary
	instanceVariableNames: 'left right'
	classVariableNames: ''
	package: 'AWFY'!

RWNode subclass: #RWIf
	instanceVariableNames: 'test then else'
	classVariableNames: ''
	package: 'AWFY'!

RWUnary subclass: #RWNeg
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWUnary subclass: #RWAbs
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWUnary subclass: #RWNot
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWUnary subclass: #RWSquare
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWUnary subclass: #RWInc
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWUnary subclass: #RWDec
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWBinary subclass: #RWAdd
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWBinary subclass: #RWSub
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWBinary subclass: #RWMul
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWBinary subclass: #RWDiv
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWBinary subclass: #RWMod
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWBinary subclass: #RWMin
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWBinary subclass: #RWMax
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWBinary subclass: #RWLess
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWBinary subclass: #RWEq
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWBinary subclass: #RWAnd
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWBinary subclass: #RWOr
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWBinary subclass: #RWXor
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RWBinary subclass: #RWShift
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #RWNodeCounter
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #BinaryTrees
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #Fasta
	instanceVariableNames: 'last'
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #KNucleotide
	instanceVariableNames: 'input'
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #ReverseComplement
	instanceVariableNames: 'input'
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #SpectralNorm
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #Pidigits
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #Strings
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #Dictionaries
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #OrderedCollections
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #Sorting
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #Enumeration
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #PrintParse
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #Exceptions
	instanceVariableNames: 'ensures'
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #Megamorphic
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #DeepRecursion
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #Perform
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

!RWRandom methodsFor: 'accessing'!
seed: anInteger
	seed := anInteger
!
next
	"Park-Miller minimal standard generator: 1 .. 2147483646."
	seed := seed * 16807 \\ 2147483647.
	^seed
!
next: n
	"Answer an Integer in 1 .. n."
	^self next \\ n + 1
! !

!RWRandom class methodsFor: 'instance creation'!
seed: anInteger
	^self new seed: anInteger
! !

!RWTreeNode methodsFor: 'accessing'!
setLeft: aNode right: anotherNode
	left := aNode.
	right := anotherNode
!
check
	left isNil ifTrue: [^1].
	^1 + left check + right check
! !

!RWTreeNode class methodsFor: 'instance creation'!
bottomUp: depth
	depth = 0 ifTrue: [^self new setLeft: nil right: nil].
	^self new setLeft: (self bottomUp: depth - 1) right: (self bottomUp: depth - 1)
! !

!RWLink methodsFor: 'accessing'!
setValue: anObject next: aLink
	value := anObject.
	next := aLink
!
value
	^value
!
next
	^next
! !

!RWLink class methodsFor: 'instance creation'!
value: anObject next: aLink
	^self new setValue: anObject next: aLink
! !

!RWOrder methodsFor: 'accessing'!
setId: i customer: c product: p quantity: q price: cents
	id := i.
	customer := c.
	product := p.
	quantity := q.
	price := cents
!
id
	^id
!
customer
	^customer
!
product
	^product
!
quantity
	^quantity
!
price
	^price
!
amount
	^quantity * price
! !

!RWRecord methodsFor: 'accessing'!
name
	^name
!
name: aString
	name := aString
!
city
	^city
!
city: aString
	city := aString
!
age
	^age
!
age: anInteger
	age := anInteger
!
score
	^score
!
score: anInteger
	score := anInteger
! !

!RWMachine methodsFor: 'instructions'!
reset
	stack := Array new: 32.
	sp := 0.
	registers := Array new: 8 withAll: 0
!
push: anInteger
	sp := sp + 1.
	stack at: sp put: anInteger
!
pop
	sp := sp - 1.
	^stack at: sp + 1
!
dup
	self push: (stack at: sp)
!
swap
	| a b |
	a := self pop.
	b := self pop.
	self push: a; push: b
!
drop
	self pop
!
add
	self push: self pop + self pop
!
sub
	| b |
	b := self pop.
	self push: self pop - b
!
mul
	self push: self pop * self pop \\ 1000003
!
max
	self push: (self pop max: self pop)
!
inc
	self push: self pop + 1
!
neg
	self push: self pop negated
!
mod: anInteger
	self push: self pop \\ anInteger
!
load: index
	self push: (registers at: index)
!
store: index
	registers at: index put: self pop
!
store: index plus: anInteger
	registers at: index put: self pop + anInteger
!
result
	^registers inject: 0 into: [:a :b | a + b]
! !

!RWNode methodsFor: 'evaluating'!
evalIn: env
	^self subclassResponsibility
!
accept: aVisitor
	^self subclassResponsibility
! !

!RWConst methodsFor: 'evaluating'!
setValue: anInteger
	value := anInteger
!
evalIn: env
	^value
!
accept: aVisitor
	^aVisitor visitConst: self
! !

!RWVar methodsFor: 'evaluating'!
setIndex: anInteger
	index := anInteger
!
evalIn: env
	^env at: index
!
accept: aVisitor
	^aVisitor visitVar: self
! !

!RWUnary methodsFor: 'accessing'!
setChild: aNode
	child := aNode
!
child
	^child
! !

!RWBinary methodsFor: 'accessing'!
setLeft: aNode right: anotherNode
	left := aNode.
	right := anotherNode
!
left
	^left
!
right
	^right
! !

!RWIf methodsFor: 'evaluating'!
setTest: aNode then: thenNode else: elseNode
	test := aNode.
	then := thenNode.
	else := elseNode
!
test
	^test
!
then
	^then
!
else
	^else
!
evalIn: env
	^(test evalIn: env) = 0
		ifTrue: [else evalIn: env]
		ifFalse: [then evalIn: env]
!
accept: aVisitor
	^aVisitor visitIf: self
! !

!RWNeg methodsFor: 'evaluating'!
evalIn: env
	^(child evalIn: env) negated
!
accept: aVisitor
	^aVisitor visitNeg: self
! !

!RWAbs methodsFor: 'evaluating'!
evalIn: env
	^(child evalIn: env) abs
!
accept: aVisitor
	^aVisitor visitAbs: self
! !

!RWNot methodsFor: 'evaluating'!
evalIn: env
	^(child evalIn: env) = 0 ifTrue: [1] ifFalse: [0]
!
accept: aVisitor
	^aVisitor visitNot: self
! !

!RWSquare methodsFor: 'evaluating'!
evalIn: env
	| x |
	x := child evalIn: env.
	^x * x bitAnd: 16rFFFFF
!
accept: aVisitor
	^aVisitor visitSquare: self
! !

!RWInc methodsFor: 'evaluating'!
evalIn: env
	^(child evalIn: env) + 1
!
accept: aVisitor
	^aVisitor visitInc: self
! !

!RWDec methodsFor: 'evaluating'!
evalIn: env
	^(child evalIn: env) - 1
!
accept: aVisitor
	^aVisitor visitDec: self
! !

!RWAdd methodsFor: 'evaluating'!
evalIn: env
	^(left evalIn: env) + (right evalIn: env) bitAnd: 16rFFFFF
!
accept: aVisitor
	^aVisitor visitAdd: self
! !

!RWSub methodsFor: 'evaluating'!
evalIn: env
	^(left evalIn: env) - (right evalIn: env)
!
accept: aVisitor
	^aVisitor visitSub: self
! !

!RWMul methodsFor: 'evaluating'!
evalIn: env
	^(left evalIn: env) * (right evalIn: env) bitAnd: 16rFFFFF
!
accept: aVisitor
	^aVisitor visitMul: self
! !

!RWDiv methodsFor: 'evaluating'!
evalIn: env
	| r |
	r := right evalIn: env.
	r = 0 ifTrue: [^0].
	^(left evalIn: env) // r
!
accept: aVisitor
	^aVisitor visitDiv: self
! !

!RWMod methodsFor: 'evaluating'!
evalIn: env
	| r |
	r := right evalIn: env.
	r = 0 ifTrue: [^0].
	^(left evalIn: env) \\ r
!
accept: aVisitor
	^aVisitor visitMod: self
! !

!RWMin methodsFor: 'evaluating'!
evalIn: env
	^(left evalIn: env) min: (right evalIn: env)
!
accept: aVisitor
	^aVisitor visitMin: self
! !

!RWMax methodsFor: 'evaluating'!
evalIn: env
	^(left evalIn: env) max: (right evalIn: env)
!
accept: aVisitor
	^aVisitor visitMax: self
! !

!RWLess methodsFor: 'evaluating'!
evalIn: env
	^(left evalIn: env) < (right evalIn: env) ifTrue: [1] ifFalse: [0]
!
accept: aVisitor
	^aVisitor visitLess: self
! !

!RWEq methodsFor: 'evaluating'!
evalIn: env
	^(left evalIn: env) = (right evalIn: env) ifTrue: [1] ifFalse: [0]
!
accept: aVisitor
	^aVisitor visitEq: self
! !

!RWAnd methodsFor: 'evaluating'!
evalIn: env
	^(left evalIn: env) bitAnd: (right evalIn: env)
!
accept: aVisitor
	^aVisitor visitAnd: self
! !

!RWOr methodsFor: 'evaluating'!
evalIn: env
	^(left evalIn: env) bitOr: (right evalIn: env)
!
accept: aVisitor
	^aVisitor visitOr: self
! !

!RWXor methodsFor: 'evaluating'!
evalIn: env
	^(left evalIn: env) bitXor: (right evalIn: env)
!
accept: aVisitor
	^aVisitor visitXor: self
! !

!RWShift methodsFor: 'evaluating'!
evalIn: env
	^((left evalIn: env) bitShift: ((right evalIn: env) bitAnd: 7)) bitAnd: 16rFFFFF
!
accept: aVisitor
	^aVisitor visitShift: self
! !

!RWNodeCounter methodsFor: 'visiting'!
visitLeaf: aNode
	^1
!
visitUnary: aNode
	^1 + (aNode child accept: self)
!
visitBinary: aNode
	^1 + (aNode left accept: self) + (aNode right accept: self)
!
visitConst: aNode
	^self visitLeaf: aNode
!
visitVar: aNode
	^self visitLeaf: aNode
!
visitIf: aNode
	^1 + (aNode test accept: self) + (aNode then accept: self) + (aNode else accept: self)
!
visitNeg: aNode
	^self visitUnary: aNode
!
visitAbs: aNode
	^self visitUnary: aNode
!
visitNot: aNode
	^self visitUnary: aNode
!
visitSquare: aNode
	^self visitUnary: aNode
!
visitInc: aNode
	^self visitUnary: aNode
!
visitDec: aNode
	^self visitUnary: aNode
!
visitAdd: aNode
	^self visitBinary: aNode
!
visitSub: aNode
	^self visitBinary: aNode
!
visitMul: aNode
	^self visitBinary: aNode
!
visitDiv: aNode
	^self visitBinary: aNode
!
visitMod: aNode
	^self visitBinary: aNode
!
visitMin: aNode
	^self visitBinary: aNode
!
visitMax: aNode
	^self visitBinary: aNode
!
visitLess: aNode
	^self visitBinary: aNode
!
visitEq: aNode
	^self visitBinary: aNode
!
visitAnd: aNode
	^self visitBinary: aNode
!
visitOr: aNode
	^self visitBinary: aNode
!
visitXor: aNode
	^self visitBinary: aNode
!
visitShift: aNode
	^self visitBinary: aNode
! !

!BinaryTrees methodsFor: 'benchmarking'!
benchmark
	^self run: 17 liveDepth: 20
!
verifyResult: result
	^result = 31806814
!
run: maxDepth liveDepth: liveDepth
	"CLBG binary-trees, its long-lived tree liveDepth deep. Answer the sum of all checks."
	| total longLived |
	total := (RWTreeNode bottomUp: maxDepth + 1) check.
	longLived := RWTreeNode bottomUp: liveDepth.
	4 to: maxDepth by: 2 do: [:depth |
		1 to: (1 bitShift: maxDepth - depth + 4) do: [:i |
			total := total + (RWTreeNode bottomUp: depth) check]].
	^total + longLived check
! !

!Fasta methodsFor: 'benchmarking'!
benchmark
	^self checksum: (self fasta: 1000000)
!
verifyResult: result
	^result = 971412559
!
checksum: aString
	| sum |
	sum := aString size.
	aString do: [:c | sum := sum + c asInteger].
	^sum
!
fasta: n
	"Answer the CLBG fasta output for n."
	| out |
	out := WriteStream on: (String new: 1024).
	last := 42.
	out nextPutAll: '>ONE Homo sapiens alu'; nextPut: Character lf.
	self repeat: self alu count: n * 2 on: out.
	out nextPutAll: '>TWO IUB ambiguity codes'; nextPut: Character lf.
	self random: self iub count: n * 3 on: out.
	out nextPutAll: '>THREE Homo sapiens frequency'; nextPut: Character lf.
	self random: self homoSapiens count: n * 5 on: out.
	^out contents
!
alu
	^'GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGGGAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGACCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAATACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCAGCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGGAGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCCAGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA'
!
iub
	^#($a 0.27 $c 0.12 $g 0.12 $t 0.27 $B 0.02 $D 0.02 $H 0.02 $K 0.02 $M 0.02 $N 0.02 $R 0.02 $S 0.02 $V 0.02 $W 0.02 $Y 0.02)
!
homoSapiens
	^#($a 0.3029549426680 $c 0.1979883004921 $g 0.1975473066391 $t 0.3015094502008)
!
repeat: aString count: n on: aStream
	"Write n characters cycling through aString, 60 to a line."
	| i |
	i := 0.
	1 to: n do: [:k |
		i := i \\ aString size + 1.
		aStream nextPut: (aString at: i).
		k \\ 60 = 0 ifTrue: [aStream nextPut: Character lf]].
	n \\ 60 = 0 ifFalse: [aStream nextPut: Character lf]
!
random: pairs count: n on: aStream
	"Write n characters drawn with the probabilities in pairs (character, probability), 60 to a line."
	| chars cumulative sum r j |
	chars := Array new: pairs size // 2.
	cumulative := Array new: pairs size // 2.
	sum := 0.0.
	1 to: chars size do: [:i |
		chars at: i put: (pairs at: i * 2 - 1).
		sum := sum + (pairs at: i * 2).
		cumulative at: i put: sum].
	1 to: n do: [:k |
		r := self nextRandom: 1.0.
		j := 1.
		[j < cumulative size and: [r >= (cumulative at: j)]] whileTrue: [j := j + 1].
		aStream nextPut: (chars at: j).
		k \\ 60 = 0 ifTrue: [aStream nextPut: Character lf]].
	n \\ 60 = 0 ifFalse: [aStream nextPut: Character lf]
!
nextRandom: max
	last := last * 3877 + 29573 \\ 139968.
	^max * last / 139968
! !

!KNucleotide methodsFor: 'benchmarking'!
initialize
	input := Fasta new fasta: 75000
!
benchmark
	^Fasta new checksum: (self report: (self sequenceIn: input))
!
verifyResult: result
	^result = 13126
!
sequenceIn: aString
	"Answer the sequence THREE of a FASTA text in upper case, without line ends."
	| in out line |
	in := ReadStream on: aString.
	[(line := in nextLine) notNil and: [(line beginsWith: '>THREE') not]] whileTrue.
	out := WriteStream on: (String new: 1024).
	[(line := in nextLine) notNil and: [line isEmpty not and: [line first ~= $>]]]
		whileTrue: [out nextPutAll: line].
	^out contents asUppercase
!
frequencies: aString length: k
	| table |
	table := Dictionary new.
	1 to: aString size - k + 1 do: [:i |
		| key |
		key := aString copyFrom: i to: i + k - 1.
		table at: key put: (table at: key ifAbsent: [0]) + 1].
	^table
!
report: sequence
	"CLBG k-nucleotide: the 1- and 2-nucleotide frequencies, most frequent first, then the counts of five sequences."
	| out |
	out := WriteStream on: (String new: 1024).
	#(1 2) do: [:k |
		| total sorted |
		total := sequence size - k + 1.
		sorted := (self frequencies: sequence length: k) associations asArray
			sort: [:a :b | a value > b value or: [a value = b value and: [a key <= b key]]].
		sorted do: [:each |
			out nextPutAll: each key; space;
				nextPutAll: (each value * 100.0 / total printShowingDecimalPlaces: 3); nextPut: Character lf].
		out nextPut: Character lf].
	#('GGT' 'GGTA' 'GGTATT' 'GGTATTTTAATT' 'GGTATTTTAATTTATAGT') do: [:s |
		out print: ((self frequencies: sequence length: s size) at: s ifAbsent: [0]);
			tab; nextPutAll: s; nextPut: Character lf].
	^out contents
! !

!ReverseComplement methodsFor: 'benchmarking'!
initialize
	input := Fasta new fasta: 1000000
!
benchmark
	^Fasta new checksum: (self reverseComplement: input)
!
verifyResult: result
	^result = 739054574
!
reverseComplement: aString
	"CLBG reverse-complement: every sequence of a FASTA text reverse-complemented, 60 characters to a line."
	| table in out sequence line |
	table := String new: 256.
	1 to: 256 do: [:i | table at: i put: (Character value: i - 1)].
	'ACGTUMRWSYKVHDBN' with: 'TGCAAKYWSRMBDHVN' do: [:from :to |
		table at: from asInteger + 1 put: to.
		table at: from asLowercase asInteger + 1 put: to].
	in := ReadStream on: aString.
	out := WriteStream on: (String new: 1024).
	sequence := WriteStream on: (String new: 1024).
	[in atEnd] whileFalse: [
		line := in nextLine.
		(line notEmpty and: [line first = $>])
			ifTrue: [
				self write: sequence contents complementedWith: table on: out.
				sequence := WriteStream on: (String new: 1024).
				out nextPutAll: line; nextPut: Character lf]
			ifFalse: [sequence nextPutAll: line]].
	self write: sequence contents complementedWith: table on: out.
	^out contents
!
write: aString complementedWith: table on: aStream
	| complement |
	complement := aString reversed collect: [:c | table at: c asInteger + 1].
	1 to: complement size by: 60 do: [:i |
		aStream nextPutAll: (complement copyFrom: i to: (i + 59 min: complement size)); nextPut: Character lf]
! !

!SpectralNorm methodsFor: 'benchmarking'!
benchmark
	^self spectralNorm: 1000
!
verifyResult: result
	^result = 1274224148
!
spectralNorm: n
	"CLBG spectral-norm; answer the norm times 10^9, rounded."
	| u v vBv vv |
	u := Array new: n withAll: 1.0.
	10 timesRepeat: [
		v := self multiplyAtAv: u.
		u := self multiplyAtAv: v].
	vBv := 0.0.
	vv := 0.0.
	1 to: n do: [:i |
		vBv := vBv + ((u at: i) * (v at: i)).
		vv := vv + ((v at: i) * (v at: i))].
	^((vBv / vv) sqrt * 1000000000) rounded
!
a: i b: j
	"The matrix element (1-based)."
	| ij |
	ij := i + j - 2.
	^1.0 / (ij * (ij + 1) // 2 + i)
!
multiplyAv: v
	| n av |
	n := v size.
	av := Array new: n.
	1 to: n do: [:i |
		| sum |
		sum := 0.0.
		1 to: n do: [:j | sum := sum + ((self a: i b: j) * (v at: j))].
		av at: i put: sum].
	^av
!
multiplyAtv: v
	| n atv |
	n := v size.
	atv := Array new: n.
	1 to: n do: [:i |
		| sum |
		sum := 0.0.
		1 to: n do: [:j | sum := sum + ((self a: j b: i) * (v at: j))].
		atv at: i put: sum].
	^atv
!
multiplyAtAv: v
	^self multiplyAtv: (self multiplyAv: v)
! !

!Pidigits methodsFor: 'benchmarking'!
benchmark
	^self pidigits: 4000
!
verifyResult: result
	^result = 7211184236
!
pidigits: n
	"CLBG pidigits: the first n digits of pi (spigot algorithm); answer their sum plus the last ten digits as an Integer."
	| out i k numer accum denom d digits |
	out := WriteStream on: (String new: n).
	numer := 1.
	accum := 0.
	denom := 1.
	i := 0.
	k := 0.
	[i < n] whileTrue: [
		| k2 |
		k := k + 1.
		k2 := k * 2 + 1.
		accum := accum + (numer * 2) * k2.
		denom := denom * k2.
		numer := numer * k.
		numer > accum ifFalse: [
			d := numer * 3 + accum // denom.
			d = (numer * 4 + accum // denom) ifTrue: [
				out print: d.
				i := i + 1.
				accum := accum - (denom * d) * 10.
				numer := numer * 10]]].
	digits := out contents.
	^(digits inject: 0 into: [:sum :c | sum + c digitValue]) + (digits copyFrom: n - 9 to: n) asNumber
! !

!Strings methodsFor: 'benchmarking'!
benchmark
	^self run: 40000
!
verifyResult: result
	^result = 10358654
!
words
	^#('the' 'quick' 'brown' 'fox' 'jumps' 'over' 'lazy' 'dog' 'Smalltalk' 'Object' 'message' 'send' 'class' 'method' 'stream' 'String' 'collection' 'dictionary' 'symbol' 'block' 'context' 'process' 'Semaphore' 'interval' 'character' 'integer' 'float' 'fraction' 'point' 'rectangle' 'color' 'The')
!
run: n
	"Write n lines of text with a WriteStream, then split, tokenize, convert case, compare, join, replace and search them."
	| rnd words out text checksum |
	rnd := RWRandom seed: 74755.
	words := self words.
	out := WriteStream on: (String new: 64).
	1 to: n do: [:i |
		out nextPutAll: 'Line '; print: i; nextPutAll: ': '.
		(rnd next: 10) + 5 timesRepeat: [out nextPutAll: (words at: (rnd next: words size)); space].
		out nextPutAll: 'end.'; cr].
	text := out contents.
	checksum := text size.
	text lines do: [:line |
		| tokens joined replaced |
		tokens := line substrings: ' :.'.
		checksum := checksum + tokens size.
		tokens do: [:t |
			| upper lower |
			upper := t asUppercase.
			lower := t asLowercase.
			upper = t ifTrue: [checksum := checksum + 1].
			(lower sameAs: upper) ifTrue: [checksum := checksum + 1].
			t < 'message' ifTrue: [checksum := checksum + 2].
			(t beginsWith: 'co') ifTrue: [checksum := checksum + 3]].
		joined := ' ' join: (tokens collect: [:t | t capitalized]).
		replaced := (joined copyReplaceAll: 'The' with: 'A') copyReplaceAll: 'String' with: 'Text'.
		checksum := checksum + replaced size + (replaced occurrencesOf: $e).
		(line includesSubstring: 'lazy dog') ifTrue: [checksum := checksum + 5].
		checksum := checksum + (line indexOf: $:) + (tokens first, '-', tokens last) size.
		checksum := checksum + ('{1}={2}' format: {tokens size. tokens last}) size].
	^checksum
! !

!Dictionaries methodsFor: 'benchmarking'!
benchmark
	^self run: 200000
!
verifyResult: result
	^result = 50002988890
!
run: n
	"n String keys and their Symbols: Dictionary and Set insertion, hits, misses, updates, removal, enumeration."
	| keys dict set symbols symbolDict sum |
	keys := (1 to: n) collect: [:i | 'key', (i * 7919 \\ n) printString].
	sum := 0.
	dict := Dictionary new.
	keys withIndexDo: [:k :i | dict at: k put: i].
	keys do: [:k | sum := sum + (dict at: k)].
	1 to: n do: [:i | sum := sum + (dict at: 'miss', i printString ifAbsent: [1])].
	keys do: [:k | dict at: k put: (dict at: k) + 1].
	keys do: [:k | (dict includesKey: k) ifTrue: [sum := sum + 1]].
	1 to: n by: 2 do: [:i | dict removeKey: (keys at: i)].
	dict keysAndValuesDo: [:k :v | sum := sum + v].
	sum := sum + dict size.
	set := Set new.
	keys do: [:k | set add: k].
	keys do: [:k | set add: k copy].
	keys do: [:k | (set includes: k) ifTrue: [sum := sum + 1]].
	sum := sum + set size.
	symbols := keys collect: [:k | k asSymbol].
	symbolDict := IdentityDictionary new.
	symbols withIndexDo: [:s :i | symbolDict at: s put: i].
	symbols do: [:s | sum := sum + (symbolDict at: s)].
	dict := Dictionary new.
	symbols do: [:s | dict at: s put: s size].
	symbols do: [:s | sum := sum + (dict at: s)].
	^sum
! !

!OrderedCollections methodsFor: 'benchmarking'!
benchmark
	^self run: 200000 rounds: 10
!
verifyResult: result
	^result = 1200915951720
!
run: n rounds: k
	"k rounds of growth at both ends, a rotating FIFO queue and a LIFO stack over n elements; breadth-first search on a 1000 x 1000 grid; insertion and removal in the middle."
	| sum |
	sum := 0.
	k timesRepeat: [sum := sum + (self queues: n)].
	^sum + (self breadthFirst: 1000) + (self insertions: 2000)
!
queues: n
	| oc sum |
	sum := 0.
	oc := OrderedCollection new.
	1 to: n do: [:i | oc add: i].
	1 to: n do: [:i | oc addFirst: i].
	sum := sum + oc size + oc first + oc last + (oc at: n // 3).
	1 to: n * 2 do: [:i |
		sum := sum + oc removeFirst.
		oc addLast: i].
	[oc isEmpty] whileFalse: [sum := sum + oc removeLast].
	^sum
!
insertions: n
	| oc sum |
	sum := 0.
	oc := OrderedCollection new.
	1 to: n do: [:i | oc add: i beforeIndex: oc size // 2 + 1].
	1 to: n // 2 do: [:i | sum := sum + (oc removeAt: oc size // 3 + 1)].
	sum := sum + (oc indexOf: n // 2) + (oc copyFrom: 10 to: 20) first.
	(oc includes: n - 1) ifTrue: [sum := sum + 1].
	^sum
!
breadthFirst: width
	"Distances from the corner of a width x width grid with 10% walls; answer their sum over the reachable cells."
	| rnd walls dist queue sum |
	rnd := RWRandom seed: 1618.
	walls := (1 to: width * width) collect: [:i | (rnd next: 10) = 1].
	walls at: 1 put: false.
	dist := Array new: width * width withAll: -1.
	dist at: 1 put: 0.
	queue := OrderedCollection new.
	queue addLast: 1.
	sum := 0.
	[queue isEmpty] whileFalse: [
		| cell x d |
		cell := queue removeFirst.
		d := dist at: cell.
		sum := sum + d.
		x := cell - 1 \\ width.
		{x > 0 ifTrue: [cell - 1]. x < (width - 1) ifTrue: [cell + 1]. cell - width. cell + width} do: [:next |
			(next notNil and: [(next between: 1 and: width * width) and: [(walls at: next) not and: [(dist at: next) < 0]]])
				ifTrue: [
					dist at: next put: d + 1.
					queue addLast: next]]].
	^sum
! !

!Sorting methodsFor: 'benchmarking'!
benchmark
	^self run: 200000
!
verifyResult: result
	^result = 2723070778149
!
run: n
	"Sort Integers, Floats, Strings and records with sort blocks; a SortedCollection."
	| rnd ints words names sum records sc |
	rnd := RWRandom seed: 31415.
	ints := (1 to: n) collect: [:i | rnd next].
	words := Strings new words.
	sum := 0.
	sum := sum + (self check: (ints copy sort: [:a :b | a <= b]) by: [:a :b | a <= b] key: [:x | x]).
	sum := sum + (self check: (ints copy sort: [:a :b | a >= b]) by: [:a :b | a >= b] key: [:x | x]).
	sum := sum + (self check: ((ints collect: [:x | x / 1000.0]) sort: [:a :b | a <= b]) by: [:a :b | a <= b] key: [:x | x truncated]).
	sum := sum + (self check: ((ints collect: [:x | x printString]) sort: [:a :b | a <= b]) by: [:a :b | a <= b] key: [:x | x size]).
	names := ints collect: [:x | (words at: x \\ words size + 1), (x \\ 1000) printString].
	sum := sum + (self check: (names copy sort: [:a :b | a caseInsensitiveLessOrEqual: b]) by: [:a :b | a caseInsensitiveLessOrEqual: b] key: [:x | x size]).
	records := names collect: [:each | RWRecord new name: each; age: each size * 7 \\ 90; score: each first asInteger; yourself].
	sum := sum + (self
		check: (records copy sort: [:a :b | a age < b age or: [a age = b age and: [a name <= b name]]])
		by: [:a :b | a age < b age or: [a age = b age and: [a name <= b name]]]
		key: [:r | r age * 1000 + r score]).
	sc := ints asOrderedCollection asSortedCollection: [:a :b | a >= b].
	sum := sum + sc first + sc last + (sc at: n // 2).
	sc := SortedCollection sortBlock: [:a :b | a <= b].
	1 to: n // 20 do: [:i | sc add: (ints at: i)].
	1 to: n // 40 do: [:i | sum := sum + sc removeFirst].
	^sum
!
check: anArray by: aSortBlock key: aBlock
	"Answer a few keys of the sorted anArray; -1 if it is not sorted."
	2 to: anArray size do: [:i | (aSortBlock value: (anArray at: i - 1) value: (anArray at: i)) ifFalse: [^-1]].
	^(aBlock value: anArray first) + (aBlock value: (anArray at: anArray size // 2)) + (aBlock value: anArray last)
! !

!Enumeration methodsFor: 'benchmarking'!
benchmark
	^self run: 200000 passes: 5
!
verifyResult: result
	^result = 39017478180
!
run: n passes: k
	"n order records, then k passes of enumeration over them."
	| rnd orders sum |
	rnd := RWRandom seed: 2718.
	orders := (1 to: n) collect: [:i |
		RWOrder new setId: i customer: (rnd next: 1000) product: (rnd next: 50) quantity: (rnd next: 20) price: (rnd next: 10000)].
	sum := 0.
	k timesRepeat: [sum := sum + (self enumerate: orders)].
	^sum
!
enumerate: orders
	"The orders through select:, collect:, inject:into:, detect:ifNone: and other enumeration protocols."
	| n sum groups |
	n := orders size.
	sum := ((orders select: [:o | o quantity > 10]) collect: [:o | o amount]) inject: 0 into: [:a :b | a + b].
	sum := sum + ((orders reject: [:o | o price < 5000]) inject: 0 into: [:a :o | a + o quantity]).
	sum := sum + (orders count: [:o | o product = 7]).
	(orders anySatisfy: [:o | o amount > 199000]) ifTrue: [sum := sum + 1].
	(orders allSatisfy: [:o | o quantity >= 1]) ifTrue: [sum := sum + 1].
	sum := sum + (orders detectMax: [:o | o amount]) id + (orders detectMin: [:o | o price]) id.
	1 to: 50 do: [:c | sum := sum + (orders detect: [:o | o customer = c] ifNone: [orders first]) id].
	sum := sum + (orders detect: [:o | o quantity > 20] ifNone: [orders last]) id.
	sum := sum + (orders collect: [:o | o customer]) asSet size.
	groups := Dictionary new.
	orders do: [:o | (groups at: o customer ifAbsentPut: [OrderedCollection new]) add: o].
	groups keysAndValuesDo: [:c :group |
		sum := sum + ((group inject: 0 into: [:a :o | a + o amount]) \\ 1000) + (group detectMax: [:o | o quantity]) quantity].
	sum := sum + ((orders with: orders reversed collect: [:a :b | a quantity * b quantity]) inject: 0 into: [:a :b | a + b]).
	orders withIndexDo: [:o :i | o customer = (i \\ 1000) ifTrue: [sum := sum + 1]].
	sum := sum + ((1 to: n) inject: 0 into: [:a :i | a + ((orders at: i) price \\ 7)]).
	sum := sum + ((orders collect: [:o | o product]) asBag occurrencesOf: 13).
	^sum
! !

!PrintParse methodsFor: 'benchmarking'!
benchmark
	^self run: 100000
!
verifyResult: result
	^result = -253003815400
!
run: n
	"Print Integers (decimal, hex, padded) and Floats, and read them back."
	| rnd sum line |
	rnd := RWRandom seed: 8128.
	sum := 0.
	1 to: n do: [:i |
		| x s f fields |
		x := rnd next - 1073741823.
		s := x printString.
		sum := sum + s size.
		(Number readFrom: s) = x ifTrue: [sum := sum + 1].
		s := x abs printStringBase: 16.
		sum := sum + s size + ((Integer readFrom: s base: 16) \\ 1000).
		s := (x abs \\ 100000) printPaddedWith: $0 to: 8.
		sum := sum + s asInteger.
		f := x / 10000.0.
		s := f printString.
		sum := sum + s size.
		(Number readFrom: s) = f ifTrue: [sum := sum + 1].
		line := String new: 40 streamContents: [:out | out print: i; nextPut: $,; print: x; nextPut: $,; print: f].
		fields := line substrings: ','.
		sum := sum + (fields first asNumber + (fields at: 2) asNumber) + (fields last asNumber * 10000) rounded].
	^sum
! !

!Exceptions methodsFor: 'benchmarking'!
benchmark
	^self run: 40000
!
verifyResult: result
	^result = 803139997
!
run: n
	"Handlers that return, pass, retry and resume; ensure: and ifCurtailed: on normal and exceptional exits; a non-local return through ensure:."
	| sum curtailed tries |
	sum := 0.
	ensures := 0.
	curtailed := 0.
	1 to: n do: [:i |
		sum := sum + ([RWError new signal: 'failed'] on: RWError do: [:e | e return: e messageText size]).
		sum := sum + ([[RWError signal] on: ZeroDivide do: [:e | e return: 1]] on: RWError do: [:e | e return: 2]).
		sum := sum + ([i / 0] on: ZeroDivide do: [:e | e return: 3]).
		sum := sum + ([[RWError signal: 'inner'] on: RWError do: [:e | e pass]] on: RWError do: [:e | e return: 4]).
		sum := sum + ([[RWError signal] ensure: [ensures := ensures + 1]] on: RWError do: [:e | e return: 5]).
		sum := sum + ([[RWError signal] ifCurtailed: [curtailed := curtailed + 1]] on: RWError do: [:e | e return: 6]).
		sum := sum + ([i + 1] ensure: [ensures := ensures + 1]).
		sum := sum + ([(Warning signal: 'warning') + 1] on: Warning do: [:e | e resume: 7]).
		sum := sum + ([[(Warning signal: 'warning') + 1] on: Warning do: [:e | e resume: e outer + 1]] on: Warning do: [:e | e resume: 8]).
		sum := sum + (self returnThroughEnsure: i).
		tries := 0.
		sum := sum + ([tries := tries + 1. tries < 3 ifTrue: [RWError signal]. tries] on: RWError do: [:e | e retry]).
		sum := sum + ([nil rwUnknownSelector] on: MessageNotUnderstood do: [:e | e return: 9]).
		sum := sum + ([self signalAtDepth: 20] on: RWError do: [:e | e return: e messageText size]).
		sum := sum + ([RWError signal] on: ZeroDivide, RWError do: [:e | e return: 10])].
	^sum + ensures + curtailed
!
returnThroughEnsure: i
	[^i \\ 7] ensure: [ensures := ensures + 1].
	^0
!
signalAtDepth: d
	d = 0 ifTrue: [^RWError signal: 'deep'].
	^(self signalAtDepth: d - 1) + 1
! !

!Megamorphic methodsFor: 'benchmarking'!
benchmark
	^self run: 20
!
verifyResult: result
	^result = 802027
!
run: passes
	"Random expression trees over 22 node classes: evaluate them (evalIn: sees every class) and count their nodes with a visitor (double dispatch)."
	| rnd trees envs sum counter |
	rnd := RWRandom seed: 1729.
	trees := (1 to: 40) collect: [:i | self randomTree: 12 with: rnd].
	envs := (1 to: 100) collect: [:i | (1 to: 4) collect: [:j | (rnd next: 2000) - 1000]].
	counter := RWNodeCounter new.
	sum := 0.
	passes timesRepeat: [
		trees do: [:tree |
			envs do: [:env | sum := sum + (tree evalIn: env) \\ 1000003].
			sum := sum + (tree accept: counter)]].
	^sum
!
randomTree: depth with: rnd
	| k |
	k := depth = 0 ifTrue: [rnd next: 2] ifFalse: [rnd next: 22].
	k = 1 ifTrue: [^RWConst new setValue: (rnd next: 100)].
	k = 2 ifTrue: [^RWVar new setIndex: (rnd next: 4)].
	k <= 8 ifTrue: [^(self unaryClasses at: k - 2) new setChild: (self randomTree: depth - 1 with: rnd)].
	k <= 21 ifTrue: [
		^(self binaryClasses at: k - 8) new
			setLeft: (self randomTree: depth - 1 with: rnd)
			right: (self randomTree: depth - 1 with: rnd)].
	^RWIf new
		setTest: (self randomTree: depth - 1 with: rnd)
		then: (self randomTree: depth - 1 with: rnd)
		else: (self randomTree: depth - 1 with: rnd)
!
unaryClasses
	^{RWNeg. RWAbs. RWNot. RWSquare. RWInc. RWDec}
!
binaryClasses
	^{RWAdd. RWSub. RWMul. RWDiv. RWMod. RWMin. RWMax. RWLess. RWEq. RWAnd. RWOr. RWXor. RWShift}
! !

!DeepRecursion methodsFor: 'benchmarking'!
benchmark
	^self run: 500000
!
verifyResult: result
	^result = 27778090000
!
run: activations
	"Linked lists built, mapped, summed and measured recursively at depths 100 to 100000 (activations per depth and operation), and a recursive flood fill that recurses 90000 deep."
	| sum |
	sum := 0.
	#(100 1000 10000 100000) do: [:depth |
		activations // depth timesRepeat: [
			| list |
			list := self build: depth.
			sum := sum + (self sum: list) + (self length: (self map: list))]].
	^sum + (self fill: (ByteArray new: 300 * 300) width: 300 x: 1 y: 1)
!
build: n
	n = 0 ifTrue: [^nil].
	^RWLink value: n next: (self build: n - 1)
!
sum: aLink
	aLink isNil ifTrue: [^0].
	^aLink value + (self sum: aLink next)
!
map: aLink
	aLink isNil ifTrue: [^nil].
	^RWLink value: aLink value * 2 next: (self map: aLink next)
!
length: aLink
	aLink isNil ifTrue: [^0].
	^1 + (self length: aLink next)
!
fill: grid width: width x: x y: y
	"Mark the empty cells reachable from x@y; answer how many."
	| index |
	(x < 1 or: [x > width or: [y < 1 or: [y > width]]]) ifTrue: [^0].
	index := y - 1 * width + x.
	(grid at: index) = 0 ifFalse: [^0].
	grid at: index put: 1.
	^1 + (self fill: grid width: width x: x + 1 y: y)
		+ (self fill: grid width: width x: x y: y + 1)
		+ (self fill: grid width: width x: x - 1 y: y)
		+ (self fill: grid width: width x: x y: y - 1)
! !

!Perform methodsFor: 'benchmarking'!
benchmark
	^self run: 800000
!
verifyResult: result
	^result = 30811631
!
program
	"A stack-machine program: selector, operand (nil for none)."
	^#(#push: 3 #load: 1 #add nil #dup nil #mul nil #push: 7 #sub nil #mod: 1009 #store: 2
		#load: 2 #load: 3 #max nil #inc nil #neg nil #push: 5 #swap nil #drop nil #store: 3
		#load: 1 #load: 2 #add nil #mod: 65536 #store: 1 #load: 4 #inc nil #store: 4)
!
run: n
	"Interpret a stack-machine program whose instructions are selectors (perform:, perform:with:), then copy records field by field through accessor selectors."
	| machine program selectors operands sum getters setters record copy |
	machine := RWMachine new.
	machine reset.
	program := self program.
	selectors := (1 to: program size by: 2) collect: [:i | program at: i].
	operands := (1 to: program size by: 2) collect: [:i | program at: i + 1].
	1 to: n do: [:i |
		machine push: i; store: 1.
		1 to: selectors size do: [:pc |
			| operand |
			operand := operands at: pc.
			operand isNil
				ifTrue: [machine perform: (selectors at: pc)]
				ifFalse: [machine perform: (selectors at: pc) with: operand]].
		machine perform: #push: withArguments: {i}.
		machine perform: #dup withArguments: #().
		machine perform: #store:plus: with: 5 with: i \\ 3.
		machine perform: #drop].
	sum := machine result.
	getters := #(#name #city #age #score).
	setters := getters collect: [:each | (each, ':') asSymbol].
	record := RWRecord new name: 'Ada'; city: 'London'; age: 36; score: 0; yourself.
	1 to: n do: [:i |
		copy := RWRecord new.
		getters with: setters do: [:get :set | copy perform: set with: (record perform: get)].
		(copy respondsTo: #score:) ifTrue: [copy perform: #score: with: i].
		sum := sum + (copy perform: #age) + (copy perform: #score) \\ 1000000007].
	^sum
! !
