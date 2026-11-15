ToolsTestCase subclass: #TerminalTest
	instanceVariableNames: 'window terminal'
	classVariableNames: ''
	package: 'Tests-Tools'!

TerminalTest comment: 'I test the Terminal tool end to end: real programs on a real pty in a Terminal window of a hidden World, driven by injected key and text events (the path of real and remote input): colors from a real program, typing into /bin/sh (prompt "$ ") and ctrl-C, resizing, a full-screen program (less) and back, heavy output while another window stays responsive, the title from OSC, remote control (snapshot state and text, type and wait), retained drawing, and hanging up on close.'!

!TerminalTest methodsFor: 'running'!
tearDown
	window isNil ifFalse: [window close].
	super tearDown
!
timeLimitMilliseconds
	^120000
! !

!TerminalTest methodsFor: 'support'!
openOn: argv
	window := self open: [Terminal openOn: argv in: '/' at: 100 @ 80].
	terminal := window content.
	self assert: (self waitFor: [terminal ioProcess notNil]) description: 'the terminal did not start'.
	^window
!
openShell
	"/bin/sh with the prompt '$ '."
	self openOn: #('/bin/sh' '-c' 'PS1=''$ '' exec /bin/sh -i').
	window focus.
	self assert: (self waitFor: [self promptCount = 1] timeout: 20000) description: 'no prompt: ', self text printString.
	^window
!
screen
	^terminal screen
!
text
	^self screen text
!
waitForText: aString
	self assert: (self waitFor: [self text includesSubstring: aString] timeout: 20000)
		description: 'no ', aString printString, ' on the screen: ', self text printString
!
type: aString
	DisplayWindow injectEvent: {7. nil. 0. 0. 0. 0. aString. world displayWindow windowId}
!
enter: aString
	self type: aString.
	self key: #return modifiers: 0
!
promptCount
	^(self text lines select: [:line | line beginsWith: '$']) size
!
ptys
	^Smalltalk vm platformHandleCounts at: #ptys ifAbsent: [0]
! !

!TerminalTest methodsFor: 'tests'!
testColorsFromARealProgram
	| line |
	self openOn: #('/bin/sh' '-c' 'printf "\033[1;31mred\033[0m ok\n"').
	self waitForText: '[Process completed]'.
	line := self screen lineAt: 1.
	self assert: line string equals: 'red ok'.
	1 to: 3 do: [:c |
		self assert: (TerminalScreen isBold: (line attributeAt: c)).
		self assert: (TerminalScreen foregroundOf: (line attributeAt: c)) equals: 2].
	self assert: (line attributeAt: 4) equals: 0.
	self assert: (line attributeAt: 5) equals: 0.
	self assert: (terminal view remoteState includes: 'exited=0')
!
testExitStatusIsShown
	self openOn: #('/bin/sh' '-c' 'exit 3').
	self waitForText: '[Process exited with status 3]'.
	self deny: terminal isRunning
!
testTypingIntoAShell
	self openShell.
	self enter: 'echo $((6*7)) ü'.
	self waitForText: (String with: Character lf), '42 ü'.
	self assert: (self text includesSubstring: '$ echo $((6*7)) ü').
	self assert: (self waitFor: [self promptCount = 2]).
	self key: #backspace modifiers: 0.
	self type: 'x'.
	self key: #left modifiers: 0.
	self type: 'y'.
	self key: #return modifiers: 0.
	self waitForText: 'not found'.
	self assert: (self text includesSubstring: '$ yx')
!
testControlCInterruptsTheForegroundJob
	self openShell.
	self enter: 'sh -c "echo sta""rted; exec sleep 100"'.
	self waitForText: (String with: Character lf), 'started'.
	self key: $c modifiers: 2.
	self assert: (self waitFor: [self promptCount = 2] timeout: 10000) description: self text.
	self key: $d modifiers: 2.
	self waitForText: '[Process exited with status 130]'
!
testResizingTellsTheProgram
	| rows cols |
	self openShell.
	self assert: self screen rows @ self screen cols equals: 24 @ 80.
	window bounds: (window bounds origin extent: 420 @ 300).
	self assert: (self waitFor: [self screen cols < 80]).
	rows := self screen rows.
	cols := self screen cols.
	self assert: (terminal view gridExtentFor: window contentExtent) equals: rows @ cols.
	self enter: 'stty size'.
	self waitForText: rows printString, ' ', cols printString
!
testFullScreenProgramAndBack
	| path |
	path := self scratchDirectory, '/lines.txt'.
	File writeText: (String new: 2000 streamContents: [:s | 1 to: 200 do: [:i | s nextPutAll: 'line '; print: i; nextPut: Character lf]]) to: path.
	self openShell.
	self enter: 'less ', path.
	self assert: (self waitFor: [self screen isAlternateScreen and: [self text includesSubstring: 'line 23']] timeout: 20000) description: self text.
	self assert: (self screen textOfRow: 1) equals: 'line 1'.
	self deny: (self text includesSubstring: '$ less').
	self key: #space modifiers: 0.
	self type: ' '.
	self assert: (self waitFor: [self text includesSubstring: 'line 40']).
	self type: 'q'.
	self assert: (self waitFor: [self screen isAlternateScreen not and: [self promptCount = 2]]) description: self text.
	self assert: (self text includesSubstring: '$ less ', path)
