Object subclass: #XDG
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Files'!

XDG comment: 'I answer the XDG base directories (specifications.freedesktop.org/basedir-spec): where a program on Linux finds its configuration, state, cache and data, each from its environment variable, else its default below the home directory. On macOS the same defaults apply.

	XDG configHome         "~/.config"
	XDG stateHome          "~/.local/state"
	XDG config: ''omarchy/shell.json''   "a path in configHome"'!

!XDG class methodsFor: 'directories'!
home
	^(Smalltalk vm getenv: 'HOME') ifNil: ['/']
!
configHome
	^self variable: 'XDG_CONFIG_HOME' default: '/.config'
!
stateHome
	^self variable: 'XDG_STATE_HOME' default: '/.local/state'
!
cacheHome
	^self variable: 'XDG_CACHE_HOME' default: '/.cache'
!
dataHome
	^self variable: 'XDG_DATA_HOME' default: '/.local/share'
!
runtimeDirectory
	"XDG_RUNTIME_DIR, or nil."
	^Smalltalk vm getenv: 'XDG_RUNTIME_DIR'
!
variable: aName default: aSuffix
	"The directory in the environment variable aName if it is an absolute path (the specification ignores relative ones), else the home directory with aSuffix."
	| value |
	value := Smalltalk vm getenv: aName.
	(value notNil and: [value notEmpty and: [value first = $/]]) ifTrue: [^value].
	^self home, aSuffix
! !

!XDG class methodsFor: 'paths'!
config: aRelativePath
	^self configHome, '/', aRelativePath
!
state: aRelativePath
	^self stateHome, '/', aRelativePath
!
cache: aRelativePath
	^self cacheHome, '/', aRelativePath
!
data: aRelativePath
	^self dataHome, '/', aRelativePath
! !
