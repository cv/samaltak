VMPlatformModule subclass: #PlatformFiles
	instanceVariableNames: 'table wbLock wbAdded wbFinished wbHead wbTail wbPending wbFailedFd wbErrno wbStarted'
	classVariableNames: 'K_FILE WB_MAX'
	package: 'VM-Platform'!

PlatformFiles comment: 'Files (raw file descriptors, unbuffered; handles of kind K_FILE, i = the descriptor), directories, FIFOs, child processes.

Write-behind: a background thread performs queued writes, so a slow reader (a FIFO into ffmpeg) does not block the VM thread. At most WB_MAX writes are pending at once; flush and close wait until a file''s writes are done. A queued write stays at the head of the queue while it is written.'!

!PlatformFiles class methodsFor: 'declaring'!
declarations
	^#((table 'pf_table[1]') (wbLock 'pthread_mutex_t[1]') (wbAdded 'pthread_cond_t[1]') (wbFinished 'pthread_cond_t[1]')
		(wbHead 'wb_job *') (wbTail 'wb_job *') (wbPending int32_t) (wbFailedFd int32_t -1) (wbErrno int32_t) (wbStarted bool))
!
initialize
	K_FILE := 1.
	WB_MAX := 3
! !

!PlatformFiles methodsFor: 'private'!
failOS: what
	common failOS: what path: self null code: posixIO errno
!
failOS: what path: path
	common failOS: what path: path code: posixIO errno
!
fdOf: f
	"The descriptor of file handle f, -1 (and the error set) if it is none."
	<c: 'int file_fd(int f)'>
	| o |
	o := common table: table at: f kind: K_FILE.
	o isNull ifTrue: [
		common setError: 'bad file handle %d' with: f.
		^-1].
	^o i asInt32
!
openFlags: mode
	^mode caseOf: {
		[PF_FILE_READ] -> [posixIO O_RDONLY].
		[PF_FILE_READ_WRITE] -> [posixIO O_RDWR bitOr: posixIO O_CREAT].
		[PF_FILE_APPEND] -> [(posixIO O_WRONLY bitOr: posixIO O_APPEND) bitOr: posixIO O_CREAT]}
		otherwise: [(posixIO O_RDWR bitOr: posixIO O_CREAT) bitOr: posixIO O_TRUNC]
! !

!PlatformFiles methodsFor: 'files'!
init
	"From platform_init."
	<c: 'void pf_files_init(void)'>
	posixThreads mutexInit: wbLock attributes: self null.
	posixThreads condInit: wbAdded attributes: self null.
	posixThreads condInit: wbFinished attributes: self null
!
open: path mode: mode
	"mode: PF_FILE_READ, PF_FILE_READ_WRITE, PF_FILE_APPEND or PF_FILE_CREATE_TRUNCATE."
	<c: 'int pf_file_open(const char *path, int mode)'>
	<export>
	| fd h |
	platform init.
	(mode < 0 or: [mode > 3]) ifTrue: [
		common setError: 'bad file mode %d' with: mode.
		^0].
	fd := posixIO open: path flags: ((self openFlags: mode) bitOr: posixIO O_CLOEXEC) mode: 8r644.
	fd < 0 ifTrue: [
		self failOS: 'open' path: path.
		^0].
	h := common table: table add: K_FILE pointer: self null.
	(table v + h) i: fd.
	^h
!
close: f
	<c: 'bool pf_file_close(int f)'>
	<export>
	| fd |
	fd := self fdOf: f.
	fd < 0 ifTrue: [^false].
	self writesDone: fd.
	common table: table remove: f.
	(posixIO close: fd) = 0 ifTrue: [^true].
	self failOS: 'close'.
	^false
!
read: f into: buf count: n
	"< 0 on error."
	<c: 'int64_t pf_file_read(int f, void *buf, size_t n)'>
	<export>
	| fd r |
	fd := self fdOf: f.
	fd < 0 ifTrue: [^-1].
	[r := posixIO read: fd into: buf count: n.
	 r < 0 and: [posixIO errno = posixIO EINTR]] whileTrue.
	r < 0 ifTrue: [self failOS: 'read'].
	^r
