CLibrary subclass: #PosixProcesses
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PosixProcesses comment: 'Child processes and pseudo-terminals: posix_spawnp, waitpid, kill, forkpty and what the forked child calls before execve. Not simulated.'!

!PosixProcesses class methodsFor: 'declaring'!
headers
	^#('<spawn.h>' '<sys/wait.h>' '<signal.h>' '<sys/ioctl.h>' '<util.h>' '<crt_externs.h>' '<unistd.h>')
!
typedefs
	^#((posix_spawn_file_actions_t opaque) (posix_spawnattr_t opaque) (sigset_t uint32_t))
! !

!PosixProcesses methodsFor: 'simulation'!
notSimulated
	^self error: 'processes are not simulated'
! !

!PosixProcesses methodsFor: 'processes'!
spawnp: pid file: file fileActions: fileActions attributes: attributes argv: argv envp: envp
	<c: 'int posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *file_actions, const posix_spawnattr_t *attributes, char **argv, char **envp)'>
	^self notSimulated
!
environment
	"The environ of the process: the address of the environment array."
	<c: 'char ***_NSGetEnviron(void)'>
	^self notSimulated
!
waitpid: pid status: status options: options
	<c: 'pid_t waitpid(pid_t pid, int *status, int options)'>
	^self notSimulated
!
WIFEXITED: status
	<c: 'bool WIFEXITED(int status)'>
	^self notSimulated
!
WEXITSTATUS: status
	<c: 'int WEXITSTATUS(int status)'>
	^self notSimulated
!
WTERMSIG: status
	<c: 'int WTERMSIG(int status)'>
	^self notSimulated
!
WNOHANG
	<cMacro: 'int WNOHANG'>
	^1
!
kill: pid signal: sig
	<c: 'int kill(pid_t pid, int sig)'>
	^self notSimulated
!
SIGHUP
	<cMacro: 'int SIGHUP'>
	^1
! !

!PosixProcesses methodsFor: 'pseudo-terminals'!
forkpty: amaster name: name termios: termp winsize: winp
	<c: 'pid_t forkpty(int *amaster, char *name, struct termios *termp, struct winsize *winp)'>
	^self notSimulated
!
ioctl: fd request: request argument: argument
	<c: 'int ioctl(int fd, unsigned long request, ...)'>
	^self notSimulated
!
TIOCSWINSZ
	<cMacro: 'unsigned long TIOCSWINSZ'>
	^self notSimulated
!
getdtablesize
	<c: 'int getdtablesize(void)'>
	^self notSimulated
! !

!PosixProcesses methodsFor: 'the forked child'!
sigaction: sig action: act old: oact
	<c: 'int sigaction(int sig, const struct sigaction *act, struct sigaction *oact)'>
	^self notSimulated
!
sigemptyset: set
	<c: 'int sigemptyset(sigset_t *set)'>
	^self notSimulated
!
sigprocmask: how set: set old: oset
	<c: 'int sigprocmask(int how, const sigset_t *set, sigset_t *oset)'>
	^self notSimulated
!
chdir: path
	<c: 'int chdir(const char *path)'>
	^self notSimulated
!
execve: path argv: argv envp: envp
	<c: 'int execve(const char *path, char **argv, char **envp)'>
	^self notSimulated
!
exit: status
	<c: 'void _exit(int status)'>
	<noreturn>
	^self notSimulated
!
NSIG
	<cMacro: 'int NSIG'>
	^32
!
SIG_SETMASK
	<cMacro: 'int SIG_SETMASK'>
	^3
!
SIG_DFL
	<cMacro: 'sig_t SIG_DFL'>
	^FunctionPointer null
! !

ExternStruct subclass: #Sigaction
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!Sigaction class methodsFor: 'declaring'!
cName
	^'struct sigaction'
!
fields
	^#((sa_handler sig_t) (sa_mask sigset_t) (sa_flags int))
! !

ExternStruct subclass: #Winsize
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!Winsize class methodsFor: 'declaring'!
cName
	^'struct winsize'
!
fields
	^#((ws_row 'unsigned short') (ws_col 'unsigned short') (ws_xpixel 'unsigned short') (ws_ypixel 'unsigned short'))
! !
