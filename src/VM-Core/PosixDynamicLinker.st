CLibrary subclass: #PosixDynamicLinker
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

!PosixDynamicLinker class methodsFor: 'declaring'!
headers
	^#('<dlfcn.h>' '<unistd.h>')
! !

!PosixDynamicLinker methodsFor: 'dynamic linking'!
RTLD_NOW
	<cMacro: 'int RTLD_NOW'>
	"Zero means unavailable in the simulator."
	^0
!
RTLD_LOCAL
	<cMacro: 'int RTLD_LOCAL'>
	^0
!
open: path flags: flags
	<c: 'void *dlopen(const char *path, int flags)'>
	^CPointer null
!
symbolIn: handle named: name
	<c: 'void *dlsym(void *handle, const char *name)'>
	^CPointer null
! !

!PosixDynamicLinker methodsFor: 'credentials'!
uid
	<c: 'uint32_t getuid(void)'>
	^0
!
euid
	<c: 'uint32_t geteuid(void)'>
	^0
!
gid
	<c: 'uint32_t getgid(void)'>
	^0
!
egid
	<c: 'uint32_t getegid(void)'>
	^0
! !
