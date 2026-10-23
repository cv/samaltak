Breakpoint subclass: #ObjectBreakpoint
	instanceVariableNames: 'object selector originalClass anonymousClass originals'
	classVariableNames: ''
	package: 'System-Debugging'!

ObjectBreakpoint comment: 'I stop when one object receives a message (selector, or any message when selector is nil). Installing me moves the object into an anonymous subclass of its class (changeClassTo:) whose method dictionary holds, for each watched selector, a copy of the inherited method with the breakpoint prologue (or, for a primitive method, a small wrapper that checks the breakpoint and then runs the original). Other instances are unaffected. Removing me moves the object back.'!

!ObjectBreakpoint methodsFor: 'accessing'!
object
	^object
!
selector
	"The selector I stop at, nil for any."
	^selector
!
originalClass
	^originalClass
!
anonymousClass
	^anonymousClass
!
isObjectBreakpoint
	^true
!
originalMethodFor: aSelector
	^originals at: aSelector ifAbsent: [originalClass lookupSelector: aSelector]
!
locationDescription
	| text |
	text := Breakpoint ignoreDuring: [[object printString] on: Error do: [:e | e return: 'an object']].
	text size > 30 ifTrue: [text := (text copyFrom: 1 to: 30), '...'].
	^text, ' receives ', (selector isNil ifTrue: ['any message'] ifFalse: ['#', selector])
! !

!ObjectBreakpoint methodsFor: 'private'!
setObject: anObject selector: aSelectorOrNil
	object := anObject.
	selector := aSelectorOrNil
!
install
	| selectors |
	originalClass := object class.
	anonymousClass := self newAnonymousSubclassOf: originalClass.
	originals := IdentityDictionary new.
	selectors := selector isNil
		ifTrue: [originalClass allSelectors asArray]
		ifFalse: [Array with: selector].
	selectors do: [:sel | self installSelector: sel].
	object changeClassTo: anonymousClass
!
uninstall
	object class == anonymousClass ifTrue: [
		Breakpoint ignoreDuring: [object changeClassTo: originalClass]]
!
newAnonymousSubclassOf: aClass
	"A nameless copy of aClass (an instance of its metaclass, so class-side behavior and the name stay) that inherits from it, has no methods of its own and is not registered as its subclass."
	| anon |
	anon := aClass class basicNew.
	1 to: aClass class instSize do: [:i | anon instVarAt: i put: (aClass instVarAt: i)].
	anon superclass: aClass.
	anon methodDict: MethodDictionary new.
	(anon class allInstVarNames includes: 'instanceVariables') ifTrue: [anon instVarNamed: 'instanceVariables' put: #()].
	(anon class allInstVarNames includes: 'subclasses') ifTrue: [anon instVarNamed: 'subclasses' put: nil].
	(anon class allInstVarNames includes: 'organization') ifTrue: [anon instVarNamed: 'organization' put: nil].
	^anon
!
installSelector: aSelector
	| method prim new |
	method := originalClass lookupSelector: aSelector.
	method isNil ifTrue: [^self].
	prim := method primitiveNumber.
	method hasRunnablePrimitive not
		ifTrue: [new := Breakpoint patch: method id: id]
		ifFalse: [
			(Simulator specialPrimitives includesKey: prim) ifTrue: [^self].
			new := self wrapperFor: method].
	originals at: aSelector put: method.
	anonymousClass addSelectorSilently: aSelector withMethod: new
!
wrapperFor: aCompiledMethod
	"A method that checks the breakpoint, then runs aCompiledMethod (primitive first) on the same receiver and arguments."
	| sel names pattern source keywords |
	sel := aCompiledMethod selector.
	names := (1 to: sel numArgs) collect: [:i | 'arg', i printString].
	sel numArgs = 0
		ifTrue: [pattern := sel asString]
		ifFalse: [
			sel first isLetter
				ifTrue: [
					keywords := sel keywords.
					pattern := String new: 40 streamContents: [:s |
						keywords doWithIndex: [:k :i | i > 1 ifTrue: [s space]. s nextPutAll: k; space; nextPutAll: (names at: i)]]]
				ifFalse: [pattern := sel asString, ' ', names first]].
	source := String new: 200 streamContents: [:s |
		s nextPutAll: pattern; nextPut: Character lf;
			tab; nextPutAll: 'Breakpoint hit: '; print: id; nextPutAll: ' in: thisContext.'; nextPut: Character lf;
			tab; nextPutAll: '^Breakpoint forward: '; print: id; nextPutAll: ' selector: '; print: sel;
			nextPutAll: ' receiver: self arguments: {'.
		names do: [:n | s nextPutAll: n] separatedBy: [s nextPutAll: '. '].
		s nextPutAll: '}'].
	^Compiler compileMethod: source in: aCompiledMethod methodClass classified: 'breakpoint'
! !
