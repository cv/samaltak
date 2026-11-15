Object subclass: #TArchMerge
	instanceVariableNames: 'defaultArch otherArch'
	classVariableNames: ''
	package: 'VM-Translator'!

TArchMerge comment: 'I merge the translations of one set of modules for two CPUs (VMTranslator>>translate: the default CPU, arm64, and x86_64) into one set of files that serves both, so that the C compiler of each CPU sees exactly that CPU''s translation:

- a file the same for both stays as it is; a file for one CPU only (a module''s targetArch) is guarded by its condition (VMTranslator class>>archGuardFor:);
- a file that differs is merged function by function (both list their functions in the same order, each after a /* Module>>selector */ line: VMTranslator>>cFileFor:functions:): a function that differs is there twice, #if defined(__x86_64__) its x86_64 translation #else the other #endif; what is outside functions (the header, globals, prototypes) is merged line by line (a longest common subsequence), each difference guarded the same way, each guarded part balanced in its own preprocessor conditionals;
- sources.mk lists the files for one CPU under it (VM_CORE_SOURCES_X86_64), the build adds those of its uname -m.'!

!TArchMerge methodsFor: 'merging'!
merge: anArray
	"anArray: an arch -> files (name -> contents) per CPU, the default CPU (VMTranslator class>>targetArchs first) first. Answer the merged files."
	| defaultFiles otherFiles names result |
	anArray size = 2 ifFalse: [^self error: 'TArchMerge merges two CPUs'].
	defaultArch := anArray first key.
	otherArch := anArray last key.
	defaultFiles := Dictionary new.
	anArray first value do: [:a | defaultFiles at: a key put: a value].
	otherFiles := Dictionary new.
	anArray last value do: [:a | otherFiles at: a key put: a value].
	names := OrderedCollection new.
	anArray first value do: [:a | names add: a key].
	anArray last value do: [:a | (names includes: a key) ifFalse: [names add: a key]].
	result := OrderedCollection new.
	names do: [:name |
		| d o |
		d := defaultFiles at: name ifAbsent: [nil].
		o := otherFiles at: name ifAbsent: [nil].
		result add: name -> (name = 'sources.mk'
			ifTrue: [self mergeSources: d with: o]
			ifFalse: [
				d isNil
					ifTrue: [self guard: o arch: otherArch]
					ifFalse: [
						o isNil
							ifTrue: [self guard: d arch: defaultArch]
							ifFalse: [d = o ifTrue: [d] ifFalse: [self mergeText: d with: o]]]])].
	^result
!
guard: aString arch: anArch
	"aString for anArch only."
	^'#if ' , (VMTranslator archGuardFor: anArch) , (String with: Character lf) , aString , '#endif' , (String with: Character lf)
!
mergeText: defaultText with: otherText
	"C that differs between the CPUs: its functions aligned by their /* Module>>selector */ lines, the rest line by line."
	| d o out keys |
	d := self chunksOf: (self linesOf: defaultText).
	o := self chunksOf: (self linesOf: otherText).
	out := OrderedCollection new.
	keys := self lcsOf: (d collect: [:c | c key]) and: (o collect: [:c | c key]).
	self align: d with: o pairs: keys do: [:dc :oc |
		dc isNil
			ifTrue: [self emit: oc value only: otherArch on: out]
			ifFalse: [
				oc isNil
					ifTrue: [self emit: dc value only: defaultArch on: out]
					ifFalse: [
						dc value = oc value
							ifTrue: [out addAll: dc value]
							ifFalse: [
								dc key isEmpty
									ifTrue: [out addAll: (self mergeLines: dc value with: oc value)]
									ifFalse: [self emit: dc value or: oc value on: out]]]]].
	^self textOf: out
! !

!TArchMerge methodsFor: 'lines'!
linesOf: aString
	"aString's lines, split at line feeds (generated text ends with one)."
	| lines start i lf |
	lines := OrderedCollection new.
	lf := Character lf.
	start := 1.
	[(i := aString indexOf: lf startingAt: start) > 0] whileTrue: [
		lines add: (aString copyFrom: start to: i - 1).
		start := i + 1].
	start <= aString size ifTrue: [lines add: (aString copyFrom: start to: aString size)].
	^lines asArray
!
textOf: aCollectionOfLines
	| s |
	s := WriteStream on: (String new: 100000).
	aCollectionOfLines do: [:line | s nextPutAll: line; lf].
	^s contents
!
chunksOf: lines
	"key -> lines: what comes before the first function (key ''), then each function from its /* Module>>selector */ line (its key) on."
	| chunks key current |
	chunks := OrderedCollection new.
	key := ''.
	current := OrderedCollection new.
	lines do: [:line |
		(self isFunctionLine: line) ifTrue: [
			chunks add: key -> current asArray.
			key := line.
			current := OrderedCollection new].
		current add: line].
	chunks add: key -> current asArray.
	^chunks asArray