!
write: f bytes: buf count: n
	"< 0 on error."
	<c: 'int64_t pf_file_write(int f, const void *buf, size_t n)'>
	<export>
	<var: #done type: 'size_t'>
	| fd p done r |
	fd := self fdOf: f.
	fd < 0 ifTrue: [^-1].
	p := self cCoerce: buf to: 'uint8_t *'.
	done := 0.
	[done < n] whileTrue: [
		r := posixIO write: fd bytes: p + done count: n - done.
		r < 0
			ifTrue: [
				posixIO errno ~= posixIO EINTR ifTrue: [
					self failOS: 'write'.
					^-1]]
			ifFalse: [done := done + r asUInt64]].
	^done asInt64
!
size: f
	<c: 'int64_t pf_file_size(int f)'>
	<export>
	| fd st |
	fd := self fdOf: f.
	st := self local: 'struct stat'.
	fd < 0 ifTrue: [^-1].
	(posixIO fstat: fd into: st) ~= 0 ifTrue: [
		self failOS: 'fstat'.
		^-1].
	^st st_size
!
position: f
	<c: 'int64_t pf_file_position(int f)'>
	<export>
	| fd r |
	fd := self fdOf: f.
	fd < 0 ifTrue: [^-1].
	r := posixIO lseek: fd offset: 0 whence: posixIO SEEK_CUR.
	r < 0 ifTrue: [self failOS: 'lseek'].
	^r
!
seek: f to: pos
	<c: 'bool pf_file_seek(int f, int64_t pos)'>
	<export>
	| fd |
	fd := self fdOf: f.
	fd < 0 ifTrue: [^false].
	(posixIO lseek: fd offset: pos whence: posixIO SEEK_SET) >= 0 ifTrue: [^true].
	self failOS: 'lseek'.
	^false
!
flush: f
	"Writes are unbuffered, so flush only pushes regular files to disk."
	<c: 'bool pf_file_flush(int f)'>
	<export>
	| fd st e |
	fd := self fdOf: f.
	st := self local: 'struct stat'.
	fd < 0 ifTrue: [^false].
	e := self writesDone: fd.
	e ~= 0 ifTrue: [
		common failOS: 'write' path: self null code: e.
		^false].
	((posixIO fstat: fd into: st) = 0 and: [(posixIO S_ISREG: st st_mode) and: [(posixIO fsync: fd) ~= 0]]) ifTrue: [
		self failOS: 'fsync'.
		^false].
	^true
!
handleCount
	<c: 'int pf_file_handle_count(void)'>
	<export>
	^common table: table count: -1
! !

