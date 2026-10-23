Object subclass: #Exception
	instanceVariableNames: 'messageText tag signaler signalContext handlerContext outerContext'
	classVariableNames: 'SignalHook'
	package: 'Kernel-Exceptions'!

Exception comment: 'I am the root of the exception hierarchy (ANSI semantics). signal searches the sender chain of the signaling context for an active handler (a BlockClosure>>on:do: context, primitive 199, whose exception class handles me) and runs its handler block; if the block falls off its end, on:do: returns its value. A handler may also return:, retry, resume: (resumable exceptions only), pass or outer. Without a handler my defaultAction runs; its value is the value of signal.'!

!Exception methodsFor: 'signaling'!
signal
	"Signal the receiver; answer the resumption value (if resumed or if the default action returns). A signal hook (debugging tools) may divert me before any handler is searched: then I answer what its diversion block answers."
	| diversion |
	signalContext := thisContext contextTag.
	signaler isNil ifTrue: [signaler := self receiver].
	SignalHook isNil ifFalse: [
		diversion := SignalHook value: self.
		diversion isNil ifFalse: [^diversion value]].
	^signalContext nextHandlerContext handleSignal: self
!
signal: aString
	messageText := aString.
	^self signal
!
signalIn: aContext
	"Signal as if from aContext."
	signalContext := aContext.
	^aContext nextHandlerContext handleSignal: self
! !

!Exception methodsFor: 'handling'!
return: returnValue
	"Leave the handler: on:do: answers returnValue."
	handlerContext isNil ifTrue: [^IllegalResumeAttempt new signal: 'return: outside of a handler'].
	handlerContext return: returnValue
!
return
	self return: nil
!
retry
	"Leave the handler and evaluate the protected block again."
	handlerContext isNil ifTrue: [^IllegalResumeAttempt new signal: 'retry outside of a handler'].
	handlerContext restart
!
retryUsing: alternativeBlock
	"Leave the handler and evaluate alternativeBlock instead of the protected block."
	handlerContext isNil ifTrue: [^IllegalResumeAttempt new signal: 'retryUsing: outside of a handler'].
	handlerContext restartWithNewReceiver: alternativeBlock
!
resume: resumptionValue
	"Continue after signal (or outer), which answers resumptionValue."
	self isResumable ifFalse: [^IllegalResumeAttempt new signal: 'This exception is not resumable'].
	self resumeUnchecked: resumptionValue
!
resume
	self resume: nil
!
resumeUnchecked: resumptionValue
	| ctx |
	outerContext isNil
		ifTrue: [signalContext return: resumptionValue]
		ifFalse: [
			ctx := outerContext.
			outerContext := ctx tempAt: 1.
			ctx return: resumptionValue]
!
pass
	"Hand the receiver to the next enclosing handler (or the default action)."
	^handlerContext nextHandlerContext handleSignal: self
!
outer
	"Like pass, but if the outer handler resumes, outer answers the resumption value here."
	| prevOuterContext |
	self isResumable ifTrue: [
		prevOuterContext := outerContext.
		outerContext := thisContext contextTag].
	^self pass
!
signalerContext
	"Answer the context that sent signal (skipping the exception's own methods)."
	^signalContext findContextSuchThat: [:ctx |
		ctx receiver ~~ self and: [ctx receiver ~~ self class]]
!
freeze
	"Copy my stack from the signal context up to my handler, so that signalerContext and its senders survive leaving the handler (e.g. to resignal me in another Process)."
	signalContext := signalContext copyStackUpTo: handlerContext.
	outerContext := nil
!
resignal
	"Signal me again from here, after freeze: handlers are searched from my sender, resumption answers here, and signalerContext still answers where I was first signaled."
	| prevOuterContext |
	prevOuterContext := outerContext.
	outerContext := thisContext contextTag.
	handlerContext := nil.
	^thisContext nextHandlerContext handleSignal: self
!
resignalAs: replacementException
	"Signal replacementException in place of the receiver, from the original signal context."
	^signalContext return: (replacementException signalIn: signalContext)
! !

!Exception methodsFor: 'accessing'!
messageText
	"Answer the message text, or the default description."
	^messageText ifNil: [self description]
!
messageText: aString
	messageText := aString
!
description
	"Answer a default textual description of the exception."
	^self class name asString
!
tag
	^tag ifNil: [self messageText]
!
tag: anObject
	tag := anObject
!
signaler
	^signaler
!
signaler: anObject
	signaler := anObject
!
receiver
	^self signalerContext ifNotNil: [:ctx | ctx receiver]
!
signalContext
	^signalContext
!
handlerContext
	^handlerContext
!
privHandlerContext: aContext
	handlerContext := aContext
! !

!Exception methodsFor: 'testing'!
isResumable
	^true
!
isHandled
	^handlerContext notNil
! !

!Exception methodsFor: 'exception description'!
defaultAction
	"No handler: treat the receiver like an unhandled error."
	^UnhandledError signalForException: self
! !

!Exception methodsFor: 'printing'!
printOn: aStream
	| text |
	aStream nextPutAll: self class name.
	text := self messageText.
	(text notNil and: [text asString ~= self class name asString])
		ifTrue: [aStream nextPutAll: ': '; nextPutAll: text asString]
! !

!Exception class methodsFor: 'signal hook'!
signalHook
	^SignalHook
!
signalHook: aBlockOrNil
	"[:anException | nil, or a block evaluated instead of the handler search (its value is the signal's)]: lets debugging tools (watchpoints) take a signal before the program's handlers see it. Must be quick; nil: none."
	SignalHook := aBlockOrNil
! !

!Exception class methodsFor: 'signaling'!
signal
	^self new signal
!
signal: aString
	^self new signal: aString
! !

!Exception class methodsFor: 'exception selectors'!
handles: anException
	"Answer whether my handlers catch anException."
	^anException isKindOf: self
!
, anExceptionClass
	"Answer an ExceptionSet handling both."
	^ExceptionSet new add: self; add: anExceptionClass; yourself
! !
