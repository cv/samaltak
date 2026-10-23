Object subclass: #Desktop
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Widgets'!

Desktop comment: 'I am the window system as the layer above (Tools) sees it: a class-side facade over UI-Windows'' World, Window and UIWindows, so code above UI-Widgets never names them. I only forward: "Desktop current" answers the running World and "Desktop newWindow" a new Window, and their own protocol does the rest.'!

!Desktop class methodsFor: 'accessing'!
current
	"The running World, or nil."
	^World current
!
isRunning
	^World current notNil and: [World current isRunning]
!
windowClass
	^Window
! !

!Desktop class methodsFor: 'windows'!
newWindow
	"A new Window: set its title, content and bounds, then open it."
	^Window new
!
windowErrorHandler: aBlockOrNil
	"aBlockOrNil value: anError value: aWindow handles errors in a window's Process (nil: the default report)."
	Window errorHandler: aBlockOrNil
! !

!Desktop class methodsFor: 'hooks'!
helpHandler: aBlockOrNil
	World helpHandler: aBlockOrNil
!
userInterruptHandler: aBlock
	World userInterruptHandler: aBlock
!
worldMenuBuilder: aBlock
	World worldMenuBuilder: aBlock
! !

!Desktop class methodsFor: 'starting'!
runStartupAction
	^UIWindows runStartupAction
!
startUp
	UIWindows startUp
!
startupAction: aBlock
	UIWindows startupAction: aBlock
! !
