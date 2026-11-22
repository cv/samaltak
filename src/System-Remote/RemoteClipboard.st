Object subclass: #RemoteClipboard
	instanceVariableNames: ''
	classVariableNames: 'Watchers'
	package: 'System-Remote'!

RemoteClipboard comment: 'I tell the image''s remote clients (remote display viewers: RfbInput) when its clipboard changes, and set it for them. The World reports what is copied (World>>clipboard: calls changed:); set: sets the clipboard through the World if there is one (late-bound: UI-Windows is above me), else the firmware display''s or the host''s, and tells the watchers. A watcher gets clipboardChanged: aString in the Process that changed the clipboard, so it must only note it and signal. The watchers are an Array replaced on each change, so changed: needs no lock.'!

!RemoteClipboard class methodsFor: 'watching'!
watchers
	^Watchers ifNil: [#()]
!
watch: anObject
	(self watchers includes: anObject) ifFalse: [Watchers := self watchers copyWith: anObject]
!
unwatch: anObject
	Watchers := self watchers copyWithout: anObject
!
changed: aString
	"The image's clipboard is now aString."
	self watchers do: [:w | [w clipboardChanged: aString] on: Error do: [:e | e return: nil]]
! !

!RemoteClipboard class methodsFor: 'setting'!
set: aString
	"Set the image's clipboard to aString (a remote client pasted it)."
	| world |
	world := (Smalltalk at: #World ifAbsent: [nil]) ifNotNil: [:c | c current].
	world notNil ifTrue: [^world clipboard: aString].
	FirmwareDisplay current
		ifNil: [(Smalltalk at: #HostWindow ifAbsent: [nil]) ifNotNil: [:h | [h clipboard: aString] on: Error do: [:e | e return: nil]]]
		ifNotNil: [:d | d clipboardSet: aString].
	self changed: aString
! !
