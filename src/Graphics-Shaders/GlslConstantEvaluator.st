Object subclass: #GlslConstantEvaluator
	instanceVariableNames: 'tokens at'
	classVariableNames: ''
	package: 'Graphics-Shaders'!

GlslConstantEvaluator comment: 'I evaluate the integer expression of a preprocessor #if: integer tokens and C''s operators (?: || && | ^ & == !!= < > <= >= << >> + - * / % and unary - + !! ~), with C''s precedence.'!

!GlslConstantEvaluator methodsFor: 'evaluating'!
evaluate: anArray at: aToken
	| v |
	tokens := anArray.
	at := 1.
	tokens isEmpty ifTrue: [^ShaderError line: aToken line column: aToken column detail: '#if needs a condition'].
	v := self conditional.
	at <= tokens size ifTrue: [self fail: 'unexpected ', (tokens at: at) text].
	^v
!
fail: aString
	| t |
	t := at <= tokens size ifTrue: [tokens at: at] ifFalse: [tokens last].
	^ShaderError line: t line column: t column detail: aString
!
peekIs: aString
	^at <= tokens size and: [(tokens at: at) is: aString]
!
conditional
	| c a b |
	c := self binary: 1.
	(self peekIs: '?') ifFalse: [^c].
	at := at + 1.
	a := self conditional.
	(self peekIs: ':') ifFalse: [self fail: 'expected :'].
	at := at + 1.
	b := self conditional.
	^c ~= 0 ifTrue: [a] ifFalse: [b]
!
binary: level
	| levels ops v |
	levels := #(#('||') #('&&') #('|') #('^') #('&') #('==' '!!=') #('<' '>' '<=' '>=') #('<<' '>>') #('+' '-') #('*' '/' '%')).
	level > levels size ifTrue: [^self unary].
	ops := levels at: level.
	v := self binary: level + 1.
	[at <= tokens size and: [ops includes: (tokens at: at) text]] whileTrue: [| op r |
		op := (tokens at: at) text.
		at := at + 1.
		r := self binary: level + 1.
		v := self apply: op to: v and: r].
	^v
!
apply: op to: a and: b
	op = '||' ifTrue: [^(a ~= 0 or: [b ~= 0]) ifTrue: [1] ifFalse: [0]].
	op = '&&' ifTrue: [^(a ~= 0 and: [b ~= 0]) ifTrue: [1] ifFalse: [0]].
	op = '|' ifTrue: [^a bitOr: b].
	op = '^' ifTrue: [^a bitXor: b].
	op = '&' ifTrue: [^a bitAnd: b].
	op = '==' ifTrue: [^a = b ifTrue: [1] ifFalse: [0]].
	op = '!!=' ifTrue: [^a = b ifTrue: [0] ifFalse: [1]].
	op = '<' ifTrue: [^a < b ifTrue: [1] ifFalse: [0]].
	op = '>' ifTrue: [^a > b ifTrue: [1] ifFalse: [0]].
	op = '<=' ifTrue: [^a <= b ifTrue: [1] ifFalse: [0]].
	op = '>=' ifTrue: [^a >= b ifTrue: [1] ifFalse: [0]].
	op = '<<' ifTrue: [^a bitShift: b].
	op = '>>' ifTrue: [^a bitShift: b negated].
	op = '+' ifTrue: [^a + b].
	op = '-' ifTrue: [^a - b].
	op = '*' ifTrue: [^a * b].
	b = 0 ifTrue: [self fail: 'division by zero'].
	op = '/' ifTrue: [^a quo: b].
	^a rem: b
!
unary
	| t v |
	at > tokens size ifTrue: [self fail: 'expected a value'].
	t := tokens at: at.
	at := at + 1.
	(t is: '-') ifTrue: [^self unary negated].
	(t is: '+') ifTrue: [^self unary].
	(t is: '!!') ifTrue: [^self unary = 0 ifTrue: [1] ifFalse: [0]].
	(t is: '~') ifTrue: [^self unary bitInvert].
	(t is: '(') ifTrue: [
		v := self conditional.
		(self peekIs: ')') ifFalse: [self fail: 'expected )'].
		at := at + 1.
		^v].
	(t kind == #int or: [t kind == #uint]) ifTrue: [^t value].
	at := at - 1.
	^self fail: 'expected a value, not ', t text
! !
