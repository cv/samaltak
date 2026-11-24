VMModule subclass: #NativeCountedText
	instanceVariableNames: 'libc'
	classVariableNames: ''
	package: 'VM-Core'!

NativeCountedText comment: 'Copy synchronous byte borrows before passing text to a C-string consumer. The caller owns the copy; no VM heap pointer is retained.'!

!NativeCountedText class methodsFor: 'declaring'!
declarations
	^#((libc LibC))
! !

!NativeCountedText methodsFor: 'copying'!
copyTerminated: bytes size: count
	"Caller must supply count readable bytes for this synchronous call. Reject NUL, impossible VM byte counts and a nonempty NULL span. Empty spans (including NULL,0) get an allocated empty string. NULL is a native error, including OOM. Free the result with libc."
	<function>
	<var: #bytes type: 'const void *'>
	<var: #count type: 'uint64_t'>
	<returns: 'char *'>
	| copy |
	"VM byte objects have at most 2^32 - 1 eight-byte slots. Also bounds count + 1."
	count > 16r7FFFFFFF8 ifTrue: [^self null].
	count ~= 0 ifTrue: [
		(bytes isNull or: [(libc memchr: bytes value: 0 size: count) notNull]) ifTrue: [^self null]].
	copy := self cCoerce: (libc malloc: count + 1) to: 'char *'.
	copy isNull ifTrue: [^self null].
	count ~= 0 ifTrue: [libc memcpy: copy from: bytes size: count].
	copy at: count put: 0.
	^copy
! !
