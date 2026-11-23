Object subclass: #ActionContext instanceVariableNames: 'environment text value resolved origin' classVariableNames: 'Copied Editors' package: 'Tools'!

ActionContext comment: 'I am a contextual value, evaluated only when an action needs my object.'!

!ActionContext methodsFor: 'actions'!
agent
 ^AgentWindow openFor: origin context: self
!
browse
 | object |
 object := self value.
 ^Tools browseClass: (object isBehavior ifTrue: [object] ifFalse: [object class])
!
inspect
 ^Tools inspect: self value
! !

!ActionContext methodsFor: 'accessing'!
agentContext
 self value.
 ^environment receiver: value; yourself
!
value
 resolved ifFalse: [value := environment evaluate: text bindings: Dictionary new. resolved := true].
 ^value
!
window
 ^origin ifNotNil: [:tool | tool window]
! !

!ActionContext methodsFor: 'initialization'!
environment: context text: string
 environment := context. text := string. resolved := false
!
object: object
 value := object. resolved := true. environment := AgentContext new
!
origin: aTool
 origin := aTool
!
useEnvironment: anEnvironment
 environment := anEnvironment.
 value := environment frame ifNil: [environment receiver] ifNotNil: [:frame | frame receiver].
 resolved := true
! !

!ActionContext class methodsFor: 'accessing'!
copied
 ^Copied
!
copied: context
 Copied := context
! !

!ActionContext class methodsFor: 'creation'!
forEditor: editor
 | env evaluator |
 env := editor window ifNil: [AgentContext new] ifNotNil: [:w | (w content respondsTo: #agentContext) ifTrue: [w content agentContext] ifFalse: [AgentContext new]].
 evaluator := self evaluatorOf: editor.
 evaluator ifNotNil: [env receiver: evaluator receiver; bindings: evaluator bindings].
 ^(self new environment: env text: editor selectionOrLine) origin: (editor window ifNotNil: [:w | w content]); yourself
!
on: object
 ^self new object: object
!
for: aTool
 ^(self new useEnvironment: aTool agentContext) origin: aTool; yourself
! !

!ActionContext class methodsFor: 'registration'!
register: editor evaluator: evaluator
 "Editors is weak: a closed workspace's evaluator, its editor and window (and their World) are garbage."
 | i |
 (Editors isNil or: [(Editors isKindOf: WeakArray) not]) ifTrue: [Editors := WeakArray new: 16].
 i := Editors indexOf: nil.
 i = 0 ifTrue: [
  Editors := (WeakArray new: Editors size * 2) replaceFrom: 1 to: Editors size with: Editors startingAt: 1; yourself.
  i := Editors indexOf: nil].
 Editors at: i put: evaluator
!
evaluatorOf: editor
 Editors isNil ifTrue: [^nil].
 Editors do: [:each | (each notNil and: [each editor == editor]) ifTrue: [^each]].
 ^nil
! !

!ActionContext methodsFor: 'testing'!
isObject
 ^resolved == true
! !
