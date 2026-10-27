ToolPane subclass: #FileBrowser
	instanceVariableNames: 'root pathBar columns preview header viewer info file openMs'
	classVariableNames: ''
	package: 'Tools'!

FileBrowser comment: 'I am the File Browser, a column browser (NeXTSTEP''s, Finder''s column view) in the Blue Book style: a FileColumn per folder from the folder I opened at (the working directory: the repository) down to the selection, side by side, scrolling sideways when they do not fit (FileColumns). Selecting a folder opens it as the next column (the columns after it close); selecting a file shows it in a preview column at the end: its name, kind, lines and size, its text (FileViewer: line numbers, Smalltalk highlighted for .st, C for .c and .h, a binary file''s first KB as a hex dump) and when it was modified. Up and down move in a column, right and left between columns; return is right (on a file: into its text). Above the columns the path of the last folder: a click on a segment goes back to it.

	FileBrowser open.
	FileBrowser openOn: ''vm/gen/interpreter.c''.
	Tools open: #files with: ''src/VM-Core''.

Remote: @wN.column-1 … (a list per column, labelled with its folder; rows named after the entries: @wN.column-3.interpreter-c, state dir or lines=), @wN.path (a button per segment: @wN.path.vm), @wN.file (the preview''s header: the name, right= kind, lines and size), @wN.viewer (top= the first line shown; the lines shown), @wN.info (modified, opened in).'!

!FileBrowser methodsFor: 'initialization'!
initialize
	super initialize.
	self build
!
build
	pathBar := FilePathBar new name: 'path'; fixed: 28; yourself.
	pathBar onClick: [:path | self showFolder: path].
	columns := FileColumns new.
	header := DebuggerPaneHeader new titleFont: #code12Bold; name: 'file'; yourself.
	viewer := FileViewer new name: 'viewer'; title: 'viewer'; yourself.
	info := StatusBar new name: 'info'; yourself.
	preview := Column with: (Array with: header with: viewer with: info).
	self addAll: (Array with: pathBar with: columns)
!
minimumWindowExtent
	^520 @ 280
! !

!FileBrowser methodsFor: 'accessing'!
root
	"The folder of the first column; paths are shown from it."
	^root
!
root: aPath
	root := aPath
!
pathBar
	^pathBar
!
columns
	^columns
!
lists
	^columns lists
!
listAt: anInteger
	^self lists at: anInteger
!
header
	^header
!
viewer
	^viewer
!
info
	^info
!
file
	"The entry the preview shows, or nil."
	^file
! !

!FileBrowser methodsFor: 'browsing'!
browse: aPath
	"Start the columns at the folder aPath (absolute)."
	root := aPath.
	self closeAfter: 0.
	self addColumnOn: aPath.
	self updatePath
!
reveal: aPath
	"Select aPath (relative to my root, or absolute: outside my root I start at its folder) column by column: a folder's contents or a file's preview at the end; its column gets the keys."
	| full list |
	full := (aPath beginsWith: '/') ifTrue: [aPath] ifFalse: [File join: root with: aPath].
	[full size > 1 and: [full last = $/]] whileTrue: [full := full allButLast].
	(self isUnderRoot: full) ifFalse: [
		self browse: ((File isDirectory: full) ifTrue: [full] ifFalse: [File directoryOf: full])].
	self lists isEmpty ifTrue: [^self].
	list := self lists first.
	list selectIndex: 0.
	((full allButFirst: root size) subStrings: '/') do: [:each | | entry |
		list := self lists last.
		entry := list entryNamed: each.
		entry isNil ifTrue: [^Tools toast: 'No ', each, ' in ', (self displayPath: list directory)].
		list select: entry].
	list focus
!
selected: anEntry in: aList
	"A column's selection changed: the columns after it close; a folder opens as the next column, a file in the preview."
	self closeAfter: (self lists indexOf: aList).
	anEntry isNil ifFalse: [
		anEntry isDirectory ifTrue: [self addColumnOn: anEntry path] ifFalse: [self show: anEntry]].
	self updatePath.
	columns scrollToShowEnd
