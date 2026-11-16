Object subclass: #ActionContext instanceVariableNames: 'environment text value resolved' classVariableNames: 'Copied Editors' package: 'Tools'!

ActionContext comment: 'I am a contextual value, evaluated only when an action needs my object.'!

!ActionContext methodsFor: 'actions'!
agent
 ^AgentWindow openFor: self
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
 ^nil
! !

!ActionContext methodsFor: 'initialization'!
environment: context text: string
 environment := context. text := string. resolved := false
!
object: object
 value := object. resolved := true. environment := AgentContext new
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
 Editors ifNil: [Editors := IdentityDictionary new].
 evaluator := Editors at: editor ifAbsent: [nil].
 evaluator ifNotNil: [env receiver: evaluator receiver; bindings: evaluator bindings].
 ^self new environment: env text: editor selectionOrLine
!
on: object
 ^self new object: object
!
in: anEnvironment
 ^self new useEnvironment: anEnvironment
! !

!ActionContext class methodsFor: 'registration'!
register: editor evaluator: evaluator
 Editors ifNil: [Editors := IdentityDictionary new].
 Editors at: editor put: evaluator
! !

!ActionContext methodsFor: 'testing'!
isObject
 ^resolved == true
! !
