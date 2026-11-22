Object subclass: #WorldToast
	instanceVariableNames: 'world text duration start opacity offset done'
	classVariableNames: ''
	package: 'UI-Windows'!

WorldToast comment: 'I am a short message the World shows centered below the top bar (Blue Book: white italic on black with a hard white-and-black shadow). I slide down 4 points and fade in over 180 ms, stay for my duration, then fade out. The Compositor steps and draws me.'!

!WorldToast methodsFor: 'initialization'!
setWorld: aWorld text: aString duration: milliseconds
	world := aWorld.
	text := aString asString.
	duration := milliseconds.
	opacity := 0.
	offset := 0.
	done := false
! !

!WorldToast methodsFor: 'accessing'!
text
	^text
!
isDone
	^done
!
font
	^Font uiItalic
!
extent
	^((self font widthOf: text) + 26) rounded @ ((self font lineHeight + 14) rounded)
! !

!WorldToast methodsFor: 'animating'!
stepAt: ms
	"Answer whether I still need frames."
	| t |
	done ifTrue: [^false].
	start isNil ifTrue: [start := ms].
	t := ms - start.
	t < 180
		ifTrue: [self appear: (Animation ease: #easeOutCubic at: t / 180)]
		ifFalse: [
			t < (180 + duration)
				ifTrue: [self appear: 1. ^false]
				ifFalse: [
					t < (360 + duration)
						ifTrue: [self appear: 1 - (Animation ease: #easeInCubic at: t - 180 - duration / 180)]
						ifFalse: [done := true. world dropToast: self. ^false]]].
	^true
!
needsFramesAt: ms
	"Answer whether I am animating at ms (fading in or out)."
	| t |
	(done or: [start isNil]) ifTrue: [^done not].
	t := ms - start.
	^t < 180 or: [t >= (180 + duration)]
!
appear: f
	opacity := f.
	offset := 4 * f
! !

!WorldToast methodsFor: 'drawing'!
drawOn: c at: aPoint
	"aPoint: top center."
	| ext box |
	ext := self extent.
	box := (aPoint x - (ext x / 2)) rounded @ (aPoint y + offset) extent: ext.
	c alpha: opacity during: [
		c fillRect: (box translateBy: 3 @ 3) color: Color shadow.
		c fillRect: (box translateBy: 2 @ 2) color: Color paper.
		c fillRect: box color: Color ink.
		c drawString: text at: box origin + (13 @ 7) font: self font color: Color paper]
! !

!WorldToast methodsFor: 'remote control'!
remoteRole
	^#toast
!
remoteLabel
	^text
!
remoteName
	^'toast'
!
remoteState
	^#()
!
remoteChildren
	^#()
! !

!WorldToast class methodsFor: 'instance creation'!
world: aWorld text: aString duration: milliseconds
	^self new setWorld: aWorld text: aString duration: milliseconds
! !
