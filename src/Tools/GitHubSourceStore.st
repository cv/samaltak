Object subclass: #GitHubSourceStore
	instanceVariableNames: 'account client baseCommit baseTree entries truncated originals texts notes'
	classVariableNames: ''
	package: 'Tools'!

GitHubSourceStore comment: 'I am SourceFiler''s store for a GitHub repository, a GitHubAccount''s (GitHubAccount default unless given): the sources are its src/; paths are repository paths (src/Tools/SourceFiler.st). I read through the git data API and keep the edits in memory until they are committed (GitHubClient), so I need no files, processes or git: SourceFiler uses me on UEFI.

A change set starts with my first read: I record the base branch''s head commit (baseCommit) and list its tree once (git/trees/<tree>?recursive=1); I read each file once from its blob (git/blobs/<sha>, base64, any size). Writes and removals stay in memory; pendingChanges are the paths whose text differs from the base''s. commit:pullRequest: posts a blob (base64) for each changed file, a tree on the base''s tree (a removed file with sha null), a commit with the message whose parent is baseCommit, the branch refs/heads/<branchPrefix><yyyymmdd-hhmmss>-<slug> (UTC; the slug from the message''s first line) and, if asked, a pull request into the base branch, titled by the first line, its body the rest and the changes noted (noteChange:). It answers a GitHubPullRequest and ends the change set. A failure signals GitHubError and keeps the change set (a branch already made stays: committing again makes another). discardChanges ends it unsent. I never update the base branch, nor any ref outside branchPrefix (GitHubClient refuses).'!

!GitHubSourceStore methodsFor: 'initialization'!
setAccount: aGitHubAccountOrNil
	account := aGitHubAccountOrNil
! !

!GitHubSourceStore methodsFor: 'accessing'!
account
	^account ifNil: [GitHubAccount default]
!
client
	(client isNil or: [client account ~~ self account]) ifTrue: [
		client isNil ifFalse: [client close].
		client := GitHubClient on: self account].
	^client
!
root
	^'src'
!
baseCommit
	"The sha of the commit the change set started from, nil without one."
	^baseCommit
!
isStarted
	^baseCommit notNil