!
testHeavyOutputKeepsOtherWindowsResponsive
	| other first trips done frames gaps |
	other := self openWorkspaceWith: '3 + 4'.
	self openShell.
	first := Profiler default frameCount.
	trips := OrderedCollection new.
	self enter: 'yes | head -200000; echo DONE-$((6*7))'.
	done := false.
	[done] whileFalse: [ | t |
		t := Time millisecondClockValue.
		other sync: [nil].
		trips add: Time millisecondClockValue - t.
		(Delay forMilliseconds: 20) wait.
		done := (self text includesSubstring: 'DONE-42') or: [trips size > 3000]].
	self assert: (self text includesSubstring: 'DONE-42').
	self assert: self screen scrollback size equals: self screen maxScrollback.
	self assert: (self screen scrollback last string) equals: 'y'.
	self assert: (trips inject: 0 into: [:a :b | a max: b]) < 1000 description: 'another window was slow to answer'.
	frames := Profiler default framesAfter: first.
	self assert: frames size > 3.
	gaps := (2 to: frames size) collect: [:i | (frames at: i) start - (frames at: i - 1) start].
	self assert: (gaps inject: 0 into: [:a :b | a + b]) / gaps size < 50000 description: 'the compositor fell behind while the terminal was busy'
!
testTitleFromOsc
	self openOn: #('/bin/sh' '-c' 'printf "\033]0;hello title\007"; exec cat').
	self assert: (self waitFor: [window title = 'Terminal — hello title']) description: window title.
	self assert: (terminal view remoteState includes: 'title="hello title"')
!
testRemoteControl
	| saved r view state |
	saved := RemoteControl registryState.
	UIRemote installOn: world.
	[self openShell.
	 r := RemoteControl dispatch: (RemoteRequest on: (Dictionary new
		at: 'cmd' put: 'type'; at: 'target' put: '@w1.terminal'; at: 'text' put: 'echo remote-$((40+2))', (String with: Character lf); at: 'delay' put: 5; yourself)).
	 self assert: (r at: 'ok').
	 r := RemoteControl dispatch: (RemoteRequest on: (Dictionary new at: 'cmd' put: 'wait'; at: 'text' put: 'remote-42'; at: 'timeout' put: 20000; yourself)).
	 self assert: (r at: 'ok') description: r printString.
	 r := RemoteControl dispatch: (RemoteRequest on: (Dictionary new at: 'cmd' put: 'snapshot'; at: 'ref' put: '@w1.terminal'; yourself)).
	 self assert: ((r at: 'text') includesSubstring: 'terminal @w1.terminal rows=24 cols=80 cursor=') description: (r at: 'text').
	 self assert: ((r at: 'text') includesSubstring: '| remote-42')]
		ensure: [UIRemote uninstall. RemoteControl registryState: saved].
	view := terminal view.
	self assert: view remoteRole equals: #terminal.
	self assert: view remoteName equals: 'terminal'.
	state := view remoteState.
	self assert: (state includes: 'rows=24').
	self assert: (state includes: 'cursor=', self screen row printString, ',3').
	self assert: (view remoteText lines includes: 'remote-42')
!
testScrollbackAndSelection
	| view |
	self openShell.
	self enter: 'i=0; while [ $i -lt 60 ]; do i=$((i+1)); echo row-$i; done'.
	self waitForText: 'row-60'.
	self assert: (self waitFor: [(self screen textOfRow: self screen row) = '$']) description: 'no prompt after the rows'.
	view := terminal view.
	self in: window do: [view scrollBy: 30].
	self assert: view scrollOffset equals: 30.
	self assert: (view remoteText includesSubstring: 'row-10') description: view remoteText.
	self deny: (view remoteText includesSubstring: 'row-60') description: view remoteText.
	self assert: (view remoteState includes: 'scrolled=30') description: view remoteState printString.
	self in: window do: [ | index |
		index := view topLineIndex + ((view shownLines indexOf: 'row-10') - 1).
		view select: (Array with: index with: 1) to: (Array with: index + 1 with: 6)].
	self assert: view selectedText equals: 'row-10', (String with: Character lf), 'row-11'.
	self assert: window retainedDrawingMismatch equals: nil.
	self type: 'x'.
	self assert: (self waitFor: [view scrollOffset = 0]).
	self waitForText: '$ x'
