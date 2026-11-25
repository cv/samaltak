Object subclass: #Desktop
	instanceVariableNames: ''
	classVariableNames: 'ToolsLoading'
	package: 'UI-Widgets'!

Desktop comment: 'I am the window system as the layer above (Tools) sees it: a class-side facade over UI-Windows'' World, Window and UIWindows, so code above UI-Widgets never names them. I only forward: "Desktop current" answers the running World and "Desktop newWindow" a new Window, and their own protocol does the rest. animationTimeScale: is Animation timeScale: (slow motion).'!

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
	"A new Window: set its title, content and bounds, then open it. In an application's process (its World an AppWorld) one without chrome, which opens in a host window of its own."
	^World current isNil ifTrue: [Window new] ifFalse: [World current newWindow]
!
windowErrorHandler: aBlockOrNil
	"aBlockOrNil value: anError value: aWindow handles errors in a window's Process (nil: the default report)."
	Window errorHandler: aBlockOrNil
! !

!Desktop class methodsFor: 'tools'!
actions
	"ActionContext, the tools' contextual actions (⌘I inspect, ⌘B browse, ⌘J the Agent), or nil. Where the image has no tools (an application's runtime image) Tools and Tools-Agent are filed in from the source the first time they are asked for (loadTools)."
	^Smalltalk at: #ActionContext ifAbsent: [
		self loadTools.
		Smalltalk at: #ActionContext ifAbsent: [nil]]
!
loadTools
	"File in Tools and Tools-Agent from the source directory (SourceFiler), once, keeping how window errors are handled (an application reports them; the tools would open the debugger). Nothing without a source directory."
	| directory handler |
	ToolsLoading isNil ifTrue: [ToolsLoading := Mutex new].
	ToolsLoading critical: [
		(Smalltalk includesKey: #ActionContext) ifTrue: [^self].
		directory := SourceFiler default sourceDirectory.
		directory isNil ifTrue: [^self].
		handler := Window errorHandler.
		[#('Tools' 'Tools-Agent') do: [:each | Compiler fileInPackage: directory, '/', each]]
			ensure: [Window errorHandler: handler]]
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

!Desktop class methodsFor: 'animation'!
animationTimeScale
	^Animation timeScale
!
animationTimeScale: aNumber
	"Run every animation aNumber times slower (10: slow motion, 1: normal)."
	Animation timeScale: aNumber
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
