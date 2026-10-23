Breakpoint subclass: #MethodBreakpoint
	instanceVariableNames: 'methodClass selector originalMethod patchedMethod'
	classVariableNames: ''
	package: 'System-Debugging'!

MethodBreakpoint comment: 'I am a breakpoint on one method: while installed, methodClass>>selector is a copy of originalMethod whose bytecodes start with the breakpoint prologue (see Breakpoint class>>patch:id:). Removing me puts originalMethod back, unless the method was replaced meanwhile. A breakpoint on a method with a primitive stops only when the primitive fails.'!

!MethodBreakpoint methodsFor: 'accessing'!
methodClass
	^methodClass
!
selector
	^selector
!
originalMethod
	^originalMethod
!
patchedMethod
	^patchedMethod
!
isMethodBreakpoint
	^true
!
locationDescription
	^methodClass name, '>>', selector
! !

!MethodBreakpoint methodsFor: 'private'!
setClass: aClass selector: aSelector
	methodClass := aClass.
	selector := aSelector
!
install
	originalMethod := methodClass compiledMethodAt: selector.
	patchedMethod := Breakpoint patch: originalMethod id: id.
	methodClass addSelector: selector withMethod: patchedMethod
!
uninstall
	(methodClass compiledMethodAt: selector ifAbsent: [nil]) == patchedMethod
		ifTrue: [methodClass addSelector: selector withMethod: originalMethod]
! !
