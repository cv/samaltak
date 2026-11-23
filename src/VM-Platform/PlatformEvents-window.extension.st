!PlatformEvents methodsFor: '*VM-Platform-window'!
peekForFFI: out
	"Borrow the head's text until next:; VM thread only, never expose it to the image."
	<function>
	<var: #out type: 'pf_event *'>
	<returns: 'bool'>
	qLen = 0 ifTrue: [^false].
	out copyStructFrom: q + qHead.
	^true
! !
