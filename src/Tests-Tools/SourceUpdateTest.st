TestCase subclass: #SourceUpdateTest
	instanceVariableNames: 'server account store filer base head fixture savedBase savedRestart'
	classVariableNames: ''
	package: 'Tests-Tools'!

SourceUpdateTest comment: 'I test SourceUpdate (SourceFiler default updateFrom: ''main''): a fake GitHub (GitHubTestServer, Tests-Net) holds two commits, the base (the fixture classes setUp files into the image) and the head: methods added, changed and removed, an instance variable added to a class with a live instance, a new comment, a new class in a new package with a class-side initialize, a removed class, an extension file, a VM source and host files (reported, not applied). Then: conflicts with the image and with the pending change set (kept, or overwritten with takeTheirs), a head that does not compile (nothing applied), a dry run, up to date, the base commit and the update control command.'!

!SourceUpdateTest methodsFor: 'running'!
setUp
	savedBase := SourceFiler baseCommit.
	savedRestart := SourceFiler needsRestart.
	self removeFixtures.
	server := GitHubTestServer token: self token files: self baseFiles.
	account := GitHubAccount new.
	account configure: (Dictionary new
		at: 'repository' put: 'test/repo';
		at: 'apiUrl' put: server url;
		at: 'token' put: self token;
		yourself).
	store := GitHubSourceStore on: account.
	filer := SourceFiler new useGitHub: true; gitHubStore: store; yourself.
	Compiler fileInString: self baseFixture; fileInString: self oldFixture.
	fixture := (self classNamed: 'SourceUpdateFixture') withA: 3.
	base := server refs at: 'main'.
	head := server commit: self headChanges message: 'Next'
!
tearDown
	self removeFixtures.
	SourceFiler baseCommit: savedBase; needsRestart: savedRestart.
	store close.
	server stop.
	account clear
!
removeFixtures
	#(#SourceUpdateNewFixture #SourceUpdateFixture #SourceUpdateOldFixture) do: [:name |
		(Smalltalk at: name ifAbsent: [nil]) ifNotNil: [:class | class removeFromSystem]].
	Smalltalk removePackageNamed: 'Tests-SourceUpdate'
! !

!SourceUpdateTest methodsFor: 'fixtures'!
token
	^'ghp_UpdateTestToken0123456789' copy
!
classNamed: aString
	^Smalltalk at: aString asSymbol ifAbsent: [nil]
!
fixturePath
	^'src/Tests-Tools/SourceUpdateFixture.st'
!
baseFiles
	^Dictionary new
		at: self fixturePath put: self baseFixture;
		at: 'src/Tests-Tools/SourceUpdateOldFixture.st' put: self oldFixture;
		at: 'src/packages.txt' put: '# packages
Tests-Net 0
Tests-Tools 5
';
		at: 'src/VM-Core/Posix.st' put: '"one"!!
';
		at: 'vm/platform/posix.c' put: 'int one;';
		at: 'Makefile' put: 'all:';
		at: 'docs/github.md' put: '# GitHub';
		yourself
!
headChanges
	^Dictionary new
		at: self fixturePath put: self headFixture;
		at: 'src/Tests-Net/SourceUpdateFixture.extension.st' put: self extensionText;
		at: 'src/Tests-Tools/SourceUpdateOldFixture.st' put: nil;
		at: 'src/Tests-SourceUpdate/SourceUpdateNewFixture.st' put: self newFixture;
		at: 'src/packages.txt' put: '# packages
Tests-Net 0
Tests-Tools 5
Tests-SourceUpdate 5
';
		at: 'src/VM-Core/Posix.st' put: '"two"!!
';
		at: 'vm/platform/posix.c' put: 'int two;';
		at: 'Makefile' put: 'all: vm';
		at: 'docs/github.md' put: '# GitHub, updated';
		yourself
!
update
	^self updateWith: [:u | u]