!
enter: anEntry from: aList
	"Right or return: into the folder's column (its first entry selected), or into the file's text."
	| next |
	anEntry isNil ifTrue: [^self].
	anEntry isDirectory ifFalse: [^viewer focus].
	next := self lists at: (self lists indexOf: aList) + 1 ifAbsent: [^self].
	next focus.
	(next selection isNil and: [next items notEmpty]) ifTrue: [next selectIndex: 1].
	columns scrollToShow: next
!
leave: aList
	"Left: back to the column before, which keeps its selection; aList stays open, without one."
	| i |
	i := self lists indexOf: aList.
	i <= 1 ifTrue: [^self].
	aList selectIndex: 0.
	(self listAt: i - 1) focus.
	columns scrollToShow: (self listAt: i - 1)
!
showFolder: aPath
	"A click on the path: that folder's column becomes the last."
	| list |
	list := self lists detect: [:each | each directory = aPath] ifNone: [^self].
	list selectIndex: 0.
	list focus.
	columns scrollToShow: list
!
closeAfter: index
	"Close the columns after the index-th and the preview; the keys go to the index-th if they were in what closed."
	| focus |
	focus := self window isNil ifFalse: [self window keyboardFocus].
	columns removeListsAfter: index; preview: nil.
	file := nil.
	(index > 0 and: [focus notNil and: [focus window isNil]]) ifTrue: [(self listAt: index) focus]
!
addColumnOn: aPath
	| list |
	list := [FileColumn on: aPath] on: FileError do: [:e |
		Tools toast: 'Cannot list ', (self displayPath: aPath), ': ', e messageText asString.
		^nil].
	list name: 'column-', (self lists size + 1) printString.
	list
		onSelect: [:entry | self selected: entry in: list];
		onDoubleClick: [:entry | self enter: entry from: list].
	columns addList: list.
	^list
!
isUnderRoot: aPath
	^aPath = root or: [aPath beginsWith: (root = '/' ifTrue: [root] ifFalse: [root, '/'])]
! !

!FileBrowser methodsFor: 'previewing'!
show: anEntry
	"Preview anEntry's file: its text, or a binary file's first KB as a hex dump."
	| t0 text |
	t0 := Time millisecondClockValue.
	text := [anEntry isBinary ifTrue: [self hexDumpOf: anEntry] ifFalse: [anEntry text]]
		on: FileError do: [:e |
			Tools toast: 'Cannot read ', anEntry name, ': ', e messageText asString.
			^nil].
	file := anEntry.
	columns preview: preview.
	viewer show: text kind: anEntry kind.
	viewer ensureTokens.
	openMs := Time millisecondClockValue - t0.
	header title: anEntry name; rightText: (self describe: anEntry).
	info clear.
	info add: 'modified ', (self timeString: anEntry modificationTime).
	info addRight: 'opened in ', openMs printString, ' ms' style: #text
