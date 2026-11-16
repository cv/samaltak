!FileBrowser methodsFor: '*Tools-Agent'!
agentContext
	"The selected file or folder: its path and entry; the text selected in the previewed file."
	| entry |
	entry := (self lists reverse detect: [:each | each selection notNil] ifNone: [nil]) ifNotNil: [:list | list selection].
	^super agentContext
		bind: #path to: (entry ifNotNil: [:e | e path]);
		bind: #entry to: entry;
		selection: ((file notNil and: [viewer hasSelection]) ifTrue: [viewer selectedText]);
		yourself
! !
