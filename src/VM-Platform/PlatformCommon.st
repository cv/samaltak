VMPlatformModule subclass: #PlatformCommon
	instanceVariableNames: 'lastError nowBase'
	classVariableNames: 'LAST_ERROR_SIZE'
	package: 'VM-Platform'!

PlatformCommon comment: 'Handle tables, the error string, the platform clock.

A handle table (pf_table) is a growing array of pf_obj; slot 0 is never used, so 0 can mean "no handle", and free slots form a list through their i. setError:with:... format the error string with snprintf (one method per arity).'!

!PlatformCommon class methodsFor: 'declaring'!
declarations
	^#((lastError 'char[LAST_ERROR_SIZE]') (nowBase int64_t -1))
!
initialize
	LAST_ERROR_SIZE := 1024
! !

!PlatformCommon methodsFor: 'errors'!
lastErrorString
	<export>
	^lastError
!
setError: message
	<export>
	libc snprintf: lastError size: LAST_ERROR_SIZE format: '%s' with: message
!
setError: format with: a
	libc snprintf: lastError size: LAST_ERROR_SIZE format: format with: a
!
setError: format with: a with: b
	libc snprintf: lastError size: LAST_ERROR_SIZE format: format with: a with: b
!
setError: format with: a with: b with: c
	libc snprintf: lastError size: LAST_ERROR_SIZE format: format with: a with: b with: c
!
failOS: what code: code
	"what: the strerror of code."
	<function>
	<var: #what type: 'char *'>
	<var: #code type: 'int'>
	self setError: '%s: %s' with: what with: (posixIO strerror: code)
!
failOS: what path: path code: code
	"what path: the strerror of code; path may be NULL."
	<function>
	<var: #what type: 'char *'>
	<var: #path type: 'char *'>
	<var: #code type: 'int'>
	self setError: '%s %s: %s' with: what with: (path notNull ifTrue: [path] ifFalse: ['']) with: (posixIO strerror: code)
! !

!PlatformCommon methodsFor: 'time'!
nowMs
	"Monotonic, ms since the first call."
	<export>
	| ts ms |
	ts := self local: 'struct timespec'.
	posix clockGettime: posix CLOCK_MONOTONIC into: ts.
	ms := (ts tv_sec * 1000) + (ts tv_nsec quo: 1000000).
	nowBase < 0 ifTrue: [nowBase := ms].
	^ms - nowBase
! !

!PlatformCommon methodsFor: 'handle tables'!
table: t add: kind pointer: ptr
	"A new handle of kind for ptr (its other fields zero), 0 if out of memory."
	<export>
	<var: #t type: 'pf_table *'>
	<var: #kind type: 'int'>
	<var: #ptr type: 'void *'>
	| h cap v o |
	t freeHead ~= 0
		ifTrue: [
			h := t freeHead.
			t freeHead: (t v + h) i]
		ifFalse: [
			t n = 0 ifTrue: [t n: 1].
			t n >= t cap ifTrue: [
				cap := t cap ~= 0 ifTrue: [t cap * 2] ifFalse: [64].
				v := self cCoerce: (libc realloc: t v size: (self sizeof: 'pf_obj') * cap asUInt64) to: 'pf_obj *'.
				v isNull ifTrue: [^0].
				t v: v.
				t cap: cap].
			h := t n.
			t n: t n + 1].
	o := t v + h.
	libc memset: o value: 0 size: (self sizeof: 'pf_obj').
	o kind: kind.
	o ptr: ptr.
	^h
!
table: t at: h kind: kind
	"The live object of handle h, if it has kind (any kind if kind < 0); else NULL."
	<export>
	<var: #t type: 'pf_table *'>
	<var: #h type: 'int32_t'>
	<var: #kind type: 'int'>
	| o |
	(h <= 0 or: [h >= t n]) ifTrue: [^self null].
	o := t v + h.
	(o kind = 0 or: [kind >= 0 and: [o kind ~= kind]]) ifTrue: [^self null].
	^o
!
table: t remove: h
	<export>
	<var: #t type: 'pf_table *'>
	<var: #h type: 'int32_t'>
	| o |
	(h <= 0 or: [h >= t n]) ifTrue: [^self].
	o := t v + h.
	o kind = 0 ifTrue: [^self].
	o kind: 0.
	o ptr: self null.
	o i: t freeHead.
	t freeHead: h
!
table: t count: kind
	"Live handles of kind (any kind if kind < 0)."
	<export>
	<var: #t type: 'pf_table *'>
	<var: #kind type: 'int'>
	| n o |
	n := 0.
	1 to: t n - 1 do: [:h |
		o := t v + h.
		(o kind ~= 0 and: [kind < 0 or: [o kind = kind]]) ifTrue: [n := n + 1]].
	^n asInt32
!
handleCounts: out
	"Live handles: files sockets windows gpuDevices shaders pipelines textures samplers buffers fences ptys."
	<export>
	out at: 0 put: files handleCount.
	out at: 1 put: sockets handleCount.
	out at: 2 put: windows handleCount.
	gpu handleCounts: out + 3.
	out at: 10 put: sockets ptyHandleCount
! !

VMStruct subclass: #PfObj
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PfObj comment: 'An entry of a handle table: kind (0 = free), the object, its device and a texture''s size and format, an integer (a file descriptor, a window id, a buffer size; the next free slot of a free entry).'!

!PfObj class methodsFor: 'declaring'!
fields
	^#((kind int32_t) (ptr 'void *') (dev int32_t) (w int32_t) (h int32_t) (fmt int32_t) (i int64_t))
! !

VMStruct subclass: #PfTable
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PfTable comment: 'A handle table: n entries in use (from 1) of cap, and the head of the free list.'!

!PfTable class methodsFor: 'declaring'!
fields
	^#((v 'pf_obj *') (n int32_t) (cap int32_t) (freeHead int32_t))
! !
