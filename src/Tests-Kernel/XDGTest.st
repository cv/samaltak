TestCase subclass: #XDGTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

XDGTest comment: 'Tests for XDG: the base directories are absolute and default below the home directory.'!

!XDGTest methodsFor: 'tests'!
testDirectoriesAreAbsolute
	{XDG configHome. XDG stateHome. XDG cacheHome. XDG dataHome} do: [:each |
		self assert: each first = $/]
!
testPaths
	self assert: (XDG config: 'omarchy/shell.json') equals: XDG configHome, '/omarchy/shell.json'.
	self assert: (XDG state: 'x') equals: XDG stateHome, '/x'
!
testRelativeVariablesAreIgnored
	self assert: (XDG variable: 'SAMALTAK_TEST_UNSET_VARIABLE' default: '/.config') equals: XDG home, '/.config'
! !