!PlatformFiles methodsFor: 'write-behind'!
writeBehind: f bytes: buf count: n
	"Queue a copy for the writer thread: n, 0 if WB_MAX writes are pending, < 0 on an error (also of an earlier write)."
	<c: 'int64_t pf_file_write_behind(int f, const void *buf, size_t n)'>
	<export>
	| fd e j data t |
	fd := self fdOf: f.
	fd < 0 ifTrue: [^-1].
	posixThreads mutexLock: wbLock.
	wbFailedFd = fd ifTrue: [
		wbFailedFd := -1.
		e := wbErrno.
		posixThreads mutexUnlock: wbLock.
		common failOS: 'write' path: self null code: e.
		^-1].
	wbPending >= WB_MAX ifTrue: [
		posixThreads mutexUnlock: wbLock.
		^0].
	j := self cCoerce: (libc malloc: (self sizeof: 'wb_job')) to: 'wb_job *'.
	data := self cCoerce: (libc malloc: (n ~= 0 ifTrue: [n] ifFalse: [1])) to: 'char *'.
	(j isNull or: [data isNull]) ifTrue: [
		libc free: j.
		libc free: data.
		posixThreads mutexUnlock: wbLock.
		common setError: 'out of memory'.
		^-1].
	libc memcpy: data from: buf size: n.
	j fd: fd.
	j data: data.
	j len: n.
	j next: self null.
	wbTail notNull ifTrue: [wbTail next: j] ifFalse: [wbHead := j].
	wbTail := j.
	wbPending := wbPending + 1.
	wbStarted ifFalse: [
		t := self local: 'pthread_t'.
		(posix pthreadCreate: t attributes: self null start: (self functionPointer: #writer:) argument: self null) = 0 ifTrue: [
			posix pthreadDetach: t value.
			wbStarted := true]].
	posixThreads condSignal: wbAdded.
	posixThreads mutexUnlock: wbLock.
	^n asInt64
!
writer: arg
	"The writer thread: perform the queued writes in order."
	<c: 'void *wb_main(void *arg)'>
	<var: #e type: 'int'>
	<var: #done type: 'size_t'>
	| j done e r |
	[posixThreads mutexLock: wbLock.
	 [wbHead isNull] whileTrue: [posixThreads condWait: wbAdded mutex: wbLock].
	 j := wbHead.
	 posixThreads mutexUnlock: wbLock.
	 done := 0.
	 e := 0.
	 [done < j len and: [e = 0]] whileTrue: [
		r := posixIO write: j fd bytes: j data + done count: j len - done.
		r < 0
			ifTrue: [posixIO errno ~= posixIO EINTR ifTrue: [e := posixIO errno]]
			ifFalse: [done := done + r asUInt64]].
	 posixThreads mutexLock: wbLock.
	 wbHead := j next.
	 wbHead isNull ifTrue: [wbTail := self null].
	 wbPending := wbPending - 1.
	 e ~= 0 ifTrue: [
		wbFailedFd := j fd.
		wbErrno := e].
	 posixThreads condBroadcast: wbFinished.
	 posixThreads mutexUnlock: wbLock.
	 libc free: j data.
	 libc free: j] repeat
!
hasWrites: fd
	"With wbLock held."
	<c: 'bool wb_has(int fd)'>
	| j |
	j := wbHead.
	[j notNull] whileTrue: [
		j fd = fd ifTrue: [^true].
		j := j next].
	^false
!
writesDone: fd
	"Wait until fd's queued writes are done; answer the errno of one that failed, else 0."
	<c: 'int wb_drain(int fd)'>
	<var: #e type: 'int'>
	| e |
	posixThreads mutexLock: wbLock.
	[self hasWrites: fd] whileTrue: [posixThreads condWait: wbFinished mutex: wbLock].
	e := 0.
	wbFailedFd = fd ifTrue: [
		wbFailedFd := -1.
		e := wbErrno].
	posixThreads mutexUnlock: wbLock.
	^e
! !

!PlatformFiles methodsFor: 'paths'!
delete: path
	<c: 'bool pf_file_delete(const char *path)'>
	<export>
	(posixIO unlink: path) = 0 ifTrue: [^true].
	((posixIO errno = posixIO EISDIR or: [posixIO errno = posixIO EPERM]) and: [(posixIO rmdir: path) = 0]) ifTrue: [^true].
	self failOS: 'delete' path: path.
	^false
!
rename: from to: to
	<c: 'bool pf_file_rename(const char *from, const char *to)'>
	<export>
	(posixIO rename: from to: to) = 0 ifTrue: [^true].
	self failOS: 'rename' path: from.
	^false
!
stat: path into: s
	"A missing path is no error: s exists is false."
	<c: 'bool pf_file_stat(const char *path, pf_stat *s)'>
	<export>
	| st |
	st := self local: 'struct stat'.
	libc memset: s value: 0 size: (self sizeof: 'pf_stat').
	(posixIO stat: path into: st) ~= 0 ifTrue: [
		(posixIO errno = posixIO ENOENT or: [posixIO errno = posixIO ENOTDIR]) ifTrue: [^true].
		self failOS: 'stat' path: path.
		^false].
	s exists: true.
	s isDir: (posixIO S_ISDIR: st st_mode).
	s fileSize: st st_size.
	s mtimeUs: (st st_mtimespec tv_sec * 1000000) + (st st_mtimespec tv_nsec quo: 1000).
	^true
!
dirEntries: path count: n
	"A malloc'd array of n malloc'd names."
	<c: 'char **pf_dir_entries(const char *path, int *n)'>
	<export>
	<var: #cap type: 'int'>
	| d cap v ok e nv s |
	d := posixIO opendir: path.
	d isNull ifTrue: [
		self failOS: 'opendir' path: path.
		^self null].
	cap := 64.
	v := self cCoerce: (libc malloc: (self sizeof: 'char *') * cap asUInt64) to: 'char **'.
	n value: 0.
	ok := v notNull.
	[ok and: [(e := posixIO readdir: d) notNull]] whileTrue: [
		((libc strcmp: e d_name with: '.') = 0 or: [(libc strcmp: e d_name with: '..') = 0]) ifFalse: [
			n value = cap ifTrue: [
				cap := cap * 2.
				nv := self cCoerce: (libc realloc: v size: (self sizeof: 'char *') * cap asUInt64) to: 'char **'.
				ok := nv notNull.
				ok ifTrue: [v := nv]].
			ok ifTrue: [
				s := libc strdup: e d_name.
				ok := s notNull.
				ok ifTrue: [
					v at: n value put: s.
					n value: n value + 1]]]].
	posixIO closedir: d.
	ok ifFalse: [
		[v notNull and: [n value > 0]] whileTrue: [
			n value: n value - 1.
			libc free: (v at: n value)].
		libc free: v.
		common setError: 'out of memory'.
		^self null].
	^v
!
dirCreate: path
	<c: 'bool pf_dir_create(const char *path)'>
	<export>
	(posixIO mkdir: path mode: 8r755) = 0 ifTrue: [^true].
	self failOS: 'mkdir' path: path.
	^false
!
cwd
	"malloc'd."
	<c: 'char *pf_cwd(void)'>
	<export>
	| p |
	p := posixIO getcwd: self null size: 0.
	p isNull ifTrue: [self failOS: 'getcwd'].
	^p
!
mkfifo: path
	<c: 'bool pf_mkfifo(const char *path)'>
	<export>
	(posixIO mkfifo: path mode: 8r644) = 0 ifTrue: [^true].
	self failOS: 'mkfifo' path: path.
	^false
! !

!PlatformFiles methodsFor: 'processes'!
spawn: argv
	"argv first is looked up in PATH; stdio is inherited. The pid, < 0 on error."
	<c: 'int64_t pf_spawn(char **argv)'>
	<export>
	| pid r |
	pid := self local: 'pid_t'.
	platform init.
	r := posixProcesses spawnp: pid file: (argv at: 0) fileActions: self null attributes: self null argv: argv envp: posixProcesses environment value.
	r ~= 0 ifTrue: [
		common failOS: 'posix_spawnp' path: (argv at: 0) code: r.
		^-1].
	^pid value
!
processWait: pid block: block status: status done: done
	"status: the exit code, or 128 + the signal number."
	<c: 'bool pf_process_wait(int64_t pid, bool block, int *status, bool *done)'>
	<export>
	| st r |
	st := self local: 'int'.
	[r := posixProcesses waitpid: pid asInt32 status: st options: (block ifTrue: [0] ifFalse: [posixProcesses WNOHANG]).
	 r < 0 and: [posixIO errno = posixIO EINTR]] whileTrue.
	r < 0 ifTrue: [
		self failOS: 'waitpid'.
		^false].
	done value: r ~= 0.
	done value ifTrue: [
		status value: ((posixProcesses WIFEXITED: st value)
			ifTrue: [posixProcesses WEXITSTATUS: st value]
			ifFalse: [128 + (posixProcesses WTERMSIG: st value)])].
	^true
! !

VMStruct subclass: #PfStat
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PfStat comment: 'What pf_file_stat answers.'!

!PfStat class methodsFor: 'declaring'!
fields
	^#((exists bool) (isDir bool) (fileSize int64_t) (mtimeUs int64_t))
! !

VMStruct subclass: #WbJob
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

WbJob comment: 'A queued write-behind: the bytes (malloc''d) for a file descriptor.'!

!WbJob class methodsFor: 'declaring'!
fields
	^#((fd int32_t) (data 'char *') (len size_t) (next 'wb_job *'))
! !