!
isFunctionLine: aString
	^(aString beginsWith: '/* ') and: [(aString endsWith: ' */') and: [(aString includesSubstring: '>>') and: [(aString includes: Character space) and: [(aString copyFrom: 4 to: aString size - 3) noneSatisfy: [:c | c = Character space]]]]]
! !

!TArchMerge methodsFor: 'guards'!
emit: lines only: anArch on: out
	out add: '#if ' , (VMTranslator archGuardFor: anArch).
	out addAll: lines.
	out add: '#endif'
!
emit: defaultLines or: otherLines on: out
	"The other CPU's lines under its condition, the default's under #else."
	defaultLines isEmpty ifTrue: [^self emit: otherLines only: otherArch on: out].
	otherLines isEmpty ifTrue: [^self emit: defaultLines only: defaultArch on: out].
	out add: '#if ' , (VMTranslator archGuardFor: otherArch).
	out addAll: otherLines.
	out add: '#else'.
	out addAll: defaultLines.
	out add: '#endif'
!
isBalanced: lines
	"Whether lines open and close their own preprocessor conditionals (so that a guard may enclose them)."
	| depth |
	depth := 0.
	lines do: [:line |
		| t |
		t := line trimBoth.
		((t beginsWith: '#if') or: [t beginsWith: '# if']) ifTrue: [depth := depth + 1].
		((t beginsWith: '#else') or: [t beginsWith: '#elif']) ifTrue: [depth = 0 ifTrue: [^false]].
		(t beginsWith: '#endif') ifTrue: [
			depth := depth - 1.
			depth < 0 ifTrue: [^false]]].
	^depth = 0
! !

!TArchMerge methodsFor: 'common subsequence'!
lcsOf: a and: b
	"Index pairs (i -> j) of a longest common subsequence of the sequences a and b (compared with =), in order."
	| n m pre suf pairs mid |
	n := a size.
	m := b size.
	pre := 0.
	[pre < n and: [pre < m and: [(a at: pre + 1) = (b at: pre + 1)]]] whileTrue: [pre := pre + 1].
	suf := 0.
	[suf < (n - pre) and: [suf < (m - pre) and: [(a at: n - suf) = (b at: m - suf)]]] whileTrue: [suf := suf + 1].
	pairs := OrderedCollection new.
	1 to: pre do: [:i | pairs add: i -> i].
	mid := self lcsOf: a from: pre + 1 to: n - suf and: b from: pre + 1 to: m - suf.
	pairs addAll: mid.
	1 to: suf do: [:k | pairs add: (n - suf + k) -> (m - suf + k)].
	^pairs
