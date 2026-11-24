Object subclass: #GlslLexer
	instanceVariableNames: 'source at line column tokens macros conditions lineStart pushedBack'
	classVariableNames: ''
	package: 'Graphics-Shaders'!

GlslLexer comment: 'I turn GLSL source into GlslTokens, running its preprocessor on the way: #define (object-like and function-like macros, expanded where used), #undef, #if/#ifdef/#ifndef/#elif/#else/#endif (with defined and integer arithmetic), #line N (the next line is line N, as FragmentShader''s prelude ends), #error; #version, #extension and #pragma are accepted and ignored. Predefined: __VERSION__ 450, SAMALTAK_FRAGMENT and SAMALTAK_CUDA. Errors are ShaderErrors at the offending line and column.'!

!GlslLexer methodsFor: 'tokenizing'!
tokenize: aString
	"The tokens of aString, ending with an #eof one."
	self setSource: aString line: 1 column: 1.
	conditions := OrderedCollection new.
	macros := Dictionary new.
	#(#('__VERSION__' '450') #('SAMALTAK_FRAGMENT' '1') #('SAMALTAK_CUDA' '1')) do: [:d |
		macros at: d first put: (Array with: nil with: (Array with: (GlslToken kind: #int text: d last line: 0 column: 0 value: d last asInteger)))].
	[pushedBack isNil ifFalse: [| t | t := pushedBack. pushedBack := nil. self emit: t].
	self skipBlanks.
	at <= source size] whileTrue: [
		(lineStart and: [(source at: at) = $#])
			ifTrue: [self directive]
			ifFalse: [
				lineStart := false.
				self isActive
					ifTrue: [self emit: self rawToken]
					ifFalse: [self skipLine]]].
	conditions isEmpty ifFalse: [self errorText: '#if without #endif'].
	tokens add: (GlslToken kind: #eof text: '' line: line column: column value: nil).
	^tokens asArray
!
setSource: aString line: l column: c
	source := aString.
	at := 1. line := l. column := c.
	tokens := OrderedCollection new.
	lineStart := true
!
tokensOfLine: aString line: l column: c
	"The tokens of one line of a directive."
	self setSource: aString line: l column: c.
	lineStart := false.
	[self skipBlanks. at <= source size] whileTrue: [tokens add: self rawToken].
	^tokens asArray
!
emit: aToken
	"Add aToken, or what it expands to if it names a macro."
	(aToken kind == #ident and: [macros includesKey: aToken text])
		ifFalse: [^tokens add: aToken].
	tokens addAll: (self expandMacro: aToken from: [self nextTokenForMacro] back: [:t | pushedBack := t] hiding: Set new)
!
expandMacro: aToken from: nextBlock back: backBlock hiding: aSet
	"The tokens the macro aToken names expands to; nextBlock answers the tokens after it (nil at the end), for a function-like macro's arguments, and backBlock takes back the one after it if it is not (."
	| m params body args next hidden out |
	m := macros at: aToken text.
	params := m first.
	body := m last.
	hidden := aSet copy add: aToken text; yourself.
	params isNil ifTrue: [^self expand: (body collect: [:t | t at: aToken]) hiding: hidden].
	next := nextBlock value.
	(next notNil and: [next is: '(']) ifFalse: [
		next isNil ifFalse: [backBlock value: next].
		^Array with: aToken].
	args := self macroArguments: nextBlock for: aToken.
	(params isEmpty and: [args size = 1 and: [args first isEmpty]]) ifTrue: [args := #()].
	args size = params size
		ifFalse: [self errorAt: aToken text: 'the macro ', aToken text, ' takes ', params size printString, ' arguments, not ', args size printString].
	args := args collect: [:a | self expand: a hiding: aSet].
	out := OrderedCollection new.
	body do: [:t | | i |
		i := t kind == #ident ifTrue: [params indexOf: t text] ifFalse: [0].
		i > 0
			ifTrue: [(args at: i) do: [:a | out add: (a at: aToken)]]
			ifFalse: [out add: (t at: aToken)]].
	^self expand: out asArray hiding: hidden
!
macroArguments: nextBlock for: aToken
	"After a function-like macro's (: its arguments, each an Array of tokens, up to the matching )."
	| args current depth t |
	args := OrderedCollection new.
	current := OrderedCollection new.
	depth := 0.
	[t := nextBlock value.
	t isNil ifTrue: [self errorAt: aToken text: 'unterminated arguments of the macro ', aToken text].
	depth = 0 and: [t is: ')']] whileFalse: [
		(depth = 0 and: [t is: ','])
			ifTrue: [args add: current asArray. current := OrderedCollection new]
			ifFalse: [
				(t is: '(') ifTrue: [depth := depth + 1].
				(t is: ')') ifTrue: [depth := depth - 1].
				current add: t]].
	args add: current asArray.
	^args
!
expand: anArray hiding: aSet
	"anArray of tokens with the macros in it expanded (except those in aSet)."
	| out stream |
	out := OrderedCollection new.
	stream := ReadStream on: anArray.
	[stream atEnd] whileFalse: [| t |
		t := stream next.
		(t kind == #ident and: [(macros includesKey: t text) and: [(aSet includes: t text) not]])
			ifTrue: [out addAll: (self expandMacro: t from: [stream atEnd ifTrue: [nil] ifFalse: [stream next]] back: [:x | stream skip: -1] hiding: aSet)]
			ifFalse: [out add: t]].
	^out asArray
!
nextTokenForMacro
	"The next token of the source, for a macro's arguments; nil at the end."
	| t |
	pushedBack isNil ifFalse: [t := pushedBack. pushedBack := nil. ^t].
	self skipBlanks.
	at > source size ifTrue: [^nil].
	(lineStart and: [(source at: at) = $#]) ifTrue: [self errorText: 'a directive among a macro''s arguments'].
	lineStart := false.
	^self rawToken
! !

!GlslLexer methodsFor: 'scanning'!
peek
	^at <= source size ifTrue: [source at: at] ifFalse: [nil]
!
peek: n
	^at + n <= source size ifTrue: [source at: at + n] ifFalse: [nil]
!
advance
	| c |
	c := source at: at.
	at := at + 1.
	c = Character lf ifTrue: [line := line + 1. column := 1. lineStart := true] ifFalse: [column := column + 1].
	^c
!
isBlank: c
	^c = $  or: [c = Character tab or: [c = Character cr or: [c = Character lf or: [c = Character newPage]]]]
!
skipBlanks
	"Spaces, newlines, line continuations and comments."
	| c |
	[(c := self peek) notNil] whileTrue: [
		(self isBlank: c)
			ifTrue: [self advance]
			ifFalse: [
				(c = $\ and: [(self peek: 1) = Character lf]) ifTrue: [self advance; advance] ifFalse: [
				(c = $/ and: [(self peek: 1) = $/]) ifTrue: [self skipLine] ifFalse: [
				(c = $/ and: [(self peek: 1) = $*]) ifTrue: [self skipBlockComment] ifFalse: [^self]]]]]
!
skipBlockComment
	| l c start |
	l := line. c := column. start := lineStart.
	self advance; advance.
	[self peek notNil and: [(self peek = $* and: [(self peek: 1) = $/]) not]] whileTrue: [self advance].
	self peek isNil ifTrue: [^ShaderError line: l column: c detail: 'unterminated comment'].
	self advance; advance.
	l = line ifTrue: [lineStart := start]
!
skipLine
	[self peek notNil and: [self peek ~= Character lf]] whileTrue: [self advance]
!
rawToken
	"The token at the current position."
	| c l col start |
	c := self peek.
	l := line. col := column. start := at.
	(c isLetter or: [c = $_]) ifTrue: [
		[self peek notNil and: [self peek isLetter or: [self peek isDigit or: [self peek = $_]]]] whileTrue: [self advance].
		^GlslToken kind: #ident text: (source copyFrom: start to: at - 1) line: l column: col value: nil].
	(c isDigit or: [c = $. and: [(self peek: 1) notNil and: [(self peek: 1) isDigit]]]) ifTrue: [^self number].
	#('<<=' '>>=' '++' '--' '<<' '>>' '<=' '>=' '==' '!!=' '&&' '||' '^^' '+=' '-=' '*=' '/=' '%=' '&=' '|=' '^=') do: [:p |
		(source size - at + 1 >= p size and: [(source copyFrom: at to: at + p size - 1) = p]) ifTrue: [
			p size timesRepeat: [self advance].
			^GlslToken kind: #punct text: p line: l column: col value: nil]].
	('()[]{}.,;:?+-*/%<>=!!~&|^' includes: c) ifTrue: [
		self advance.
		^GlslToken kind: #punct text: (String with: c) line: l column: col value: nil].
	^ShaderError line: l column: col detail: 'unexpected character ', c printString
!
number
	"An integer (decimal, octal, hex; u for unsigned) or a float (an f or lf after it is dropped)."
	| l col start isFloat text kind v |
	l := line. col := column. start := at.
	isFloat := false.
	(self peek = $0 and: [(self peek: 1) notNil and: [(self peek: 1) asLowercase = $x]])
		ifTrue: [
			self advance; advance.
			[self peek notNil and: [self peek isDigit or: ['abcdefABCDEF' includes: self peek]]] whileTrue: [self advance]]
		ifFalse: [
			[self peek notNil and: [self peek isDigit]] whileTrue: [self advance].
			self peek = $. ifTrue: [isFloat := true. self advance. [self peek notNil and: [self peek isDigit]] whileTrue: [self advance]].
			(self peek notNil and: [self peek asLowercase = $e]) ifTrue: [
				isFloat := true.
				self advance.
				(self peek notNil and: ['+-' includes: self peek]) ifTrue: [self advance].
				(self peek notNil and: [self peek isDigit]) ifFalse: [^ShaderError line: l column: col detail: 'bad exponent'].
				[self peek notNil and: [self peek isDigit]] whileTrue: [self advance]]].
	text := source copyFrom: start to: at - 1.
	(isFloat not and: [self peek notNil and: [self peek asLowercase = $f and: [(text beginsWith: '0x') not and: [(text beginsWith: '0X') not]]]]) ifTrue: [isFloat := true].
	isFloat
		ifTrue: [
			(self peek notNil and: [self peek asLowercase = $f])
				ifTrue: [self advance]
				ifFalse: [(self peek notNil and: [self peek asLowercase = $l and: [(self peek: 1) notNil and: [(self peek: 1) asLowercase = $f]]]) ifTrue: [self advance; advance]].
			kind := #float]
		ifFalse: [
			kind := #int.
			(self peek notNil and: [self peek asLowercase = $u]) ifTrue: [self advance. kind := #uint].
			v := (text size > 1 and: [(text at: 2) asLowercase = $x])
				ifTrue: [text size < 3 ifTrue: [^ShaderError line: l column: col detail: 'bad hexadecimal number']. Integer readFrom: (text copyFrom: 3 to: text size) base: 16]
				ifFalse: [(text size > 1 and: [text first = $0])
					ifTrue: [(text allSatisfy: [:d | d between: $0 and: $7]) ifFalse: [^ShaderError line: l column: col detail: 'bad octal number']. Integer readFrom: (text copyFrom: 2 to: text size) base: 8]
					ifFalse: [Integer readFrom: text base: 10]].
			v > 16rFFFFFFFF ifTrue: [^ShaderError line: l column: col detail: 'integer literal too big'].
			(kind == #int and: [v > 16r7FFFFFFF]) ifTrue: [v := v - 16r100000000]].
	(self peek notNil and: [self peek isLetter or: [self peek = $_ or: [self peek isDigit]]]) ifTrue: [^ShaderError line: line column: column detail: 'bad number'].
	^GlslToken kind: kind text: text line: l column: col value: v
! !

!GlslLexer methodsFor: 'directives'!
isActive
	^conditions allSatisfy: [:c | c first]
!
directive
	"A line starting with #: read it (with its continuations, without comments) and act on it."
	| l col text name words rest n |
	l := line. col := column.
	self advance.
	text := WriteStream on: String new.
	[self peek notNil and: [self peek ~= Character lf]] whileTrue: [
		(self peek = $\ and: [(self peek: 1) = Character lf]) ifTrue: [self advance; advance. text space] ifFalse: [
		(self peek = $/ and: [(self peek: 1) = $/]) ifTrue: [self skipLine] ifFalse: [
		(self peek = $/ and: [(self peek: 1) = $*]) ifTrue: [self skipBlockComment. text space] ifFalse: [text nextPut: self advance]]]].
	lineStart := true.
	text := text contents.
	name := (text copyReplaceAll: (String with: Character tab) with: ' ') trimBoth.
	n := 0.
	[n < name size and: [(name at: n + 1) isLetter]] whileTrue: [n := n + 1].
	name := name copyFrom: 1 to: n.
	name isEmpty ifTrue: [^self].
	(self isActive or: [#('if' 'ifdef' 'ifndef' 'elif' 'else' 'endif') includes: name]) ifFalse: [^self].
	(self isActive not and: [#('if' 'ifdef' 'ifndef' 'elif') includes: name]) ifTrue: [^self conditional: name tokens: #() at: nil].
	words := GlslLexer new tokensOfLine: text line: l column: col + 1.
	"errors in a directive are at its #"
	words at: 1 put: (GlslToken kind: #ident text: name line: l column: col value: nil).
	rest := words allButFirst.
	(#('if' 'ifdef' 'ifndef' 'elif' 'else' 'endif') includes: name) ifTrue: [^self conditional: name tokens: rest at: words first].
	name = 'define' ifTrue: [^self define: rest at: words first].
	name = 'undef' ifTrue: [rest isEmpty ifFalse: [macros removeKey: rest first text ifAbsent: []]. ^self].
	name = 'line' ifTrue: [
		rest := self expand: rest hiding: Set new.
		(rest notEmpty and: [rest first kind == #int]) ifFalse: [self errorAt: words first text: '#line needs a line number'].
		line := rest first value - 1.
		^self].
	name = 'error' ifTrue: [self errorAt: words first text: '#error', (rest inject: '' into: [:s :t | s, ' ', t text])].
	(#('version' 'extension' 'pragma') includes: name) ifTrue: [^self].
	self errorAt: words first text: 'unknown directive #', name
!
define: rest at: aToken
	| nameToken params body i |
	(rest notEmpty and: [rest first kind == #ident]) ifFalse: [self errorAt: aToken text: '#define needs a name'].
	nameToken := rest first.
	(nameToken text beginsWith: 'GL_') ifTrue: [self errorAt: nameToken text: 'macro names starting with GL_ are reserved'].
	i := 2.
	params := nil.
	(rest size >= 2 and: [((rest at: 2) is: '(') and: [(rest at: 2) column = (nameToken column + nameToken text size) and: [(rest at: 2) line = nameToken line]]])
		ifTrue: [
			params := OrderedCollection new.
			i := 3.
			[i <= rest size and: [((rest at: i) is: ')') not]] whileTrue: [
				((rest at: i) is: ',') ifFalse: [params add: (rest at: i) text].
				i := i + 1].
			i > rest size ifTrue: [self errorAt: nameToken text: 'unterminated macro parameters'].
			i := i + 1.
			params := params asArray].
	body := rest copyFrom: i to: rest size.
	macros at: nameToken text put: (Array with: params with: body)
!
conditional: name tokens: rest at: aToken
	"aToken nil: a conditional inside an inactive one, whose condition is not looked at."
	| value |
	name = 'endif' ifTrue: [
		conditions isEmpty ifTrue: [self errorAt: aToken text: '#endif without #if'].
		^conditions removeLast].
	aToken isNil ifTrue: [^conditions add: (Array with: false with: true)].
	(name = 'else' or: [name = 'elif']) ifTrue: [
		conditions isEmpty ifTrue: [self errorAt: aToken text: '#', name, ' without #if'].
		conditions last last ifTrue: [^conditions last at: 1 put: false].
		value := name = 'else' or: [self evaluate: rest at: aToken].
		conditions last at: 1 put: value; at: 2 put: value.
		^self].
	value := name = 'if'
		ifTrue: [self evaluate: rest at: aToken]
		ifFalse: [
			rest isEmpty ifTrue: [self errorAt: aToken text: '#', name, ' needs a name'].
			(macros includesKey: rest first text) = (name = 'ifdef')].
	conditions add: (Array with: value with: value)
!
evaluate: anArray at: aToken
	"#if's condition: defined X, integers, macros, and C's operators on them; undefined names are 0."
	| ts out stream |
	out := OrderedCollection new.
	stream := ReadStream on: anArray.
	[stream atEnd] whileFalse: [| t |
		t := stream next.
		(t kind == #ident and: [t text = 'defined'])
			ifTrue: [| n |
				n := stream atEnd ifFalse: [stream next].
				(n notNil and: [n is: '(']) ifTrue: [n := stream atEnd ifFalse: [stream next]. stream atEnd ifFalse: [stream next]].
				n isNil ifTrue: [self errorAt: t text: 'defined needs a name'].
				out add: (GlslToken kind: #int text: '' line: t line column: t column value: ((macros includesKey: n text) ifTrue: [1] ifFalse: [0]))]
			ifFalse: [out add: t]].
	ts := (self expand: out asArray hiding: Set new) collect: [:t |
		t kind == #ident ifTrue: [GlslToken kind: #int text: '0' line: t line column: t column value: 0] ifFalse: [t]].
	^(GlslConstantEvaluator new evaluate: ts at: aToken) ~= 0
! !

!GlslLexer methodsFor: 'errors'!
errorAt: aToken text: aString
	^ShaderError line: aToken line column: aToken column detail: aString
!
errorText: aString
	^ShaderError line: line column: column detail: aString
! !

!GlslLexer class methodsFor: 'tokenizing'!
tokenize: aString
	^self new tokenize: aString
! !
