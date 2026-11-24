!GlslShader methodsFor: 'statements'!
blockBody: aToken
	"The statements up to the closing brace (the { is read), in the current scope."
	| n stmts |
	n := GlslNode kind: #block at: aToken.
	stmts := OrderedCollection new.
	[self accept: '}'] whileFalse: [
		self peek kind == #eof ifTrue: [self error: 'expected } before the end' at: self peek].
		stmts add: self statement].
	n children: stmts asArray.
	^n
!
blockStatement
	| t n |
	t := self expect: '{'.
	scopes addLast: Dictionary new.
	n := self blockBody: t.
	scopes removeLast.
	^n
!
scoped: aBlock
	"aBlock's statement in a scope of its own."
	| r |
	scopes addLast: Dictionary new.
	r := aBlock value.
	scopes removeLast.
	^r
!
statement
	| t n |
	t := self peek.
	(t is: '{') ifTrue: [^self blockStatement].
	(t is: ';') ifTrue: [self next. ^GlslNode kind: #empty at: t].
	t kind == #ident ifTrue: [
		t text = 'if' ifTrue: [^self ifStatement].
		t text = 'for' ifTrue: [^self forStatement].
		t text = 'while' ifTrue: [^self whileStatement].
		t text = 'do' ifTrue: [^self doStatement].
		t text = 'switch' ifTrue: [^self switchStatement].
		(t text = 'case' or: [t text = 'default']) ifTrue: [^self caseLabel].
		t text = 'return' ifTrue: [^self returnStatement].
		(t text = 'break' or: [t text = 'continue']) ifTrue: [
			self next.
			(t text = 'break' and: [loops + switches = 0]) ifTrue: [self error: 'break outside a loop or switch' at: t].
			(t text = 'continue' and: [loops = 0]) ifTrue: [self error: 'continue outside a loop' at: t].
			self expect: ';'.
			^GlslNode kind: t text asSymbol at: t].
		t text = 'discard' ifTrue: [
			self next. self expect: ';'.
			usesDiscard := true.
			^GlslNode kind: #discard at: t].
		self isDeclarationStart ifTrue: [^self declaration]].
	n := GlslNode kind: #expr at: t.
	n children: (Array with: self expression).
	self expect: ';'.
	^n
!
isDeclarationStart
	| t i depth |
	t := self peek.
	(#('const' 'highp' 'mediump' 'lowp' 'precise' 'struct') includes: t text) ifTrue: [^true].
	(self isTypeName: t) ifFalse: [^false].
	(self peek: 1) kind == #ident ifTrue: [^true].
	((self peek: 1) is: '[') ifFalse: [^false].
	"T[n] name or T[n](...): look past the brackets."
	i := 1. depth := 0.
	[| x |
	x := self peek: i.
	x kind == #eof ifTrue: [^false].
	(x is: '[') ifTrue: [depth := depth + 1].
	(x is: ']') ifTrue: [depth := depth - 1].
	i := i + 1.
	depth > 0 or: [(self peek: i) is: '[']] whileTrue.
	^(self peek: i) kind == #ident
!
declaration
	| t quals type n vars |
	t := self peek.
	quals := self qualifiers.
	(quals includes: #uniform) | (quals includes: #in) | (quals includes: #out) ifTrue: [self error: 'a local variable has no storage qualifier but const' at: t].
	type := self typeSpecifier.
	type isNil ifTrue: [self error: 'expected a type, not ', self describePeek at: self peek].
	type isVoid ifTrue: [self error: 'a variable cannot be void' at: t].
	vars := OrderedCollection new.
	[| nameToken v vt d |
	nameToken := self expectIdentifier.
	vt := self arraySuffix: type.
	v := GlslVariable name: nameToken text type: vt storage: #local at: nameToken.
	(quals includes: #const) ifTrue: [v beConst].
	d := GlslNode kind: #var at: nameToken.
	d symbol: v.
	(self accept: '=')
		ifTrue: [d children: (Array with: (self initializer: v))]
		ifFalse: [
			v isConst ifTrue: [self error: 'a constant needs a value' at: nameToken].
			(v type isArray and: [v type length isNil]) ifTrue: [self error: 'an array needs a size' at: nameToken].
			d children: (Array with: nil)].
	self declare: v.
	vars add: d.
	self accept: ','] whileTrue.
	self expect: ';'.
	n := GlslNode kind: #decl at: t.
	n children: vars asArray.
	^n
!
condition
	| e |
	e := self expression.
	e type isBool ifFalse: [self error: 'a condition is a bool, not ', e type name at: e].
	^e
!
ifStatement
	| t c a b n |
	t := self next.
	self expect: '('.
	c := self condition.
	self expect: ')'.
	a := self scoped: [self statement].
	b := (self accept: 'else') ifTrue: [self scoped: [self statement]] ifFalse: [nil].
	n := GlslNode kind: #if at: t.
	n children: (Array with: c with: a with: b).
	^n
!
forStatement
	| t init c inc body n |
	t := self next.
	self expect: '('.
	scopes addLast: Dictionary new.
	init := (self peekIs: ';')
		ifTrue: [self next. nil]
		ifFalse: [self isDeclarationStart ifTrue: [self declaration] ifFalse: [| e | e := GlslNode kind: #expr at: self peek. e children: (Array with: self expression). self expect: ';'. e]].
	c := (self peekIs: ';') ifTrue: [nil] ifFalse: [self condition].
	self expect: ';'.
	inc := (self peekIs: ')') ifTrue: [nil] ifFalse: [self expression].
	self expect: ')'.
	loops := loops + 1.
	body := self scoped: [self statement].
	loops := loops - 1.
	scopes removeLast.
	n := GlslNode kind: #for at: t.
	n children: (Array with: init with: c with: inc with: body).
	^n
!
whileStatement
	| t c body n |
	t := self next.
	self expect: '('.
	c := self condition.
	self expect: ')'.
	loops := loops + 1.
	body := self scoped: [self statement].
	loops := loops - 1.
	n := GlslNode kind: #while at: t.
	n children: (Array with: c with: body).
	^n
!
doStatement
	| t c body n |
	t := self next.
	loops := loops + 1.
	body := self scoped: [self statement].
	loops := loops - 1.
	(self peekIs: 'while') ifFalse: [self error: 'expected while after do''s statement' at: self peek].
	self next.
	self expect: '('.
	c := self condition.
	self expect: ')'.
	self expect: ';'.
	n := GlslNode kind: #do at: t.
	n children: (Array with: body with: c).
	^n
!
switchStatement
	| t e body n |
	t := self next.
	self expect: '('.
	e := self expression.
	(e type = GlslType int or: [e type = GlslType uint]) ifFalse: [self error: 'switch takes an int or a uint, not ', e type name at: e].
	self expect: ')'.
	switches := switches + 1.
	(self peekIs: '{') ifFalse: [self error: 'expected { after switch (...)' at: self peek].
	body := self blockStatement.
	switches := switches - 1.
	n := GlslNode kind: #switch at: t.
	n children: (Array with: e with: body).
	^n
!
caseLabel
	| t n v |
	t := self next.
	switches = 0 ifTrue: [self error: t text, ' outside a switch' at: t].
	v := t text = 'case' ifTrue: [self constantValueOf: self conditional] ifFalse: [nil].
	self expect: ':'.
	n := GlslNode kind: #case at: t.
	n value: v.
	^n
!
returnStatement
	| t e n |
	t := self next.
	n := GlslNode kind: #return at: t.
	(self accept: ';') ifTrue: [
		current returnType isVoid ifFalse: [self error: current name, ' returns a ', current returnType name at: t].
		n children: (Array with: nil).
		^n].
	e := self expression.
	current returnType isVoid ifTrue: [self error: current name, ' returns nothing' at: e].
	n children: (Array with: (self convert: e to: current returnType)).
	self expect: ';'.
	^n
! !
