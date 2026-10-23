WindowGesture subclass: #ResizeGesture
	instanceVariableNames: 'zone start startBounds'
	classVariableNames: ''
	package: 'UI-Windows'!

ResizeGesture comment: 'I resize a window from the zone that was pressed (#resizeL, #resizeR, #resizeB or #resizeBR; Window>>zoneAt:) by the pointer''s distance from start, applied to startBounds, keeping the window''s minExtent.'!

!ResizeGesture methodsFor: 'accessing'!
zone
	^zone
!
setZone: aSymbol start: aPoint bounds: aRectangle
	zone := aSymbol.
	start := aPoint.
	startBounds := aRectangle
! !

!ResizeGesture methodsFor: 'pointer'!
pointerMoved: p
	| r dx dy minW minH left |
	r := startBounds.
	dx := p x - start x.
	dy := p y - start y.
	minW := window minExtent x.
	minH := window minExtent y.
	(zone == #resizeR or: [zone == #resizeBR]) ifTrue: [r := r origin extent: (r width + dx max: minW) @ r height].
	(zone == #resizeB or: [zone == #resizeBR]) ifTrue: [r := r origin extent: r width @ (r height + dy max: minH)].
	zone == #resizeL ifTrue: [
		left := (r left + dx) min: r right - minW.
		r := left @ r top corner: r corner].
	window bounds: r
! !

!ResizeGesture class methodsFor: 'instance creation'!
window: aWindow zone: aSymbol start: aPoint bounds: aRectangle
	^self new setWindow: aWindow; setZone: aSymbol start: aPoint bounds: aRectangle; yourself
! !
