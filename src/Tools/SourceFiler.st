Object subclass: #SourceFiler
	instanceVariableNames: 'sourceDirectory enabled useGitHub gitHubStore'
	classVariableNames: 'Default'
	package: 'Tools'!

SourceFiler comment: 'I write what the browser accepts and the agent writes back into the image''s sources (src/<package>/<Class>.st, or <Class>.extension.st for a method in a ''*Package'' category), changing only that method, comment or definition chunk (ChunkFile), so unchanged methods stay byte-for-byte the same and a diff shows exactly the edit. Each write reads the file from my store, edits its chunks and gives it back; a file left without chunks is removed.

My store is the local source directory (a SourceDirectoryStore): --source-dir <dir>, else the first of <image dir>/../../src, <image dir>/../src, <image dir>/src, <current dir>/src that holds packages.txt. Or it is GitHub (a GitHubSourceStore: GitHubAccount default''s repository, read at the base branch''s head and edited in memory until committed) when that account is configured and there is no writable source directory (UEFI: its volumes are read-only), or always after useGitHub: true (false: never). --no-source-write turns me off; so does having no store (the browser then only changes the image).

	SourceFiler default writeMethod: (Integer >> #gcd:).   "the path written, nil if nothing changed or I am off"
	SourceFiler default removeMethod: #gcd: class: Integer category: ''arithmetic''.
	SourceFiler default writeDefinition: aString of: aClass; writeCommentOf: aClass; removeClass: aClass.
	SourceFiler default pendingChanges.   "GitHub: the paths changed and not yet committed"
	SourceFiler default commit: ''Kernel: gcd: handles 0''.   "GitHub: a GitHubPullRequest (number, url, branch, commitSha)"
	SourceFiler default commit: ''...'' pullRequest: false.   "the commit on its branch only"
	SourceFiler default discardChanges
	SourceFiler default docs.   "the documents in docs/ beside src/: #(''agent.md'' ...)"
	SourceFiler default doc: ''agent''.   "docs/agent.md''s text, nil if there is none"

commit: makes the branch <branchPrefix><yyyymmdd-hhmmss>-<slug> at a new commit whose parent is the base commit the change set started from, and opens a pull request into the base branch, titled by the message''s first line, its body the rest and the methods, definitions and comments written; it ends the change set. A failed commit keeps it and signals GitHubError. Nothing ever updates the base branch or a ref outside branchPrefix. A change set survives a snapshot and restart (the token does not).'!

!SourceFiler methodsFor: 'accessing'!
sourceDirectory
	^sourceDirectory
!
sourceDirectory: aPathOrNil
	sourceDirectory := aPathOrNil
!
enabled: aBoolean
	enabled := aBoolean
!
useGitHub: aBooleanOrNil
	"true: always the GitHub store; false: never; nil: when GitHub is configured and there is no writable source directory."
	useGitHub := aBooleanOrNil
!
gitHubStore
	^gitHubStore ifNil: [gitHubStore := GitHubSourceStore new]
!
gitHubStore: aGitHubSourceStore
	"Use aGitHubSourceStore (on an account other than GitHubAccount default: tests) when I use GitHub."
	gitHubStore := aGitHubSourceStore
!
isEnabled
	enabled == false ifTrue: [^false].
	(Smalltalk vm arguments includes: '--no-source-write') ifTrue: [^false].
	^self store notNil
!
usesGitHub
	useGitHub == false ifTrue: [^false].
	useGitHub == true ifTrue: [^true].
	(gitHubStore notNil and: [gitHubStore isStarted]) ifTrue: [^true].
	^self gitHubStore account isConfigured and: [self hasWritableSourceDirectory not]
!
hasWritableSourceDirectory
	"A source directory not on a mounted (read-only) volume."
	^sourceDirectory notNil and: [(File mountTableFor: sourceDirectory) isNil]
!
store
	"Where I read and write sources (see my comment), nil if nowhere."
	self usesGitHub ifTrue: [^self gitHubStore].
	^sourceDirectory isNil ifTrue: [nil] ifFalse: [SourceDirectoryStore on: sourceDirectory]
!
root
	"The store's source directory (the one holding packages.txt)."
	^self store ifNil: [sourceDirectory] ifNotNil: [:store | store root]
!
packageDirectory: aPackageName
	^self root, '/', aPackageName
!
pathForClass: aClass
	^(self packageDirectory: aClass theNonMetaClass packageName), '/', aClass theNonMetaClass name, '.st'
!
pathForMethod: aCompiledMethod
	"The file a method lives in: its class's file, or the extension file of the package its *category names."
	^self pathFor: aCompiledMethod methodClass category: aCompiledMethod category
!
pathFor: aBehavior category: aCategoryOrNil
	(aCategoryOrNil notNil and: [aCategoryOrNil beginsWith: '*']) ifTrue: [
		^(self packageDirectory: (self packageOfExtensionCategory: aCategoryOrNil)), '/', aBehavior theNonMetaClass name, '.extension.st'].
	^self pathForClass: aBehavior
!
packageOfExtensionCategory: aString
	"'*System-Profiling' names the package System-Profiling (a longer name like '*System-Profiling-private' names the longest package it starts with)."
	| name best |
	name := aString allButFirst.
	best := nil.
	Smalltalk packages do: [:p |
		((name = p name or: [name beginsWith: p name, '-']) and: [best isNil or: [p name size > best size]])
			ifTrue: [best := p name]].
	^best ifNil: [name]
!
labelOf: aBehavior
	^aBehavior theNonMetaClass name, (aBehavior isMeta ifTrue: [' class'] ifFalse: [''])
!
docsDirectory
	"The docs/ beside the store's source directory, or nil without a store."
	| parent |
	self store isNil ifTrue: [^nil].
	parent := File directoryOf: self root.
	^parent = '.' ifTrue: ['docs'] ifFalse: [parent, '/docs']
! !

!SourceFiler methodsFor: 'files'!
edit: aPath note: aString with: aBlock
	"Edit aPath's chunks: aBlock gets its ChunkFile (empty if there is no file) and answers whether it changed it. Give the file back to the store (remove it when no chunk is left), note aString as the change, and answer aPath; nil if nothing changed."
	| store file |
	store := self store.
	file := ChunkFile on: ((store textAt: aPath) ifNil: ['']).
	(aBlock value: file) ifFalse: [^nil].
	file chunkCount = 0
		ifTrue: [store removeFileAt: aPath]
		ifFalse: [store at: aPath putText: file text].
	store noteChange: aString.
	^aPath
!
docs
	"The names of the documents in docs/ (doc: reads one)."
	^self store ifNil: [#()] ifNotNil: [:store | store fileNamesIn: self docsDirectory]
!
doc: aName
	"The text of the document aName in docs/ ('agent' or 'agent.md'), or nil."
	| name |
	name := (aName includes: $.) ifTrue: [aName] ifFalse: [aName, '.md'].
	^self store ifNotNil: [:store | store textAt: self docsDirectory, '/', name]
! !

!SourceFiler methodsFor: 'writing'!
writeMethod: aCompiledMethod
	"Write the method's source into its file. Answer the path if the file changed, nil if it was already up to date or I am off."
	^self writeSource: aCompiledMethod source
		selector: aCompiledMethod selector
		class: aCompiledMethod methodClass
		category: (aCompiledMethod category ifNil: ['as yet unclassified'])
!
writeSource: aString selector: aSelector class: aBehavior category: aCategory
	"Write aString as the method aSelector of aBehavior in aCategory into its file (as writeMethod:)."
	self isEnabled ifFalse: [^nil].
	^self edit: (self pathFor: aBehavior category: aCategory) note: (self labelOf: aBehavior), '>>', aSelector with: [:file |
		file putMethod: aString
			selector: aSelector
			className: aBehavior theNonMetaClass name
			meta: aBehavior isMeta
			category: aCategory]
!
removeMethod: aSelector class: aBehavior category: aCategory
	"Remove a method from the file it lived in (when the browser moves it to another file, or it is removed)."
	self isEnabled ifFalse: [^nil].
	^self edit: (self pathFor: aBehavior category: aCategory) note: (self labelOf: aBehavior), '>>', aSelector, ' (removed)' with: [:file |
		| entry |
		entry := file methodEntryFor: aSelector className: aBehavior theNonMetaClass name meta: aBehavior isMeta.
		entry notNil ifTrue: [file removeMethodEntry: entry].
		entry notNil]
!
writeDefinition: aString of: aClass
	self isEnabled ifFalse: [^nil].
	^self edit: (self pathForClass: aClass) note: aClass name, ' (definition)' with: [:file |
		file putDefinition: aString className: aClass name]
!
writeCommentOf: aClass
	self isEnabled ifFalse: [^nil].
	^self edit: (self pathForClass: aClass) note: aClass name, ' (comment)' with: [:file |
		file putComment: (aClass comment ifNil: ['']) className: aClass name]
!
removeClass: aClass
	"Remove the class's file (its extension files stay). Answer the path, nil if there was none or I am off."
	| path store |
	self isEnabled ifFalse: [^nil].
	path := self pathForClass: aClass.
	store := self store.
	(store textAt: path) isNil ifTrue: [^nil].
	store removeFileAt: path.
	store noteChange: aClass name, ' (removed)'.
	^path
!
definitionInFileOf: aClass
	"The class definition chunk as written in its file, or nil."
	| text file k |
	self store isNil ifTrue: [^nil].
	text := self store textAt: (self pathForClass: aClass).
	text isNil ifTrue: [^nil].
	file := ChunkFile on: text.
	k := file definitionChunkFor: aClass name.
	^k isNil ifTrue: [nil] ifFalse: [file chunkBody: k]
! !

!SourceFiler methodsFor: 'changes'!
pendingChanges
	"The paths changed and not committed (GitHub; a local directory has none: git keeps them)."
	^self store ifNil: [#()] ifNotNil: [:store | store pendingChanges]
!
discardChanges
	"Forget the changes not committed (GitHub)."
	^self existingStore discardChanges
!
commit: aString
	"Commit the changes on a new branch and open a pull request (GitHub); answer a GitHubPullRequest (see my comment)."
	^self commit: aString pullRequest: true
!
commit: aString pullRequest: aBoolean
	^self existingStore commit: aString pullRequest: aBoolean
!
existingStore
	^self store ifNil: [self error: 'No source store: no source directory and no GitHub account']
! !

!SourceFiler methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a SourceFiler ('.
	self store
		ifNil: [aStream nextPutAll: 'off']
		ifNotNil: [:store | store printOn: aStream].
	aStream nextPut: $)
! !

!SourceFiler class methodsFor: 'instance creation'!
default
	^Default ifNil: [Default := self new sourceDirectory: self findSourceDirectory; yourself]
!
default: aSourceFilerOrNil
	Default := aSourceFilerOrNil
!
reset
	Default := nil
!
findSourceDirectory
	| explicit image dir candidates |
	explicit := Smalltalk argumentAfter: '--source-dir'.
	explicit isNil ifFalse: [^explicit].
	candidates := OrderedCollection new.
	image := Smalltalk vm imagePath.
	image isNil ifFalse: [
		dir := File directoryOf: image.
		candidates add: dir, '/../../src'; add: dir, '/../src'; add: dir, '/src'].
	File primCwd ifNotNil: [:cwd | candidates add: cwd, '/src'].
	^candidates detect: [:each | File exists: each, '/packages.txt'] ifNone: [nil]
! !

!SourceFiler class methodsFor: 'class initialization'!
startUp: resuming
	"The image may have moved: look for the sources again. A GitHub change set not yet committed is kept."
	(Default notNil and: [Default gitHubStore isStarted])
		ifTrue: [Default sourceDirectory: self findSourceDirectory]
		ifFalse: [Default := nil]
!
initialize
	Smalltalk addToStartUpList: self
! !