!
hexDumpOf: anEntry
	"The first KB as hexdump -C shows it."
	| bytes hex |
	bytes := anEntry readBytes: 1024.
	hex := '0123456789abcdef'.
	^String new: bytes size * 5 streamContents: [:s |
		0 to: bytes size - 1 by: 16 do: [:offset | | n |
			n := 16 min: bytes size - offset.
			s nextPutAll: ((offset printString: 16) asLowercase padLeftTo: 8 with: $0); space.
			1 to: 16 do: [:i |
				s space.
				i <= n
					ifTrue: [s nextPut: (hex at: (bytes at: offset + i) // 16 + 1); nextPut: (hex at: (bytes at: offset + i) \\ 16 + 1)]
					ifFalse: [s space; space].
				i = 8 ifTrue: [s space]].
			s space; space; nextPut: $|.
			1 to: n do: [:i | | b |
				b := bytes at: offset + i.
				s nextPut: ((b between: 32 and: 126) ifTrue: [Character value: b] ifFalse: [$.])].
			s nextPut: $|; nextPut: Character lf].
		anEntry size > bytes size ifTrue: [s nextPutAll: '…']]
! !

!FileBrowser methodsFor: 'describing'!
updatePath
	| last |
	self lists isEmpty ifTrue: [^self].
	last := self lists last.
	pathBar segments: (self segmentsOf: last directory); summary: (self summaryOf: last items).
	self windowTitle: 'File Browser: ', (file isNil ifTrue: [File baseName: last directory] ifFalse: [file name])
!
segmentsOf: aPath
	"{label. path} pairs: my root by name and the folders below it."
	| result path |
	result := OrderedCollection with: (Array with: (root = '/' ifTrue: [root] ifFalse: [File baseName: root]) with: root).
	path := root = '/' ifTrue: [''] ifFalse: [root].
	((aPath allButFirst: root size) subStrings: '/') do: [:each |
		path := path, '/', each.
		result add: (Array with: each with: path)].
	^result asArray
!
summaryOf: entries
	| folders |
	folders := (entries select: [:each | each isDirectory]) size.
	^(self count: folders of: 'folder'), ProfilerFormat dot, (self count: entries size - folders of: 'file')
!
count: n of: aString
	^n printString, ' ', aString, (n = 1 ifTrue: [''] ifFalse: ['s'])
!
describe: anEntry
	"Its kind, lines and size (and how much of it the viewer shows)."
	| s kind |
	kind := anEntry kind.
	s := kind == #smalltalk ifTrue: ['Smalltalk'] ifFalse: [kind == #c ifTrue: ['C'] ifFalse: [kind asString]].
	anEntry lines isNil ifFalse: [s := s, ProfilerFormat dot, (ProfilerFormat count: anEntry lines), (anEntry lines = 1 ifTrue: [' line'] ifFalse: [' lines'])].
	s := s, ProfilerFormat dot, (ProfilerFormat bytes: anEntry size).
	(anEntry isBinary and: [anEntry size > 1024]) ifTrue: [s := s, ProfilerFormat dot, 'first KB shown'].
	(anEntry isBinary not and: [anEntry isTruncated]) ifTrue: [s := s, ProfilerFormat dot, 'first ', (ProfilerFormat bytes: FileBrowserEntry maxTextBytes), ' shown'].
	^s
!
displayPath: aPath
	"aPath from my root (the root by name), else as it is."
	aPath = root ifTrue: [^File baseName: root].
	(self isUnderRoot: aPath) ifTrue: [^aPath allButFirst: root size + 1].
	^aPath
!
timeString: microseconds
	"In UTC: the VM knows no time zone."
	^(Date fromDays: microseconds // 86400000000) printString, ' ', (Time fromSeconds: microseconds // 1000000 \\ 86400) printString, ' UTC'
! !

!FileBrowser methodsFor: 'events'!
keyDown: anEvent
	"Right and left, passed on by a column, move between the columns."
	| focus |
	focus := self window isNil ifFalse: [self window keyboardFocus].
	(self lists includes: focus) ifTrue: [
		anEvent key == #right ifTrue: [self enter: focus selection from: focus. ^true].
		anEvent key == #left ifTrue: [self leave: focus. ^true]].
	^super keyDown: anEvent
! !

!FileBrowser class methodsFor: 'opening'!
open
	^self openOn: nil at: nil
!
openAt: aPointOrNil
	^self openOn: nil at: aPointOrNil
!
openOn: aPathOrNil
	^self openOn: aPathOrNil at: nil
!
openOn: aPathOrNil at: aPointOrNil
	"A File Browser at the working directory (the repository); aPathOrNil (relative to it, or absolute) is revealed: a folder's contents or a file's preview."
	| browser window |
	browser := self new root: Directory current; yourself.
	window := browser openIn: (Tools placeAt: aPointOrNil extent: 1200 @ 640) title: 'File Browser'.
	window do: [
		browser browse: browser root.
		aPathOrNil isNil
			ifTrue: [(browser listAt: 1) focus]
			ifFalse: [browser reveal: aPathOrNil]].
	^window
!
initialize
	ToolsMenu register: 'File Browser' description: 'files', ProfilerFormat dot, 'viewer' order: 46 action: [:point | self openAt: point].
	Tools registerOpener: #files with: [:pathOrNil | self openOn: pathOrNil]
! !