!
lcsOf: a from: a1 to: a2 and: b from: b1 to: b2
	"Dynamic programming over the hashes of the elements (the middle, after the common prefix and suffix are gone)."
	| n m ha hb table pairs i j w |
	n := a2 - a1 + 1.
	m := b2 - b1 + 1.
	(n <= 0 or: [m <= 0]) ifTrue: [^#()].
	ha := (a1 to: a2) collect: [:k | (a at: k) hash].
	hb := (b1 to: b2) collect: [:k | (b at: k) hash].
	w := m + 1.
	table := Array new: (n + 1) * w withAll: 0.
	n to: 1 by: -1 do: [:x |
		m to: 1 by: -1 do: [:y |
			table at: (x - 1) * w + y put: (((ha at: x) = (hb at: y) and: [(a at: a1 + x - 1) = (b at: b1 + y - 1)])
				ifTrue: [(table at: x * w + y + 1) + 1]
				ifFalse: [(table at: x * w + y) max: (table at: (x - 1) * w + y + 1)])]].
	pairs := OrderedCollection new.
	i := 1.
	j := 1.
	[i <= n and: [j <= m]] whileTrue: [
		((ha at: i) = (hb at: j) and: [(a at: a1 + i - 1) = (b at: b1 + j - 1)])
			ifTrue: [
				pairs add: (a1 + i - 1) -> (b1 + j - 1).
				i := i + 1.
				j := j + 1]
			ifFalse: [
				(table at: i * w + j) >= (table at: (i - 1) * w + j + 1)
					ifTrue: [i := i + 1]
					ifFalse: [j := j + 1]]].
	^pairs
!
align: d with: o pairs: pairs do: aBlock
	"aBlock with each element of d and o in order: matched pairs together, the others with nil beside them."
	| i j |
	i := 1.
	j := 1.
	pairs do: [:p |
		[i < p key] whileTrue: [aBlock value: (d at: i) value: nil. i := i + 1].
		[j < p value] whileTrue: [aBlock value: nil value: (o at: j). j := j + 1].
		aBlock value: (d at: i) value: (o at: j).
		i := i + 1.
		j := j + 1].
	[i <= d size] whileTrue: [aBlock value: (d at: i) value: nil. i := i + 1].
	[j <= o size] whileTrue: [aBlock value: nil value: (o at: j). j := j + 1]
!
mergeLines: defaultLines with: otherLines
	"The lines of both, common ones once, each difference guarded; a difference that is not balanced in its preprocessor conditionals takes in the common lines and differences after it until it is."
	| pairs hunks out i j k start |
	pairs := self lcsOf: defaultLines and: otherLines.
	"hunks: (common lines) or (default lines -> other lines), in order"
	hunks := OrderedCollection new.
	i := 1.
	j := 1.
	pairs do: [:p |
		(i < p key or: [j < p value]) ifTrue: [
			hunks add: (defaultLines copyFrom: i to: p key - 1) -> (otherLines copyFrom: j to: p value - 1)].
		hunks add: (Array with: (defaultLines at: p key)).
		i := p key + 1.
		j := p value + 1].
	(i <= defaultLines size or: [j <= otherLines size]) ifTrue: [
		hunks add: (defaultLines copyFrom: i to: defaultLines size) -> (otherLines copyFrom: j to: otherLines size)].
	out := OrderedCollection new.
	k := 1.
	[k <= hunks size] whileTrue: [
		(hunks at: k) isArray
			ifTrue: [out addAll: (hunks at: k). k := k + 1]
			ifFalse: [
				| dl ol |
				start := k.
				dl := OrderedCollection withAll: (hunks at: k) key.
				ol := OrderedCollection withAll: (hunks at: k) value.
				k := k + 1.
				[((self isBalanced: dl) and: [self isBalanced: ol]) or: [k > hunks size]] whileFalse: [
					(hunks at: k) isArray
						ifTrue: [dl addAll: (hunks at: k). ol addAll: (hunks at: k)]
						ifFalse: [dl addAll: (hunks at: k) key. ol addAll: (hunks at: k) value].
					k := k + 1].
				((self isBalanced: dl) and: [self isBalanced: ol]) ifFalse: [
					"nothing after it balances it: the whole text, guarded"
					^(OrderedCollection new)
						add: '#if ' , (VMTranslator archGuardFor: otherArch);
						addAll: otherLines;
						add: '#else';
						addAll: defaultLines;
						add: '#endif';
						yourself].
				self emit: dl asArray or: ol asArray on: out]].
	^out
! !

!TArchMerge methodsFor: 'sources.mk'!
mergeSources: defaultText with: otherText
	"Each list of sources.mk with the files of both CPUs; a file for one CPU only goes to that CPU's list (VM_CORE_SOURCES_X86_64...)."
	| d o names s archOnly |
	d := self listsOf: defaultText.
	o := self listsOf: otherText.
	names := OrderedCollection new.
	d do: [:a | names add: a key].
	o do: [:a | (names includes: a key) ifFalse: [names add: a key]].
	archOnly := Dictionary new.
	s := WriteStream on: String new.
	s nextPutAll: (self linesOf: defaultText) first; lf.
	names do: [:name |
		| df of common |
		df := (d detect: [:a | a key = name] ifNone: [name -> #()]) value.
		of := (o detect: [:a | a key = name] ifNone: [name -> #()]) value.
		common := df select: [:f | of includes: f].
		s nextPutAll: name; nextPutAll: ' :='.
		common do: [:f | s space; nextPutAll: f].
		s lf.
		(Array with: defaultArch -> (df reject: [:f | of includes: f]) with: otherArch -> (of reject: [:f | df includes: f])) do: [:a |
			a value notEmpty ifTrue: [
				(self isBaseList: name) ifFalse: [^self error: name , ' has files for one CPU: only the lists for every OS may'].
				(archOnly at: name , '_' , (VMTranslator archSuffixFor: a key) ifAbsentPut: [OrderedCollection new]) addAll: a value]]].
	VMTranslator targetArchs do: [:spec |
		names do: [:name |
			(self isBaseList: name) ifTrue: [
				| key |
				key := name , '_' , (spec at: 2).
				s nextPutAll: key; nextPutAll: ' :='.
				((archOnly at: key ifAbsent: [#()]) asSortedCollection: [:a :b | a <= b]) do: [:f | s space; nextPutAll: f].
				s lf]]].
	^s contents
!
isBaseList: aName
	^#('VM_CORE_SOURCES' 'VM_HEADLESS_SOURCES' 'VM_PLATFORM_SOURCES') includes: aName
!
listsOf: aString
	"The NAME := files lines of a sources.mk: name -> files."
	| lists |
	lists := OrderedCollection new.
	(self linesOf: aString) do: [:line |
		| i |
		i := line indexOfSubCollection: ' :=' startingAt: 1.
		(i > 0 and: [line first ~= $#]) ifTrue: [
			lists add: (line copyFrom: 1 to: i - 1) -> ((line copyFrom: i + 3 to: line size) substrings asArray)]].
	^lists asArray
! !
