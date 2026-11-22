Object subclass: #ImageSource
	instanceVariableNames: 'directory packages layers uses exports classes classOrder globalDecls methodChunks only'
	classVariableNames: ''
	package: 'VM-ImageBuilder'!

ImageSource comment: 'I read a source tree for ImageBuilder: packages.txt (load order, layers, uses and export lines) and every package''s .st files in chunk format: class definitions (BuilderClasses), comments, class-side instance variables, Smalltalk at: #Name put: literal, and method chunks after X methodsFor: ''category'' headers. Every chunk keeps its file and line for error messages.'!

Error subclass: #ImageBuildError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-ImageBuilder'!

!ImageSource class methodsFor: 'instance creation'!
on: aDirectory
	^self new setDirectory: aDirectory
!
definitionKinds
	"Class definition selectors (first keyword) and the kind of instances they make."
	^Dictionary new
		at: 'subclass:' put: #fixed;
		at: 'variableSubclass:' put: #pointers;
		at: 'variableByteSubclass:' put: #bytes;
		at: 'variableWordSubclass:' put: #words;
		at: 'variableDoubleWordSubclass:' put: #doublewords;
		at: 'weakSubclass:' put: #weak;
		at: 'immediateSubclass:' put: #immediate;
		yourself
! !

!ImageSource methodsFor: 'initialization'!
setDirectory: aDirectory
	directory := aDirectory.
	packages := OrderedCollection new.
	layers := Dictionary new.
	uses := Dictionary new.
	exports := Dictionary new.
	classes := Dictionary new.
	classOrder := OrderedCollection new.
	globalDecls := OrderedCollection new.
	methodChunks := OrderedCollection new
! !

!ImageSource methodsFor: 'accessing'!
directory
	^directory
!
only: aCollectionOrNil
	"Read only these packages (names), in packages.txt's order and on its layers; nil: all."
	only := aCollectionOrNil
!
packages
	"{name. layer} in load order."
	^packages
!
layerOf: aPackageName
	^layers at: aPackageName
