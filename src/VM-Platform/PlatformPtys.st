VMPlatformModule subclass: #PlatformPtys
	instanceVariableNames: 'hungUp'
	classVariableNames: 'HUNG_UP_MAX'
	package: 'VM-Platform'!

PlatformPtys comment: 'Pseudo-terminals: a child process (a shell) on the slave side of a new pty, the master in the socket table (kind PF_FD_PTY, ptr a pty_child), so reading, writing and the readiness semaphores work like a socket''s (PlatformSockets). The child gets its own session with the slave as controlling terminal, default signal dispositions (the VM ignores SIGPIPE) and no other inherited descriptors. Children closed before they ended are reaped later (hungUp).'!

!PlatformPtys class methodsFor: 'declaring'!
declarations
	^#((hungUp 'int64_t[HUNG_UP_MAX]'))
!
initialize
	HUNG_UP_MAX := 64
! !

!PlatformPtys methodsFor: 'private'!
reapHungUp
	<c: 'void reap_hung_up(void)'>
	0 to: HUNG_UP_MAX - 1 do: [:i |
		((hungUp at: i) ~= 0 and: [(posixProcesses waitpid: (hungUp at: i) asInt32 status: self null options: posixProcesses WNOHANG) ~= 0]) ifTrue: [
			hungUp at: i put: 0]]
!
resolve: argv0 environment: envp
	"The malloc'd path of argv0, searched in PATH (from envp, else ours) unless it has a slash; NULL (and the error set) if there is none."
	<c: 'char *pty_resolve(const char *argv0, char **envp)'>
	<var: #path type: 'const char *'>
	<var: #end type: 'const char *'>
	| path e n done end len cand |
	(posixIO strchr: argv0 char: $/ value) notNull ifTrue: [
		(posixIO access: argv0 mode: posixIO X_OK) ~= 0 ifTrue: [
			common failOS: argv0 code: posixIO errno.
			^self null].
		cand := libc strdup: argv0.
		cand isNull ifTrue: [common failOS: argv0 code: posixIO errno].
		^cand].
	path := self null.
	e := envp.
	[e notNull and: [e value notNull and: [path isNull]]] whileTrue: [
		(posixIO strncmp: e value with: 'PATH=' size: 5) = 0 ifTrue: [path := e value + 5].
		e := e + 1].
	path isNull ifTrue: [path := libc getenv: 'PATH'].
	path isNull ifTrue: [path := '/usr/bin:/bin'].
	n := libc strlen: argv0.
	done := false.
	[done not and: [path value ~= 0]] whileTrue: [
		end := posixIO strchr: path char: $: value.
		len := end notNull ifTrue: [(end - path) asUInt64] ifFalse: [libc strlen: path].
		cand := self cCoerce: (libc malloc: len + n + 2) to: 'char *'.
		cand isNull ifTrue: [
			common failOS: argv0 code: posixIO errno.
			^self null].
		libc memcpy: cand from: path size: len.
		cand at: len put: $/ value.
		libc memcpy: cand + len + 1 from: argv0 size: n + 1.
		(len ~= 0 and: [(posixIO access: cand mode: posixIO X_OK) = 0]) ifTrue: [^cand].
		libc free: cand.
		end isNull
			ifTrue: [done := true]
			ifFalse: [path := end + 1]].
	common failOS: argv0 code: posixIO ENOENT.
	^self null
!
childEnvironment: envp
	"envp (or ours) with TERM=xterm-256color unless envp sets TERM; the strings are shared, the array malloc'd."
	<c: 'char **pty_child_env(char **envp)'>
	| src n hasTerm env k |
	src := envp notNull ifTrue: [envp] ifFalse: [host environment].
	n := 0 asUInt64.
	hasTerm := false.
	[(src at: n) notNull] whileTrue: [
		(envp notNull and: [(posixIO strncmp: (src at: n) with: 'TERM=' size: 5) = 0]) ifTrue: [hasTerm := true].
		n := n + 1].
	env := self cCoerce: (libc malloc: (n + 2) * (self sizeof: 'char *')) to: 'char **'.
	env isNull ifTrue: [^self null].
	k := 0 asUInt64.
	0 to: n asInt64 - 1 do: [:i |
		(envp notNull or: [(posixIO strncmp: (src at: i) with: 'TERM=' size: 5) ~= 0]) ifTrue: [
			env at: k put: (src at: i).
			k := k + 1]].
	hasTerm ifFalse: [
		env at: k put: 'TERM=xterm-256color'.
		k := k + 1].
	env at: k put: self null.
	^env
!
writeError: message
	"In the forked child: message and CR LF to stderr."
	| crlf |
	crlf := self local: 'char[2]'.
	crlf at: 0 put: 13.
	crlf at: 1 put: 10.
	posixIO write: 2 bytes: message count: (libc strlen: message).
	posixIO write: 2 bytes: crlf count: 2
!
execChild: path argv: argv environment: env directory: cwd maxFd: maxFd
	"In the forked child: async-signal-safe calls only."
	<c: 'void pty_exec_child(char *path, char **argv, char **env, const char *cwd, int max_fd)'>
	<noreturn>
	| dfl none |
	dfl := self local: 'struct sigaction'.
	dfl sa_handler: posixProcesses SIG_DFL.
	none := self local: 'sigset_t'.
	1 to: posixProcesses NSIG - 1 do: [:s | posixProcesses sigaction: s action: dfl old: self null].
	posixProcesses sigemptyset: none.
	posixProcesses sigprocmask: posixProcesses SIG_SETMASK set: none old: self null.
	3 to: maxFd - 1 do: [:fd | posixIO close: fd].
	(cwd notNull and: [(posixProcesses chdir: cwd) ~= 0]) ifTrue: [self writeError: 'samaltak: cannot change directory'].
	posixProcesses execve: path argv: argv envp: env.
	posixIO write: 2 bytes: 'samaltak: cannot execute ' count: 25.
	self writeError: path.
	posixProcesses exit: 127
