Object subclass: #SourceFiler
	instanceVariableNames: 'sourceDirectory enabled useGitHub gitHubStore'
	classVariableNames: 'BaseCommit BaseDirty Default LastUpdate NeedsRestart'
	package: 'Compiler'!

SourceFiler comment: 'I write what the browser (or the agent) accepts back into the image''s sources (src/<package>/<Class>.st, or <Class>.extension.st for a method in a ''*Package'' category; a package filed in from a directory, as an application is, in that directory), changing only that method, comment or definition chunk (ChunkFile), so unchanged methods stay byte-for-byte the same and a diff shows exactly the edit. Each write reads the file from my store, edits its chunks and gives it back; a file left without chunks is removed.

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

commit: makes the branch <branchPrefix><yyyymmdd-hhmmss>-<slug> at a new commit whose parent is the base commit the change set started from, and opens a pull request into the base branch, titled by the message''s first line, its body the rest and the methods, definitions and comments written; it ends the change set. A failed commit keeps it and signals GitHubError. Nothing ever updates the base branch or a ref outside branchPrefix. A change set survives a snapshot and restart (the token does not).

Updating the running image from GitHub (a SourceUpdate; docs/github.md):
	SourceFiler baseCommit.   "the commit the image''s sources are at: stage 2 records git rev-parse HEAD (baseDirty: src/ had uncommitted changes)"
	SourceFiler default previewUpdateFrom: ''main''.   "what updateFrom: would do, nothing installed"
	SourceFiler default updateFrom: ''main''.   "apply the changes since baseCommit, then baseCommit is main''s head"
	SourceFiler default updateFrom: ''main'' takeTheirs: true.   "also where the image changed the same method"
	SourceFiler needsRestart.   "VM sources changed by updates: they take effect after a rebuild and restart"
The update control command (samaltak-ctl update [--dry-run] [--ref main] [--theirs]) does the same.'!

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
	^gitHubStore ifNil: [gitHubStore := (Smalltalk at: #GitHubSourceStore) new]
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
	"GitHubSourceStore is in Tools: an application's runtime image has none."
	useGitHub == false ifTrue: [^false].
	(Smalltalk at: #GitHubSourceStore ifAbsent: [nil]) isNil ifTrue: [^false].
	useGitHub == true ifTrue: [^true].
	(gitHubStore notNil and: [gitHubStore isStarted]) ifTrue: [^true].
	^self gitHubStore account isConfigured and: [self hasWritableSourceDirectory not]
!
hasStartedGitHubStore
	^gitHubStore notNil and: [gitHubStore isStarted]
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
	"src/<package> in my store; with a local directory, the directory the package was filed in from (an application's) if it was."
	self usesGitHub ifFalse: [(Compiler packageDirectoryOf: aPackageName) ifNotNil: [:directory | ^directory]].
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
!
writeFile: aPath bytes: aByteArray
	"Write a binary file, aPath from the repository's root (fonts/Foo.ttf: beside the store's source directory, as docsDirectory). Answer the path written, nil if I am off."
	| store parent path |
	self isEnabled ifFalse: [^nil].
	store := self existingStore.
	parent := File directoryOf: self root.
	path := parent = '.' ifTrue: [aPath] ifFalse: [parent, '/', aPath].
	store at: path putBytes: aByteArray.
	store noteChange: path.
	^path
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

!SourceFiler methodsFor: 'updating'!
updateFrom: aRef
	"Apply the source changes between my base commit and aRef's head on GitHub to the running image (SourceUpdate); answer the SourceUpdate (summary)."
	^self updateFrom: aRef dryRun: false takeTheirs: false
!
updateFrom: aRef takeTheirs: aBoolean
	^self updateFrom: aRef dryRun: false takeTheirs: aBoolean
!
previewUpdateFrom: aRef
	"What updateFrom: would apply, installing nothing."
	^self updateFrom: aRef dryRun: true takeTheirs: false
!
updateFrom: aRef force: aBoolean
	"updateFrom:, also when image changes depend on VM changes of the same range (SourceUpdate>>vmDependent), which it otherwise refuses."
	^self updateFrom: aRef dryRun: false takeTheirs: false force: aBoolean
!
updateFrom: aRef dryRun: dryRun takeTheirs: takeTheirs
	^self updateFrom: aRef dryRun: dryRun takeTheirs: takeTheirs force: false
!
updateFrom: aRef dryRun: dryRun takeTheirs: takeTheirs force: force
	| update |
	update := ((Smalltalk at: #SourceUpdate) account: self gitHubStore account ref: (aRef ifNil: [self gitHubStore account baseBranch]) base: self class baseCommit)
		filer: self;
		dryRun: dryRun;
		takeTheirs: takeTheirs;
		force: force;
		previousRestart: self class needsRestart;
		run.
	update state == #applied ifTrue: [
		self class baseCommit: update head.
		NeedsRestart := (self class needsRestart, (update needsRestart reject: [:p | self class needsRestart includes: p])) asArray].
	LastUpdate := update.
	^update
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

!SourceFiler class methodsFor: 'updating'!
baseCommit
	"The sha of the commit the image's sources are at: recorded by stage 2, moved by an update; nil if unknown."
	^BaseCommit
!
baseCommit: aShaOrNil
	BaseCommit := aShaOrNil
!
baseDirty
	"Whether src/ had uncommitted changes when stage 2 built the image."
	^BaseDirty == true
!
needsRestart
	"Paths of the VM's sources that updates changed and the running VM does not have."
	^NeedsRestart ifNil: [#()]
!
needsRestart: aCollection
	NeedsRestart := aCollection asArray
!
lastUpdate
	^LastUpdate
!
recordBuildCommit
	"Stage 2: the commit the sources were built from (--base-commit <sha>, --base-dirty; the Makefile passes git rev-parse HEAD)."
	| sha |
	sha := Smalltalk argumentAfter: '--base-commit'.
	BaseCommit := (sha notNil and: [(Smalltalk at: #SourceUpdate) isSha: sha]) ifTrue: [sha] ifFalse: [nil].
	BaseDirty := Smalltalk vm arguments includes: '--base-dirty'.
	NeedsRestart := nil.
	LastUpdate := nil
!
updateCommand: aRemoteRequest
	"The update control command: {cmd: update, ref?, dryRun?, takeTheirs?, force?} answers the SourceUpdate's asDictionary."
	| arguments |
	arguments := aRemoteRequest arguments.
	^[(self default
		updateFrom: (arguments at: 'ref' ifAbsent: [nil])
		dryRun: (arguments at: 'dryRun' ifAbsent: [false]) == true
		takeTheirs: (arguments at: 'takeTheirs' ifAbsent: [false]) == true
		force: (arguments at: 'force' ifAbsent: [false]) == true) asDictionary]
			on: Error do: [:e | (Smalltalk at: #RemoteError) signal: 'update: ', e messageText asString]
! !

!SourceFiler class methodsFor: 'class initialization'!
startUp: resuming
	"The image may have moved: look for the sources again. A GitHub change set not yet committed is kept."
	(Default notNil and: [Default hasStartedGitHubStore])
		ifTrue: [Default sourceDirectory: self findSourceDirectory]
		ifFalse: [Default := nil]
!
initialize
	"SourceUpdate (Tools) registers the update command and the stage 2 step that records the base commit."
	Smalltalk addToStartUpList: self
! !
