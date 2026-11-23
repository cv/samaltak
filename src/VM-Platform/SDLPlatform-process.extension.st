!SDLPlatform methodsFor: 'FFI - processes'!
ffiProcessSpawn: bytes size: n
	<function>
	<approvedFFI: 515 symbol: 'platform_process_spawn' arguments: #(8) result: 3>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	| request pid |
	request := self local: 'pf_process_request'.
	pid := (self decodeProcess: bytes size: n pty: false into: request)
		ifTrue: [files spawn: request argv]
		ifFalse: [-1].
	self releaseProcess: request.
	^pid
!
ffiProcessWait: pid block: block into: out capacity: cap
	<function>
	<approvedFFI: 516 symbol: 'platform_process_wait' arguments: #(3 1 9) result: 1>
	<var: #pid type: 'int64_t'>
	<var: #block type: 'int32_t'>
	<var: #out type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| status done |
	(cap ~= 5 or: [out isNull or: [pid ~= pid asInt32 or: [block ~= 0 and: [block ~= 1]]]]) ifTrue: [
		common setError: 'invalid process wait arguments'.
		^0].
	status := self local: 'int'.
	done := self local: 'bool'.
	(files processWait: pid block: block = 1 status: status done: done) ifFalse: [^0].
	out at: 0 put: ((done value ifTrue: [1] ifFalse: [0]) asUInt8).
	self processWord: (done value ifTrue: [status value asUInt32] ifFalse: [0]) into: out + 1 bytes: 4.
	^1
!
ffiProcessExec: bytes size: n
	<function>
	<approvedFFI: 518 symbol: 'platform_process_exec' arguments: #(8) result: 1>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	| request |
	request := self local: 'pf_process_request'.
	(self decodeProcess: bytes size: n pty: false into: request) ifTrue: [files exec: request argv].
	self releaseProcess: request.
	^0
!
ffiPtySpawn: bytes size: n rows: rows columns: cols into: out capacity: cap
	<function>
	<approvedFFI: 560 symbol: 'platform_pty_spawn' arguments: #(8 1 1 9) result: 1>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #rows type: 'int32_t'>
	<var: #cols type: 'int32_t'>
	<var: #out type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| request pid h |
	(cap ~= 16 or: [out isNull or: [rows <= 0 or: [cols <= 0 or: [rows > 65535 or: [cols > 65535]]]]]) ifTrue: [
		common setError: 'invalid pty spawn arguments'.
		^0].
	request := self local: 'pf_process_request'.
	pid := self local: 'int64_t'.
	h := (self decodeProcess: bytes size: n pty: true into: request)
		ifTrue: [ptys spawn: request argv environment: request envp directory: request cwd rows: rows columns: cols pid: pid]
		ifFalse: [0].
	self releaseProcess: request.
	h <= 0 ifTrue: [^0].
	self processWord: h asUInt64 into: out bytes: 8.
	self processWord: pid value asUInt64 into: out + 8 bytes: 8.
	^1
! !

!SDLPlatform methodsFor: 'FFI - process records'!
decodeProcess: bytes size: n pty: pty into: request
	"LE32 count, then LE32 length and bytes per string. For PTY this is followed by the env vector and cwd string; all-ones means inherit for those two fields only."
	<function>
	<var: #bytes type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #pty type: 'bool'>
	<var: #request type: 'pf_process_request *'>
	<returns: 'bool'>
	| count len |
	request storage: self null.
	request argv: self null.
	request envp: self null.
	request cwd: self null.
	"VM byte objects have at most 2^32 - 1 eight-byte slots. These spans and (LE32 count + 1) pointers both fit in a hosted size_t and ptrdiff_t."
	(bytes isNull or: [n > 16r7FFFFFFF8]) ifTrue: [^self invalidProcessRecord].
	request input: bytes.
	request remaining: n.
	count := self processLE32: request.
	(count <= 0 or: [count = 16rFFFFFFFF or: [count asUInt64 > (request remaining >> 2)]]) ifTrue: [^self invalidProcessRecord].
	"One native slab suffices: every copied string and NUL consumes fewer bytes than its wire record."
	request storage: (self cCoerce: (libc malloc: n) to: 'char *').
	request storage isNull ifTrue: [common setError: 'out of memory'. ^false].
	request next: request storage.
	request argv: (self processVector: count in: request).
	request argv isNull ifTrue: [^false].
	((request argv at: 0) at: 0) = 0 ifTrue: [^self invalidProcessRecord].
	pty ifTrue: [
		count := self processLE32: request.
		count ~= 16rFFFFFFFF ifTrue: [
			request envp: (self processVector: count in: request).
			request envp isNull ifTrue: [^false]].
		len := self processLE32: request.
		len ~= 16rFFFFFFFF ifTrue: [
			request cwd: (self processString: len in: request).
			request cwd isNull ifTrue: [^self invalidProcessRecord]]].
	request remaining ~= 0 ifTrue: [^self invalidProcessRecord].
	^true
!
releaseProcess: request
	<function>
	<var: #request type: 'pf_process_request *'>
	libc free: request argv.
	libc free: request envp.
	libc free: request storage
!
processVector: count in: request
	<function>
	<var: #count type: 'int64_t'>
	<var: #request type: 'pf_process_request *'>
	<returns: 'char **'>
	| vector s |
	(count < 0 or: [count asUInt64 > (request remaining >> 2)]) ifTrue: [
		self invalidProcessRecord.
		^self null].
	vector := self cCoerce: (libc malloc: (count asUInt64 + 1) * (self sizeof: 'char *')) to: 'char **'.
	vector isNull ifTrue: [
		common setError: 'out of memory'.
		^self null].
	0 to: count - 1 do: [:i |
		s := self processString: (self processLE32: request) in: request.
		s isNull ifTrue: [
			libc free: vector.
			self invalidProcessRecord.
			^self null].
		vector at: i put: s].
	vector at: count put: self null.
	^vector
!
processString: len in: request
	<function>
	<var: #len type: 'int64_t'>
	<var: #request type: 'pf_process_request *'>
	<returns: 'char *'>
	| src dest n |
	(len < 0 or: [len = 16rFFFFFFFF or: [len asUInt64 > request remaining]]) ifTrue: [^self null].
	n := len asUInt64.
	src := request input.
	dest := request next.
	n ~= 0 ifTrue: [
		(libc memchr: src value: 0 size: n) notNull ifTrue: [^self null].
		libc memcpy: dest from: src size: n].
	dest at: n put: 0.
	request next: dest + n + 1.
	request input: src + n.
	request remaining: request remaining - n.
	^dest
!
processLE32: request
	<function>
	<var: #request type: 'pf_process_request *'>
	<returns: 'int64_t'>
	| src word |
	request remaining < 4 ifTrue: [^-1].
	src := request input.
	word := 0 asUInt64.
	0 to: 3 do: [:i | word := word bitOr: ((src at: i) asUInt64 << (i * 8))].
	request input: src + 4.
	request remaining: request remaining - 4.
	^word asInt64
!
processWord: value into: out bytes: n
	<function>
	<var: #value type: 'uint64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #n type: 'int32_t'>
	0 to: n - 1 do: [:i | out at: i put: (value >> (i * 8)) asUInt8]
!
invalidProcessRecord
	<function>
	<returns: 'bool'>
	common setError: 'invalid process request'.
	^false
! !

VMStruct subclass: #PfProcessRequest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!PfProcessRequest class methodsFor: 'declaring'!
fields
	^#((input 'const uint8_t *') (remaining uint64_t) (storage 'char *') (next 'char *')
		(argv 'char **') (envp 'char **') (cwd 'char *'))
! !
