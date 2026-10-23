!Behavior methodsFor: 'system startup'!
startUp: resuming
	"Sent to classes in the startup list when the image starts; resuming is true after a snapshot was resumed."
	self startUp
!
startUp
!
shutDown: quitting
	"Sent to classes in the shutdown list before a snapshot (quitting false) or quit (quitting true)."
	self shutDown
!
shutDown
! !
