Object subclass: #WidgetTestTimer
	instanceVariableNames: 'milliseconds block cancelled'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

WidgetTestTimer comment: 'I am a timer a WidgetTestWindow hands out for after:do:; tests fire me explicitly.'!

!WidgetTestTimer methodsFor: 'accessing'!
setMilliseconds: ms block: aBlock
	milliseconds := ms.
	block := aBlock.
	cancelled := false
!
milliseconds
	^milliseconds
!
cancel
	cancelled := true
!
isCancelled
	^cancelled
!
fire
	cancelled ifFalse: [cancelled := true. block value]
! !

!WidgetTestTimer class methodsFor: 'instance creation'!
after: ms do: aBlock
	^self new setMilliseconds: ms block: aBlock
! !