!
updateWith: aBlock
	^(aBlock value: ((SourceUpdate account: account ref: 'main' base: base) filer: filer; yourself)) run
!
baseFixture
	"The fixture class as the base commit has it (and the image, after setUp)."
	^'Object subclass: #SourceUpdateFixture
	instanceVariableNames: ''a''
	classVariableNames: ''''
	package: ''Tests-Tools''!!

SourceUpdateFixture comment: ''Old comment.''!!

!!SourceUpdateFixture methodsFor: ''accessing''!!
a
	^a
!!
a: anObject
	a := anObject
!!
changed
	^1
!!
removed
	^#removed
!!
local
	^#base
!! !!

!!SourceUpdateFixture class methodsFor: ''instance creation''!!
withA: anObject
	^self new a: anObject
!! !!
'
!
headFixture
	"The fixture class at the head: an instance variable b, b and sum added, changed and local changed, removed removed, a new comment."
	^'Object subclass: #SourceUpdateFixture
	instanceVariableNames: ''a b''
	classVariableNames: ''''
	package: ''Tests-Tools''!!

SourceUpdateFixture comment: ''New comment.''!!

!!SourceUpdateFixture methodsFor: ''accessing''!!
a
	^a
!!
a: anObject
	a := anObject
!!
b
	^b
!!
changed
	^2
!!
local
	^#theirs
!!
sum
	^a + (b ifNil: [0])
!! !!

!!SourceUpdateFixture class methodsFor: ''instance creation''!!
withA: anObject
	^self new a: anObject
!! !!
'
!
extensionText
	"An extension file the head adds."
	^'!!SourceUpdateFixture methodsFor: ''*Tests-Net''!!
extended
	^#extended
!! !!
'
!
oldFixture
	"A class the head removes."
	^'Object subclass: #SourceUpdateOldFixture
	instanceVariableNames: ''''
	classVariableNames: ''''
	package: ''Tests-Tools''!!

!!SourceUpdateOldFixture methodsFor: ''accessing''!!
old
	^#old
!! !!
'
!
newFixture
	"A class the head adds, in a new package, with a class variable its class-side initialize sets."
	^'SourceUpdateFixture subclass: #SourceUpdateNewFixture
	instanceVariableNames: ''c''
	classVariableNames: ''Initialized''
	package: ''Tests-SourceUpdate''!!

SourceUpdateNewFixture comment: ''I am new.''!!

!!SourceUpdateNewFixture methodsFor: ''accessing''!!
total
	^self sum + 1
!! !!

!!SourceUpdateNewFixture class methodsFor: ''class initialization''!!
initialize
	Initialized := true
!!
initialized
	^Initialized
!! !!
'
! !