!
notes
	"What changed (noteChange:), in order."
	^notes ifNil: [#()] ifNotNil: [notes asArray]
! !

!GitHubSourceStore methodsFor: 'files'!
textAt: aPath
	"aPath's text in the change set (as the base has it, unless changed); nil if there is no such file."
	self isStarted ifFalse: [self start].
	(texts includesKey: aPath) ifTrue: [^texts at: aPath].
	^originals at: aPath ifAbsent: [originals at: aPath put: (self readBlobAt: aPath)]
!
at: aPath putText: aString
	self textAt: aPath.
	texts at: aPath put: aString
!
removeFileAt: aPath
	self textAt: aPath.
	texts at: aPath put: nil
!
noteChange: aString
	notes isNil ifTrue: [notes := OrderedCollection new].
	(notes includes: aString) ifFalse: [notes add: aString]
!
fileNamesIn: aPath
	"The names of the files directly in the directory aPath (a repository path), sorted."
	| prefix |
	self isStarted ifFalse: [self start].
	prefix := aPath, '/'.
	^((entries keys select: [:p | (p beginsWith: prefix) and: [(p indexOf: $/ startingAt: prefix size + 1) = 0]])
		collect: [:p | p copyFrom: prefix size + 1 to: p size]) asSortedCollection asArray
! !

!GitHubSourceStore methodsFor: 'changes'!
pendingChanges
	"The paths changed and not committed, sorted."
	texts isNil ifTrue: [^#()].
	^(texts keys select: [:p | (texts at: p) ~= (originals at: p ifAbsent: [nil])]) asSortedCollection asArray
!
hasChanges
	^self pendingChanges notEmpty
!
discardChanges
	"End the change set unsent; the next read starts another at the base branch's head."
	baseCommit := baseTree := entries := truncated := originals := texts := notes := nil
!
commit: aString pullRequest: aBoolean
	"Commit the change set on a new branch, with a pull request into the base branch if aBoolean; answer a GitHubPullRequest (see my comment)."
	| paths tree commit branch pr result |
	paths := self pendingChanges.
	paths isEmpty ifTrue: [^GitHubError refuse: 'No changes to commit'].
	(aString isString and: [aString trimBoth notEmpty]) ifFalse: [^GitHubError refuse: 'The commit message is empty'].
	tree := self client post: (self client repositoryPath: 'git/trees') json: (Dictionary new
		at: 'base_tree' put: baseTree;
		at: 'tree' put: (paths collect: [:p | self treeEntryFor: p]);
		yourself).
	commit := self client post: (self client repositoryPath: 'git/commits') json: (Dictionary new
		at: 'message' put: aString;
		at: 'tree' put: (tree at: 'sha');
		at: 'parents' put: (Array with: baseCommit);
		yourself).
	branch := self branchNameFor: aString.
	self client post: (self client repositoryPath: 'git/refs') json: (Dictionary new
		at: 'ref' put: 'refs/heads/', branch;
		at: 'sha' put: (commit at: 'sha');
		yourself).
	pr := GitHubPullRequest new setBranch: branch commitSha: (commit at: 'sha').
	aBoolean ifTrue: [
		result := self client post: (self client repositoryPath: 'pulls') json: (Dictionary new
			at: 'title' put: (self class titleOf: aString);
			at: 'body' put: (self pullRequestBodyFor: aString);
			at: 'head' put: branch;
			at: 'base' put: self account baseBranch;
			yourself).
		pr setNumber: (result at: 'number') url: (result at: 'html_url' ifAbsent: [nil])].
	self discardChanges.
	^pr
!
close
	client isNil ifFalse: [client close]
! !

!GitHubSourceStore methodsFor: 'private'!
start
	"Begin a change set at the base branch's head: its commit, its tree's blobs (path -> {mode. sha})."
	| ref commit sha tree listing blobs |
	ref := self client get: (self client repositoryPath: 'git/ref/heads/', self account baseBranch).
	sha := (ref at: 'object') at: 'sha'.
	commit := self client get: (self client repositoryPath: 'git/commits/', sha).
	tree := (commit at: 'tree') at: 'sha'.
	listing := self client get: (self client repositoryPath: 'git/trees/', tree, '?recursive=1').
	blobs := Dictionary new.
	(listing at: 'tree') do: [:e |
		(e at: 'type') = 'blob' ifTrue: [blobs at: (e at: 'path') put: (Array with: (e at: 'mode') with: (e at: 'sha'))]].
	truncated := (listing at: 'truncated' ifAbsent: [false]) == true.
	entries := blobs.
	baseTree := tree.
	originals := Dictionary new.
	texts := Dictionary new.
	notes := OrderedCollection new.
	baseCommit := sha
!
readBlobAt: aPath
	| entry blob content |
	entry := entries at: aPath ifAbsent: [nil].
	entry isNil ifTrue: [
		truncated ifTrue: [^GitHubError refuse: 'The base tree is too large to list in one request: ', aPath, ' is not in the listing'].
		^nil].
	blob := self client get: (self client repositoryPath: 'git/blobs/', entry last).
	content := blob at: 'content'.
	^(blob at: 'encoding' ifAbsent: ['base64']) = 'base64'
		ifTrue: [(Base64 decode: content) utf8Decoded]
		ifFalse: [content]
!
treeEntryFor: aPath
	"The git/trees entry of a changed path: a new blob of its text, or sha nil (removed)."
	| text entry |
	text := texts at: aPath.
	entry := Dictionary new.
	entry
		at: 'path' put: aPath;
		at: 'mode' put: ((entries at: aPath ifAbsent: [nil]) ifNil: ['100644'] ifNotNil: [:e | e first]);
		at: 'type' put: 'blob';
		at: 'sha' put: (text isNil ifTrue: [nil] ifFalse: [
			(self client post: (self client repositoryPath: 'git/blobs') json: (Dictionary new
				at: 'content' put: (Base64 encode: text utf8Encoded);
				at: 'encoding' put: 'base64';
				yourself)) at: 'sha']).
	^entry
!
branchNameFor: aMessage
	"branchPrefix, the UTC time as yyyymmdd-hhmmss, and a slug of the message's first line."
	| us date secs slug |
	us := Time utcMicroseconds.
	date := Date fromDays: us // 86400000000.
	secs := us // 1000000 \\ 86400.
	slug := self class slugOf: (self class titleOf: aMessage).
	^String new: 64 streamContents: [:s |
		s nextPutAll: self account branchPrefix.
		s nextPutAll: (date year printString padLeftTo: 4 with: $0).
		s nextPutAll: (date monthIndex printString padLeftTo: 2 with: $0).
		s nextPutAll: (date dayOfMonth printString padLeftTo: 2 with: $0).
		s nextPut: $-.
		s nextPutAll: ((secs // 3600) printString padLeftTo: 2 with: $0).
		s nextPutAll: ((secs // 60 \\ 60) printString padLeftTo: 2 with: $0).
		s nextPutAll: ((secs \\ 60) printString padLeftTo: 2 with: $0).
		slug isEmpty ifFalse: [s nextPut: $-; nextPutAll: slug]]
!
pullRequestBodyFor: aMessage
	"The message after its first line, then what changed."
	| rest lf |
	lf := String with: Character lf.
	rest := (aMessage copyAfter: Character lf) trimBoth.
	^String new: 200 streamContents: [:s |
		rest isEmpty ifFalse: [s nextPutAll: rest; nextPutAll: lf; nextPutAll: lf].
		s nextPutAll: 'Changed:'.
		self notes do: [:each | s nextPutAll: lf; nextPutAll: '- `'; nextPutAll: each; nextPut: $`].
		s nextPutAll: lf]
! !

!GitHubSourceStore methodsFor: 'printing'!
printOn: aStream
	| n |
	aStream nextPutAll: 'a GitHubSourceStore ('; nextPutAll: (self account repository ifNil: ['no repository']).
	n := self pendingChanges size.
	aStream nextPutAll: ', '; print: n; nextPutAll: (n = 1 ifTrue: [' changed file'] ifFalse: [' changed files']); nextPut: $)
! !

!GitHubSourceStore class methodsFor: 'instance creation'!
on: aGitHubAccount
	^self new setAccount: aGitHubAccount
! !

!GitHubSourceStore class methodsFor: 'naming'!
titleOf: aMessage
	"The message's first line."
	^(aMessage copyUpTo: Character lf) trimBoth
!
slugOf: aString
	"aString's ASCII letters and digits in lowercase, other runs as one -, at most 40 characters: 'Kernel: gcd: handles 0' -> 'kernel-gcd-handles-0'."
	| out dash slug |
	out := WriteStream on: (String new: 40).
	dash := false.
	aString do: [:c |
		(c value < 128 and: [c isLetter or: [c isDigit]])
			ifTrue: [
				(dash and: [out position > 0]) ifTrue: [out nextPut: $-].
				dash := false.
				out nextPut: c asLowercase]
			ifFalse: [dash := true]].
	slug := out contents.
	slug size > 40 ifTrue: [slug := slug copyFrom: 1 to: 40].
	[slug notEmpty and: [slug last = $-]] whileTrue: [slug := slug allButLast].
	^slug
! !