!
child: p
	"The pty_child of pty handle p, NULL (and the error set) if it is none."
	<c: 'pty_child *pty_child_of(int p)'>
	| o |
	o := sockets fdGet: p kind: PF_FD_PTY.
	o isNull ifTrue: [^self null].
	^o ptr
! !

!PlatformPtys methodsFor: 'pseudo-terminals'!
spawn: argv environment: envp directory: cwd rows: rows columns: cols pid: pidOut
	"argv first is looked up in PATH; envp NULL = inherit (TERM=xterm-256color is set either way unless envp has TERM); cwd NULL = inherit."
	<c: 'int pf_pty_spawn(char **argv, char **envp, const char *cwd, int rows, int cols, int64_t *pid_out)'>
	<export>
	| path env child ws maxFd master pid saved h |
	platform init.
	self reapHungUp.
	path := self resolve: (argv at: 0) environment: envp.
	path isNull ifTrue: [^0].
	env := self childEnvironment: envp.
	child := self cCoerce: (libc malloc: (self sizeof: 'pty_child')) to: 'pty_child *'.
	(env isNull or: [child isNull]) ifTrue: [
		libc free: path.
		libc free: env.
		libc free: child.
		common setError: 'out of memory'.
		^0].
	ws := self local: 'struct winsize'.
	ws ws_row: rows asUInt16.
	ws ws_col: cols asUInt16.
	maxFd := posixProcesses getdtablesize.
	maxFd > 65536 ifTrue: [maxFd := 65536].
	master := self local: 'int'.
	pid := posixProcesses forkpty: master name: self null termios: self null winsize: ws.
	pid = 0 ifTrue: [self execChild: path argv: argv environment: env directory: cwd maxFd: maxFd].
	saved := posixIO errno.
	libc free: path.
	libc free: env.
	pid < 0 ifTrue: [
		libc free: child.
		common failOS: 'forkpty' code: saved.
		^0].
	child pid: pid.
	child reaped: false.
	h := sockets add: master value kind: PF_FD_PTY pointer: child.
	h = 0 ifTrue: [
		posixIO close: master value.
		posixProcesses kill: pid signal: posixProcesses SIGHUP.
		hungUp at: (pid rem: HUNG_UP_MAX) put: pid.
		libc free: child.
		^0].
	pidOut value: pid.
	^h
!
resize: p rows: rows columns: cols
	<c: 'bool pf_pty_resize(int p, int rows, int cols)'>
	<export>
	| o ws |
	o := sockets fdGet: p kind: PF_FD_PTY.
	o isNull ifTrue: [^false].
	ws := self local: 'struct winsize'.
	ws ws_row: rows asUInt16.
	ws ws_col: cols asUInt16.
	(posixProcesses ioctl: o i asInt32 request: posixProcesses TIOCSWINSZ argument: ws) = 0 ifTrue: [^true].
	common failOS: 'TIOCSWINSZ' code: posixIO errno.
	^false
!
wait: p block: block status: status done: done
	"status as pf_process_wait's."
	<c: 'bool pf_pty_wait(int p, bool block, int *status, bool *done)'>
	<export>
	| c |
	c := self child: p.
	c isNull ifTrue: [^false].
	c reaped ifTrue: [
		common setError: 'pty child already waited for'.
		^false].
	(files processWait: c pid block: block status: status done: done) ifFalse: [^false].
	c reaped: done value.
	^true
!
foreground: p
	"The foreground process group of pty p's terminal, < 0 (and the error set) if it cannot be told."
	<c: 'int pf_pty_foreground(int p)'>
	<export>
	| o |
	o := sockets fdGet: p kind: PF_FD_PTY.
	o isNull ifTrue: [^-1].
	^posixProcesses tcgetpgrp: o i asInt32
!
close: p
	"Hangs up the child (SIGHUP) unless it has ended."
	<c: 'bool pf_pty_close(int p)'>
	<export>
	| c ok placed |
	c := self child: p.
	c isNull ifTrue: [^false].
	ok := sockets close: p kind: PF_FD_PTY.
	c reaped ifFalse: [
		"its process group: the shell and its foreground job"
		posixProcesses kill: c pid negated signal: posixProcesses SIGHUP.
		posixProcesses kill: c pid signal: posixProcesses SIGHUP.
		(posixProcesses waitpid: c pid status: self null options: posixProcesses WNOHANG) = 0 ifTrue: [
			self reapHungUp.
			placed := false.
			0 to: HUNG_UP_MAX - 1 do: [:i |
				(placed not and: [(hungUp at: i) = 0 or: [i = (HUNG_UP_MAX - 1)]]) ifTrue: [
					hungUp at: i put: c pid.
					placed := true]]]].
	libc free: c.
	^ok
! !

VMStruct subclass: #PtyChild
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PtyChild comment: 'The child process of a pty, and whether it has been waited for.'!

!PtyChild class methodsFor: 'declaring'!
fields
	^#((pid int32_t) (reaped bool))
! !
