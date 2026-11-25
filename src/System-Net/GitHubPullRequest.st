Object subclass: #GitHubPullRequest
	instanceVariableNames: 'number url branch commitSha'
	classVariableNames: ''
	package: 'System-Net'!

GitHubPullRequest comment: 'I am what SourceFiler>>commit: made on GitHub: the branch (without refs/heads/) and the commit on it, and the pull request''s number and web URL (nil when it was asked for no pull request).'!

!GitHubPullRequest methodsFor: 'initialization'!
setBranch: aString commitSha: aSha
	branch := aString.
	commitSha := aSha
!
setNumber: anInteger url: aString
	number := anInteger.
	url := aString
! !

!GitHubPullRequest methodsFor: 'accessing'!
number
	^number
!
url
	^url
!
branch
	^branch
!
commitSha
	^commitSha
!
hasPullRequest
	^number notNil
! !

!GitHubPullRequest methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a GitHubPullRequest'.
	number isNil ifFalse: [aStream nextPutAll: ' #'; print: number].
	aStream nextPutAll: ' ('; nextPutAll: (commitSha ifNil: ['?'] ifNotNil: [:sha | sha copyFrom: 1 to: (sha size min: 7)]); nextPutAll: ' on '; nextPutAll: (branch ifNil: ['?']); nextPut: $).
	url isNil ifFalse: [aStream space; nextPutAll: url]
! !
