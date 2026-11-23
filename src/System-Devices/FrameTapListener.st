Object subclass: #FrameTapListener
	instanceVariableNames: 'tap damage semaphore maxRects frame moves'
	classVariableNames: ''
	package: 'System-Devices'!

FrameTapListener comment: 'I am one client''s view of a FrameTap: the damage of the frames presented since it last took it (takeDamage), a DamageRegion of up to maxRects (32: a remote display pays per byte, not per Blt) rectangles, full past half the screen or when a frame was presented whole or at a new size. My semaphore is signalled when my damage stops being empty: wait on it only while hasDamage is false. A client that shares one semaphore for its socket and its damage gives it to me (semaphore:). The frames'' moves (FrameTap>>moved:to:) come with their damage (take), in order; a new size drops them.'!

!FrameTapListener methodsFor: 'initialization'!
setTap: aFrameTap
	tap := aFrameTap.
	semaphore := Semaphore new.
	maxRects := 32.
	frame := 0.
	damage := self regionOf: 0 @ 0
! !

!FrameTapListener methodsFor: 'accessing'!
tap
	^tap
!
semaphore
	^semaphore
!
semaphore: aSemaphore
	semaphore := aSemaphore
!
maxRects: anInteger
	"At most anInteger rectangles (from the next take on)."
	maxRects := anInteger
!
frame
	"The last frame (FrameTap>>frame) whose damage I took in."
	^frame
!
extent
	"The size of the screen my damage is of."
	^damage bounds extent
!
hasDamage
	^tap critical: [damage notEmpty]
!
peekDamage
	"My damage so far, without taking it (a copy)."
	^tap critical: [| d | d := self regionOf: damage bounds extent. d addAll: damage. d]
!
takeDamage
	"The damage since the last take (a DamageRegion of the screen, empty if nothing changed), and start again from none (the frames' moves are dropped: take has them)."
	^self take first
!
take
	"{the damage since the last take (takeDamage). the moves of those frames ({Rectangle. Point} each, in order, all within the screen)}, and start again from none."
	^tap critical: [| d m |
		d := damage.
		m := moves ifNil: [#()] ifNotNil: [moves asArray].
		damage := self regionOf: d bounds extent.
		moves := nil.
		Array with: d with: m]
!
close
	"No more damage."
	tap remove: self
! !

!FrameTapListener methodsFor: 'private'!
extent: aPoint
	"The screen is aPoint pixels (FrameTap, under its lock)."
	damage := self regionOf: aPoint.
	moves := nil
!
frame: n damaged: rectsOrFull extent: aPoint
	self frame: n damaged: rectsOrFull moves: #() extent: aPoint
!
frame: n damaged: rectsOrFull moves: anArray extent: aPoint
	"Frame n was presented, moving anArray's pixels first (FrameTap, under its lock)."
	| was screen |
	was := damage isEmpty.
	frame := n.
	damage bounds extent = aPoint
		ifFalse: [
			damage := self regionOf: aPoint.
			moves := nil.
			damage beFull]
		ifTrue: [
			rectsOrFull == #full
				ifTrue: [damage beFull]
				ifFalse: [
					rectsOrFull do: [:each |
						each isArray
							ifTrue: [damage addLeft: (each at: 1) top: (each at: 2) right: (each at: 1) + (each at: 3) bottom: (each at: 2) + (each at: 4)]
							ifFalse: [damage add: each]]].
			screen := 0 @ 0 extent: aPoint.
			anArray do: [:m |
				((screen containsRect: m first) and: [screen containsRect: ((m at: 2) extent: m first extent)]) ifTrue: [
					(moves ifNil: [moves := OrderedCollection new]) add: m]]].
	(was and: [damage notEmpty]) ifTrue: [semaphore signal]
!
regionOf: aPoint
	^(DamageRegion extent: aPoint) maxRects: maxRects; yourself
! !

!FrameTapListener class methodsFor: 'instance creation'!
tap: aFrameTap
	^self new setTap: aFrameTap
! !