!
usesOf: aPackageName
	^uses at: aPackageName ifAbsent: [#()]
!
exportLayerOf: aGlobalName from: aPackageName
	^exports at: aPackageName , ' ' , aGlobalName ifAbsent: [nil]
!
classes
	^classes
!
classOrder
	^classOrder
!
classNamed: aString
	^classes at: aString ifAbsent: [nil]
!
globalDecls
	"{name. literal value. file. line. package}"
	^globalDecls
!
methodChunks
	"{className. isMeta. category. source. file. line. package}"
	^methodChunks
! !

!ImageSource methodsFor: 'reading'!
read
	self readPackages.
	packages do: [:each | self readPackage: (each at: 1)]
!
error: aString file: aFile line: anInteger
	^ImageBuildError signal: aFile , ':' , anInteger printString , ': ' , aString
!
readPackages
	| path lineNumber |
	path := directory , '/packages.txt'.
	lineNumber := 0.
	(self readText: path) lines do: [:raw |
		| line parts |
		lineNumber := lineNumber + 1.
		line := raw trimBoth.
		(line isEmpty or: [line first = $#]) ifFalse: [
			parts := line substrings.
			(parts first = 'export' and: [parts size >= 4 and: [(parts at: 3) allSatisfy: [:c | c between: $0 and: $9]]])
				ifTrue: [(parts allButFirst: 3) do: [:g | exports at: (parts at: 2) , ' ' , g put: (parts at: 3) asNumber]]
				ifFalse: [
					(parts size >= 2 and: [((parts at: 2) allSatisfy: [:c | (c between: $0 and: $9) or: [c = $-]]) and: [
						parts size = 2 or: [(parts at: 3) = 'uses' and: [parts size > 3]]]])
						ifFalse: [self error: 'expected "Name layer [uses Package...]" or "export Package layer Global..."' file: path line: lineNumber].
					(only isNil or: [only includes: parts first]) ifTrue: [
						packages add: (Array with: parts first with: (parts at: 2) asNumber)].
					layers at: parts first put: (parts at: 2) asNumber.
					uses at: parts first put: (parts size > 3 ifTrue: [(parts allButFirst: 3) asArray] ifFalse: [#()])]]].
	(uses values inject: Set new into: [:all :each | all addAll: each; yourself]) , (exports keys collect: [:k | k substrings first]) do: [:p |
		(layers includesKey: p) ifFalse: [self error: 'unknown package ' , p file: path line: 0]]
!
readText: aPath
	"File readText: without a leading byte order mark (the seed's File readText: may keep it)."
	| text |
	text := File readText: aPath.
	^(text notEmpty and: [text first value = 16rFEFF]) ifTrue: [text allButFirst] ifFalse: [text]
!
readPackage: aName
	| dir files |
	dir := directory , '/' , aName.
	(File isDirectory: dir) ifFalse: [self error: 'package directory ' , aName , ' missing' file: directory , '/packages.txt' line: 0].
	files := ((Directory fileNames: dir) select: [:f | f endsWith: '.st']) asSortedCollection asArray.
	files := (files reject: [:f | f endsWith: '.extension.st']) , (files select: [:f | f endsWith: '.extension.st']).
	files do: [:f | self readFile: dir , '/' , f package: aName]
!
chunksOf: aString
	"Answer {text. line} for each chunk: an exclamation mark ends a chunk, a doubled one stands for itself."
	| chunks buf i n line start c |
	chunks := OrderedCollection new.
	buf := WriteStream on: String new.
	i := 1.
	n := aString size.
	line := 1.
	start := 1.
	[i <= n] whileTrue: [
		c := aString at: i.
		c value = 33
			ifTrue: [
				(i < n and: [(aString at: i + 1) value = 33])
					ifTrue: [buf nextPut: c. i := i + 2]
					ifFalse: [
						chunks add: (Array with: buf contents with: start).
						buf := WriteStream on: String new.
						i := i + 1.
						start := line]]
			ifFalse: [
				c value = 10 ifTrue: [line := line + 1].
				buf nextPut: c.
				i := i + 1]].
	buf contents trimBoth isEmpty ifFalse: [chunks add: (Array with: buf contents with: start)].
	^chunks
!
readFile: aPath package: aPackageName
	| mode |
	mode := nil.
	(self chunksOf: (self readText: aPath)) do: [:chunk |
		| raw stripped line body |
		raw := chunk at: 1.
		stripped := raw trimLeft.
		line := (chunk at: 2) + ((raw first: raw size - stripped size) occurrencesOf: Character lf).
		body := stripped trimRight.
		((body endsWith: '$') and: [stripped size > body size]) ifTrue: [body := stripped first: body size + 1].
		mode notNil
			ifTrue: [
				body isEmpty
					ifTrue: [mode := nil]
					ifFalse: [methodChunks add: {mode at: 1. mode at: 2. mode at: 3. body. aPath. line. aPackageName}]]
			ifFalse: [
				body isEmpty ifFalse: [
					mode := self methodsForHeader: body.
					mode isNil ifTrue: [self topLevel: body file: aPath line: line package: aPackageName]]]]
!
methodsForHeader: aString
	"{className. isMeta. category} for X [class] methodsFor: 'cat' [stamp: '...'], else nil."
	| node message receiver |
	(aString includesSubstring: 'methodsFor:') ifFalse: [^nil].
	node := [Parser new parseExpression: aString] on: Error do: [:e | ^nil].
	node body statements size = 1 ifFalse: [^nil].
	message := node body statements first.
	(message isMessage and: [message selector == #methodsFor: or: [message selector == #methodsFor:stamp:]]) ifFalse: [^nil].
	receiver := message receiver.
	receiver isVariable ifTrue: [^Array with: receiver name with: false with: message arguments first value].
	(receiver isMessage and: [receiver selector == #class and: [receiver receiver isVariable]]) ifTrue: [
		^Array with: receiver receiver name with: true with: message arguments first value].
	^nil
!
topLevel: aString file: aPath line: aLine package: aPackageName
	| node e parts kind |
	node := [Parser new parseExpression: aString] on: SyntaxError do: [:ex | ^self error: ex messageText file: aPath line: aLine].
	e := node body statements isEmpty ifTrue: [nil] ifFalse: [node body statements first].
	(e notNil and: [e isMessage]) ifFalse: [^self error: 'definition expected' file: aPath line: aLine].
	parts := e selector keywords.
	kind := parts isEmpty ifTrue: [nil] ifFalse: [self class definitionKinds at: parts first ifAbsent: [nil]].
	(kind notNil and: [e receiver isVariable or: [e receiver isLiteral]]) ifTrue: [^self defineClass: e kind: kind file: aPath line: aLine package: aPackageName].
	(e selector == #comment: and: [e receiver isVariable]) ifTrue: [
		(e arguments first isLiteral and: [e arguments first value isString]) ifFalse: [^self error: 'comment: expects a string' file: aPath line: aLine].
		^(self definedClass: e receiver name file: aPath line: aLine) comment: e arguments first value].
	(e selector == #instanceVariableNames: and: [e receiver isMessage and: [e receiver selector == #class and: [e receiver receiver isVariable]]]) ifTrue: [
		^(self definedClass: e receiver receiver name file: aPath line: aLine) classInstanceVariables: e arguments first value substrings].
	(e selector == #at:put: and: [e receiver isVariable and: [e receiver name = 'Smalltalk' and: [e arguments first isLiteral]]]) ifTrue: [
		e arguments last isLiteral ifFalse: [^self error: 'Smalltalk at:put: expects a literal value' file: aPath line: aLine].
		^globalDecls add: {e arguments first value asString. e arguments last value. aPath. aLine. aPackageName}].
	self error: 'unsupported top-level chunk' file: aPath line: aLine
!
definedClass: aString file: aPath line: aLine
	^classes at: aString ifAbsent: [self error: 'unknown class ' , aString file: aPath line: aLine]
!
defineClass: aMessageNode kind: aSymbol file: aPath line: aLine package: aPackageName
	| keywords args superName lit name cls |
	keywords := aMessageNode selector keywords.
	args := Dictionary new.
	keywords with: aMessageNode arguments do: [:k :a | args at: k put: a].
	superName := aMessageNode receiver isLiteral
		ifTrue: [
			aMessageNode receiver value isNil ifFalse: [^self error: 'bad superclass' file: aPath line: aLine].
			nil]
		ifFalse: [aMessageNode receiver name].
	lit := [:k :default |
		| a |
		a := args at: k ifAbsent: [nil].
		a isNil
			ifTrue: [default]
			ifFalse: [
				(a isLiteral and: [a value isString]) ifFalse: [^self error: k , ' expects a literal' file: aPath line: aLine].
				a value asString]].
	name := lit value: keywords first value: ''.
	(classes includesKey: name) ifTrue: [^self error: 'class ' , name , ' defined twice' file: aPath line: aLine].
	cls := BuilderClass new
		setName: name
		superclassName: superName
		kind: aSymbol
		instanceVariables: (lit value: 'instanceVariableNames:' value: '') substrings
		classVariables: (lit value: 'classVariableNames:' value: '') substrings
		package: (lit value: 'package:' value: (lit value: 'category:' value: aPackageName))
		sourcePackage: aPackageName
		file: aPath
		line: aLine.
	classes at: name put: cls.
	classOrder add: cls
! !
