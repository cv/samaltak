RfbFrameSource subclass: #RfbBufferSource
	instanceVariableNames: 'extent bytes cursor'
	classVariableNames: ''
	package: 'System-Remote'!

RfbBufferSource comment: 'I am a screen in memory, BGRA8 rows: what RFB tests draw on (fill:red:green:blue:, at:put:, move:to:) and a frame source to run an RfbServer against without a World. Each change tells my listeners at once.'!

!RfbBufferSource methodsFor: 'initialization'!
setExtent: aPoint
	extent := aPoint.
	bytes := ByteArray new: aPoint x * aPoint y * 4
! !

!RfbBufferSource methodsFor: 'screen'!
extent
	^extent
!
bytes
	^bytes
!
bgraOf: aRectangle
	| out w |
	w := aRectangle width.
	out := ByteArray new: w * aRectangle height * 4.
	0 to: aRectangle height - 1 do: [:y | | from |
		from := (aRectangle top + y) * extent x + aRectangle left * 4 + 1.
		out replaceFrom: y * w * 4 + 1 to: y + 1 * w * 4 with: bytes startingAt: from].
	^out
!
cursor
	^cursor ifNil: [super cursor]
!
cursor: anRfbCursor
	cursor := anRfbCursor.
	self notify: [:each | each cursorChanged]
! !

!RfbBufferSource methodsFor: 'drawing'!
at: aPoint put: anArray
	"A pixel {red. green. blue}."
	| o |
	o := aPoint y * extent x + aPoint x * 4.
	bytes at: o + 1 put: (anArray at: 3); at: o + 2 put: (anArray at: 2); at: o + 3 put: (anArray at: 1); at: o + 4 put: 255.
	self notify: [:each | each damaged: (Array with: (aPoint extent: 1 @ 1))]
!
fill: aRectangle red: r green: g blue: b
	| rect |
	rect := aRectangle intersect: self bounds.
	rect isEmpty ifTrue: [^self].
	rect top to: rect bottom - 1 do: [:y |
		rect left to: rect right - 1 do: [:x | | o |
			o := y * extent x + x * 4.
			bytes at: o + 1 put: b; at: o + 2 put: g; at: o + 3 put: r; at: o + 4 put: 255]].
	self notify: [:each | each damaged: (Array with: rect)]
!
fillWith: aBlock
	"Every pixel {red. green. blue} from aBlock value: x value: y, one damage of all."
	0 to: extent y - 1 do: [:y |
		0 to: extent x - 1 do: [:x | | o c |
			o := y * extent x + x * 4.
			c := aBlock value: x value: y.
			bytes at: o + 1 put: (c at: 3); at: o + 2 put: (c at: 2); at: o + 3 put: (c at: 1); at: o + 4 put: 255]].
	self notify: [:each | each damagedAll]
!
move: aRectangle to: aPoint
	"Copy aRectangle's pixels to aPoint (as a window drag would) and say so (moved:to:), with the uncovered part of the source as damage."
	| pixels w |
	pixels := self bgraOf: aRectangle.
	w := aRectangle width.
	0 to: aRectangle height - 1 do: [:y | | to |
		to := (aPoint y + y) * extent x + aPoint x * 4 + 1.
		bytes replaceFrom: to to: to + (w * 4) - 1 with: pixels startingAt: y * w * 4 + 1].
	self notify: [:each | each moved: aRectangle to: aPoint]
!
extent: aPoint
	self setExtent: aPoint.
	self notify: [:each | each resized: aPoint]
! !

!RfbBufferSource class methodsFor: 'instance creation'!
extent: aPoint
	^self new setExtent: aPoint
! !