!
testRetainedDrawingStaysValid
	| view |
	View verifyDrawing: true.
	[self openShell.
	 view := terminal view.
	 self enter: 'i=0; while [ $i -lt 40 ]; do i=$((i+1)); printf "\033[3$((i % 8))m%s \033[7m%s\033[0m ─┼─ 日本😀e\314\201\n" row-$i $i; done'.
	 self waitForText: 'row-40'.
	 self assert: (self waitFor: [(self screen textOfRow: self screen row) = '$']).
	 self in: window do: [view scrollBy: 10].
	 self settle.
	 self in: window do: [view select: (Array with: view topLineIndex with: 2) to: (Array with: view topLineIndex + 3 with: 5)].
	 self settle.
	 self in: window do: [view scrollBy: -10. view clearSelection].
	 self settle.
	 self assert: View staleDrawings isEmpty description: View staleDrawings printString.
	 self assert: window retainedDrawingMismatch equals: nil]
		ensure: [View verifyDrawing: false]
!
testBracketedPaste
	self openOn: #('/bin/sh' '-c' 'printf "\033[?2004h"; exec cat').
	self assert: (self waitFor: [self screen bracketedPaste]).
	self in: window do: [terminal view pasteText: 'pasted'].
	self waitForText: '^[[200~pasted^[[201~'
!
testKeysTheProgramGets
	| sent view |
	view := TerminalView new.
	sent := OrderedCollection new.
	view onSend: [:bytes | sent add: bytes asString].
	{#up -> 0. #left -> 0. #home -> 0. #end -> 0. #delete -> 0. #pageUp -> 0. #backspace -> 0. #return -> 0. #tab -> 0. #tab -> 1. #escape -> 0.
	 $c -> 2. $d -> 2. #space -> 2. $x -> 4. #left -> 4. #right -> 4. #up -> 1. #f1 -> 0. #f5 -> 0. #backspace -> 4}
		do: [:each | view keyDown: (KeyEvent type: #down keyCode: (UIEvent keyCodeFor: each key) key: each key repeat: false modifiers: (Modifiers bits: each value) time: 0)].
	self assert: sent asArray equals: (#('[A' '[D' '[H' '[F' '[3~' '[5~' 127 13 9 '[Z' '') collect: [:each |
		each isString ifTrue: [(String with: Character escape), each] ifFalse: [String with: (Character value: each)]]),
		{String with: (Character value: 3). String with: (Character value: 4). String with: (Character value: 0)},
		(#('x' 'b' 'f' '[1;2A' 'OP' '[15~') collect: [:each | (String with: Character escape), each]),
		{(String with: Character escape with: (Character value: 127))}.
	sent removeAll.
	view keyDown: (KeyEvent type: #down keyCode: 120 key: $x repeat: false modifiers: (Modifiers bits: 4) time: 0).
	view textInput: (TextEvent string: '≈' modifiers: (Modifiers bits: 4) time: 0).
	view textInput: (TextEvent string: 'ab' modifiers: Modifiers none time: 0).
	view textInput: (TextEvent string: (String with: $c with: Character lf with: (Character value: 1)) modifiers: Modifiers none time: 0).
	self assert: sent asArray equals: {(String with: Character escape), 'x'. 'ab'. String with: $c with: Character cr}.
	sent removeAll.
	view parser feed: ((String with: Character escape), '[?1h') asByteArray.
	view keyDown: (KeyEvent type: #down keyCode: (UIEvent keyCodeFor: #up) key: #up repeat: false modifiers: Modifiers none time: 0).
	self assert: sent asArray equals: {(String with: Character escape), 'OA'}
!
testWideCharactersAreSelectedAndCopiedWhole
	| view cell word |
	view := TerminalView new.
	view parser feed: ('ab 日本語', (String with: $e with: (Character value: 16r301)), ' cd') utf8Encoded.
	view select: #(1 5) to: #(1 6).
	self assert: (view selectionColumnsOn: 1) equals: #(4 7).
	self assert: view selectedText equals: '日本'.
	cell := view cellAt: view padding + ((4.5 * view cellExtent x) @ 1).
	self assert: cell equals: #(1 5).
	word := view wordAt: cell.
	view select: word first to: word last.
	self assert: view selectedText equals: '日本語', (String with: $e with: (Character value: 16r301)).
	self assert: view shownLinesNow first equals: 'ab 日本語', (String with: $e with: (Character value: 16r301)), ' cd'
!
testWorldMenuAndOpeners
	self assert: (ToolsMenu labels includes: 'Terminal').
	self assert: (Tools hasOpener: #terminal).
	self assert: (File exists: Terminal repositoryDirectory, '/src/packages.txt').
	self assert: Terminal loginShellCommand last equals: '-l'.
	self assert: (Terminal absolutePath: '/a/b/../c/./d') equals: '/a/c/d'
!
testClosingTheWindowHangsUp
	| pty before process |
	self openOn: #('cat').
	pty := terminal pty.
	self assert: pty isRunning.
	process := terminal ioProcess.
	before := self ptys.
	window close.
	self deny: pty isOpen.
	self assert: self ptys < before.
	self assert: (self waitFor: [process isTerminated]).
	window := nil
! !
