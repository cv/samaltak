ListView subclass: #FileColumn
	instanceVariableNames: 'directory'
	classVariableNames: ''
	package: 'Tools'!

FileColumn comment: 'I am a column of the File Browser: a folder''s entries (FileBrowserEntry), folders first, each sorted by name, names starting with a dot left out. Each row has a glyph (a folder, or a page: its lines ultramarine for Smalltalk, ink for C, grey for other text, halftone for binary) and on the right a folder''s ▸ or a text file''s lines. A sideways wheel is my owner''s (FileColumns).

	(FileColumn on: ''src'') items'!

!FileColumn methodsFor: 'initialization'!
initialize
	super initialize.
	self
		labelBlock: [:entry | entry name];
		cellBlock: [:canvas :rect :entry :inverted | self drawGlyphOf: entry in: rect on: canvas inverted: inverted];
		rightBlock: [:entry | entry isDirectory
			ifTrue: [String with: (Character value: 16r25B8)]
			ifFalse: [entry lines ifNotNil: [:n | ProfilerFormat count: n]]];
		remoteStateBlock: [:entry | entry isDirectory
			ifTrue: #('dir')
			ifFalse: [entry lines isNil ifTrue: [#()] ifFalse: [Array with: 'lines=', entry lines printString]]];
		emptyText: 'empty folder'
! !

!FileColumn methodsFor: 'accessing'!
directory
	^directory
!
directory: aPath
	"List the folder aPath (FileError if it cannot be read)."
	| names entries |
	names := ((Directory entries: aPath) reject: [:each | each first = $.])
		asSortedCollection: [:a :b | a asLowercase <= b asLowercase].
	entries := names asArray collect: [:each | FileBrowserEntry on: (File join: aPath with: each)].
	directory := aPath.
	self title: (File baseName: aPath).
	self items: (entries select: [:each | each isDirectory]), (entries reject: [:each | each isDirectory])
!
entryNamed: aString
	^items detect: [:each | each name = aString] ifNone: [nil]
! !

!FileColumn methodsFor: 'drawing'!
drawGlyphOf: anEntry in: aRect on: aCanvas inverted: inverted
	| ink r kind marks |
	ink := inverted ifTrue: [self theme paper] ifFalse: [self theme ink].
	anEntry isDirectory ifTrue: [
		r := aRect left @ (aRect top + (aRect height - 8 / 2) + 1) rounded extent: 11 @ 8.
		aCanvas fillRect: (r left @ (r top - 2) extent: 5 @ 2) color: ink.
		^aCanvas strokeRect: r color: ink width: 1].
	r := aRect left + 1 @ (aRect top + (aRect height - 11 / 2)) rounded extent: 9 @ 11.
	aCanvas strokeRect: r color: ink width: 1.
	kind := anEntry kind.
	kind == #binary ifTrue: [^aCanvas pattern: #halftone in: (r insetBy: 2) color: ink].
	marks := inverted ifTrue: [ink] ifFalse: [
		kind == #smalltalk ifTrue: [self theme ultramarine] ifFalse: [kind == #c ifTrue: [ink] ifFalse: [self theme color: #ink4]]].
	1 to: (kind == #text ifTrue: [2] ifFalse: [3]) do: [:i |
		aCanvas fillRect: (r left + 2 @ (r top + (i * 2) + 1) extent: 5 @ 1) color: marks]
! !

!FileColumn methodsFor: 'events'!
wheel: anEvent
	anEvent delta y = 0 ifTrue: [^false].
	^super wheel: anEvent
! !

!FileColumn class methodsFor: 'instance creation'!
on: aPath
	^self new directory: aPath; yourself
! !