!SourceUpdateTest methodsFor: 'tests'!
testUpdateAppliesTheChanges
	| update class newClass |
	update := self update.
	self assert: update state equals: #applied.
	self assert: update failures isEmpty.
	self assert: update conflicts isEmpty.
	self assert: update head equals: head.
	class := self classNamed: 'SourceUpdateFixture'.
	self assert: class instVarNames asArray equals: #('a' 'b').
	self assert: fixture class == class.
	self assert: fixture a equals: 3.
	self assert: fixture b isNil.
	self assert: fixture sum equals: 3.
	self assert: fixture changed equals: 2.
	self assert: fixture local equals: #theirs.
	self deny: (class includesSelector: #removed).
	self assert: fixture extended equals: #extended.
	self assert: (class >> #extended) category equals: '*Tests-Net'.
	self assert: (class >> #sum) category equals: 'accessing'.
	self assert: class comment equals: 'New comment.'.
	self assert: (class withA: 4) sum equals: 4.
	self assert: (self classNamed: 'SourceUpdateOldFixture') isNil.
	newClass := self classNamed: 'SourceUpdateNewFixture'.
	self assert: newClass superclass == class.
	self assert: newClass packageName equals: 'Tests-SourceUpdate'.
	self assert: newClass comment equals: 'I am new.'.
	self assert: newClass initialized equals: true.
	self assert: ((newClass withA: 1) total) equals: 2.
	self assert: (Smalltalk packages anySatisfy: [:p | p name = 'Tests-SourceUpdate' and: [p layer = 5]]).
	self assert: update needsRestart equals: #('src/VM-Core/Posix.st' 'vm/platform/posix.c').
	self assert: update hostSide equals: #('Makefile' 'docs/github.md').
	self assert: (update summary beginsWith: 'applied 9 methods in 3 classes, 1 new class, 1 class definition changed, 1 class removed, 2 comments, 1 new package (Tests-SourceUpdate)').
	self assert: (update summary includesSubstring: '1 commit)').
	self assert: (update summary includesSubstring: 'needs restart for: src/VM-Core/Posix.st, vm/platform/posix.c').
	self assert: (update summary includesSubstring: 'host side, not in the image: Makefile, docs/github.md')
!
testConflictKeepsTheImagesMethod
	| update class |
	class := self classNamed: 'SourceUpdateFixture'.
	class compile: 'local
	^#mine' classified: 'accessing'.
	update := self update.
	self assert: update state equals: #applied.
	self assert: (update conflicts collect: [:c | c label]) asArray equals: #('SourceUpdateFixture>>local').
	self assert: update conflicts first reason equals: 'changed in this image'.
	self assert: fixture local equals: #mine.
	self assert: fixture changed equals: 2.
	self assert: fixture sum equals: 3.
	self assert: (update summary includesSubstring: 'conflicts, kept as this image has them (takeTheirs: true overwrites): SourceUpdateFixture>>local (changed in this image)')
!
testTakeTheirs
	| update class |
	class := self classNamed: 'SourceUpdateFixture'.
	class compile: 'local
	^#mine' classified: 'accessing'.
	update := self updateWith: [:u | u takeTheirs: true].
	self assert: update state equals: #applied.
	self assert: update conflicts isEmpty.
	self assert: fixture local equals: #theirs
!
testPendingChangeConflicts
	| update class |
	class := self classNamed: 'SourceUpdateFixture'.
	filer writeSource: 'removed
	^#pending' selector: #removed class: class category: 'accessing'.
	self assert: filer pendingChanges equals: (Array with: self fixturePath).
	update := self update.
	self assert: update state equals: #applied.
	self assert: (update conflicts collect: [:c | c label]) asArray equals: #('SourceUpdateFixture>>removed').
	self assert: update conflicts first reason equals: 'changed in the pending change set'.
	self assert: fixture removed equals: #removed.
	self assert: fixture changed equals: 2
!
testAlreadyAppliedIsNoConflict
	| update class |
	class := self classNamed: 'SourceUpdateFixture'.
	class compile: 'local
	^#theirs' classified: 'accessing'.
	update := self update.
	self assert: update conflicts isEmpty.
	self assert: ((update already collect: [:c | c label]) includes: 'SourceUpdateFixture>>local').
	self assert: (update summary includesSubstring: '1 change already in the image')
!
testCompileFailureAppliesNothing
	| update class |
	server commit: (Dictionary new
		at: self fixturePath put: ((self headFixture
			copyReplaceAll: '^a + (b ifNil: [0])' with: '^a + zork')
			copyReplaceAll: '^2' with: '^2 +');
		yourself) message: 'Broken'.
	update := self update.
	self assert: update state equals: #failed.
	self assert: update failures size equals: 2.
	self assert: (update failures anySatisfy: [:f | (f beginsWith: 'SourceUpdateFixture>>sum: ') and: [f includesSubstring: 'zork']]).
	self assert: (update failures anySatisfy: [:f | f beginsWith: 'SourceUpdateFixture>>changed: ']).
	self assert: (update summary beginsWith: 'nothing applied: ').
	class := self classNamed: 'SourceUpdateFixture'.
	self assert: class instVarNames asArray equals: #('a').
	self assert: fixture changed equals: 1.
	self assert: fixture removed equals: #removed.
	self assert: class comment equals: 'Old comment.'.
	self assert: (self classNamed: 'SourceUpdateNewFixture') isNil.
	self assert: (self classNamed: 'SourceUpdateOldFixture') notNil.
	self deny: (Smalltalk packages anySatisfy: [:p | p name = 'Tests-SourceUpdate'])
!
testKeptMethodsMustCompileOnTheNewShape
	| update |
	"The head drops the instance variable a, but a: (unchanged) still assigns it."
	server commit: (Dictionary new
		at: self fixturePath put: ((self headFixture
			copyReplaceAll: 'instanceVariableNames: ''a b''' with: 'instanceVariableNames: ''b''')
			copyReplaceAll: '^a + (b ifNil: [0])' with: '^b');
		yourself) message: 'No a'.
	update := self update.
	self assert: update state equals: #failed.
	self assert: (update failures anySatisfy: [:f | f beginsWith: 'SourceUpdateFixture>>a']).
	self assert: (self classNamed: 'SourceUpdateFixture') instVarNames asArray equals: #('a').
	self assert: fixture a equals: 3
!
testDryRunChangesNothing
	| update class |
	update := self updateWith: [:u | u dryRun: true].
	self assert: update state equals: #preview.
	self assert: (update summary beginsWith: 'would apply 9 methods').
	self assert: update applied notEmpty.
	class := self classNamed: 'SourceUpdateFixture'.
	self assert: class instVarNames asArray equals: #('a').
	self assert: fixture changed equals: 1.
	self assert: (self classNamed: 'SourceUpdateNewFixture') isNil.
	self assert: (self classNamed: 'SourceUpdateOldFixture') notNil
!
testUpToDate
	| update |
	base := head.
	update := self update.
	self assert: update state equals: #upToDate.
	self assert: (update summary beginsWith: 'up to date at ', head).
	self assert: fixture changed equals: 1
!
testUnknownBaseCommit
	| update |
	base := nil.
	update := self update.
	self assert: update state equals: #failed.
	self assert: (update summary includesSubstring: 'SourceFiler baseCommit is nil')
!
testSourceFilerMovesItsBaseCommit
	| update |
	SourceFiler baseCommit: base; needsRestart: #().
	update := filer updateFrom: 'main'.
	self assert: update state equals: #applied.
	self assert: SourceFiler baseCommit equals: head.
	self assert: SourceFiler needsRestart equals: #('src/VM-Core/Posix.st' 'vm/platform/posix.c').
	self assert: SourceFiler lastUpdate == update.
	update := filer updateFrom: 'main'.
	self assert: update state equals: #upToDate.
	self assert: (update summary includesSubstring: 'needs restart for: src/VM-Core/Posix.st')
!
testUpdateCommand
	| saved response |
	saved := SourceFiler default.
	SourceFiler baseCommit: base.
	SourceFiler default: filer.
	[response := RemoteControl dispatch: (RemoteRequest on: (Dictionary new
		at: 'cmd' put: 'update';
		at: 'ref' put: 'main';
		at: 'dryRun' put: true;
		yourself))] ensure: [SourceFiler default: saved].
	self assert: (response at: 'state') equals: 'preview'.
	self assert: ((response at: 'summary') beginsWith: 'would apply').
	self assert: (response at: 'head') equals: head.
	self assert: (response at: 'needsRestart') asArray equals: #('src/VM-Core/Posix.st' 'vm/platform/posix.c').
	self assert: SourceFiler baseCommit equals: base
!
testTheImageKnowsItsCommit
	"make image passes git rev-parse HEAD to stage 2."
	self assert: (SourceUpdate isSha: savedBase)
! !
