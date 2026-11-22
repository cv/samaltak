VMPlatformModule subclass: #PlatformHost
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PlatformHost comment: 'What the platform layer does differently on each operating system: the display-refresh thread behind PlatformVsync, the process environment and a UTF-8 locale in it, socket setup, which keys are cmd and alt, the shader formats asked of SDL_GPU and compiling GLSL for them. DarwinPlatformHost and LinuxPlatformHost implement me under the same C names; the build links the one of its OS (targetOS).'!

!PlatformHost class methodsFor: 'declaring'!
isAbstractModule
	^self == PlatformHost
!
isInterface
	^self == PlatformHost
! !

!PlatformHost methodsFor: 'host'!
vsyncStart
	"Call vsync refreshed (from a thread of mine) at each display refresh from now on; false (and the error set) if that cannot be done."
	self subclassResponsibility
!
vsyncStop
	self subclassResponsibility
!
environment
	"The process's environment (NAME=value strings, NULL-terminated)."
	self subclassResponsibility
!
socketOpened: fd
	"A new socket: a write to it after the peer closed must fail (EPIPE), not kill the VM with SIGPIPE."
	self subclassResponsibility
!
cmdKeymod
	"The SDL modifier that is the image's cmd (PF_MOD_CMD)."
	self subclassResponsibility
!
altKeymod
	"The SDL modifier that is the image's alt (PF_MOD_ALT)."
	self subclassResponsibility
!
shaderFormats
	"The shader formats a GPU device is created for."
	self subclassResponsibility
!
utf8Ctype
	"The environment entry LC_CTYPE=… of a UTF-8 locale every system has."
	self subclassResponsibility
!
compileShader: source stage: stage size: sizeOut
	"SPIR-V compiled from GLSL source for stage (PF_STAGE_*, with SAMALTAK_VERTEX or SAMALTAK_FRAGMENT defined), malloc'd, its size in sizeOut; NULL with the error set (the compiler's log) if it does not compile."
	self subclassResponsibility
! !

PlatformHost subclass: #DarwinPlatformHost
	instanceVariableNames: 'coreVideo darwin displayLink'
	classVariableNames: ''
	package: 'VM-Platform'!

DarwinPlatformHost comment: 'The platform layer on macOS: a CVDisplayLink thread for the refreshes, _NSGetEnviron, SO_NOSIGPIPE, the command key as cmd, MSL shaders (SDL_GPU on Metal; GLSL is not compiled here).'!

!DarwinPlatformHost class methodsFor: 'declaring'!
declarations
	^#((coreVideo CoreVideo) (darwin DarwinPlatform) (displayLink CVDisplayLinkRef))
!
targetOS
	^#darwin
! !

!DarwinPlatformHost methodsFor: 'host'!
onRefresh: link now: now output: outputTime flags: flagsIn flagsOut: flagsOut context: context
	"The display link's thread."
	<function>
	vsync refreshed.
	^coreVideo kCVReturnSuccess
!
vsyncStart
	<export>
	| link |
	darwin installPaste.
	link := self local: 'CVDisplayLinkRef'.
	(coreVideo createWithActiveCGDisplays: link) ~= coreVideo kCVReturnSuccess ifTrue: [
		common setError: 'CVDisplayLinkCreateWithActiveCGDisplays failed'.
		^false].
	displayLink := link value.
	coreVideo setOutputCallback: displayLink callback: (self functionPointer: #onRefresh:now:output:flags:flagsOut:context:) userInfo: self null.
	coreVideo start: displayLink.
	^true
!
vsyncStop
	<export>
	coreVideo stop: displayLink.
	coreVideo release: displayLink.
	displayLink := self null
!
environment
	<export>
	^darwin environment value
!
socketOpened: fd
	<export>
	| one |
	one := self local: 'int'.
	one value: 1.
	posixSockets setsockopt: fd level: posixSockets SOL_SOCKET option: posixSockets SO_NOSIGPIPE value: one length: (self sizeof: 'int') asUInt32
!
cmdKeymod
	<export>
	^sdl SDL_KMOD_GUI
!
altKeymod
	<export>
	^sdl SDL_KMOD_ALT
!
shaderFormats
	<export>
	^sdlGpu SDL_GPU_SHADERFORMAT_MSL
!
utf8Ctype
	<export>
	^'LC_CTYPE=UTF-8'
!
compileShader: source stage: stage size: sizeOut
	<export>
	common setError: 'GLSL is compiled only on Linux (SDL_GPU on Vulkan); on Metal shaders are MSL'.
	^self null
! !

PlatformHost subclass: #LinuxPlatformHost
	instanceVariableNames: 'linux shaderc compiler vertexOptions fragmentOptions vsyncOn vsyncPeriodUs vsyncStarted'
	classVariableNames: ''
	package: 'VM-Platform'!

LinuxPlatformHost comment: 'The platform layer on Linux: a thread that wakes at the display''s refresh rate (absolute CLOCK_MONOTONIC deadlines) for the refreshes, environ, SIGPIPE ignored (there is no SO_NOSIGPIPE), the alt key as cmd and the super key as alt (the window manager keeps most super combinations), GLSL compiled to SPIR-V with shaderc (SDL_GPU on Vulkan).'!

!LinuxPlatformHost class methodsFor: 'declaring'!
declarations
	^#((linux LinuxPlatform) (shaderc Shaderc) (compiler shaderc_compiler_t) (vertexOptions shaderc_compile_options_t)
		(fragmentOptions shaderc_compile_options_t) (vsyncOn atomic_bool) (vsyncPeriodUs atomic_int) (vsyncStarted bool))
!
targetOS
	^#linux
! !

!LinuxPlatformHost methodsFor: 'host'!
vsyncStart
	<export>
	| mode rate t |
	mode := sdl getCurrentDisplayMode: sdl getPrimaryDisplay.
	rate := (mode notNull and: [mode refresh_rate > 0.0]) ifTrue: [mode refresh_rate asFloat] ifFalse: [60.0].
	self atomicStore: #vsyncPeriodUs value: (1000000.0 / rate) truncated asInt32.
	self atomicStore: #vsyncOn value: true.
	vsyncStarted ifFalse: [
		t := self local: 'pthread_t'.
		(posix pthreadCreate: t attributes: self null start: (self functionPointer: #vsyncRun:) argument: self null) ~= 0 ifTrue: [
			common setError: 'cannot start the vsync thread'.
			^false].
		posix pthreadDetach: t value.
		vsyncStarted := true].
	^true
!
vsyncStop
	<export>
	self atomicStore: #vsyncOn value: false
!
vsyncRun: arg
	"The vsync thread: refreshed every vsyncPeriodUs, on absolute deadlines (no drift; one that has fallen behind by more than a period starts again from now); naps of 100 ms while stopped."
	<function>
	| next now nap period |
	next := self local: 'Timespec'.
	now := self local: 'Timespec'.
	nap := self local: 'Timespec'.
	nap tv_nsec: 100000000.
	posix clockGettime: posix CLOCK_MONOTONIC into: next.
	[true] whileTrue: [
		(self atomicLoad: #vsyncOn)
			ifTrue: [
				period := (self atomicLoad: #vsyncPeriodUs) asInt64 * 1000.
				next tv_nsec: next tv_nsec + period.
				[next tv_nsec >= 1000000000] whileTrue: [
					next tv_sec: next tv_sec + 1.
					next tv_nsec: next tv_nsec - 1000000000].
				posix clockGettime: posix CLOCK_MONOTONIC into: now.
				((now tv_sec - next tv_sec) * 1000000000) + (now tv_nsec - next tv_nsec) > period ifTrue: [now copyStructFrom: next].
				linux clockNanosleep: posix CLOCK_MONOTONIC flags: linux TIMER_ABSTIME request: next remain: self null.
				vsync refreshed]
			ifFalse: [
				posixThreads nanosleep: nap remaining: self null.
				posix clockGettime: posix CLOCK_MONOTONIC into: next]].
	^self null
!
environment
	<export>
	^linux environ
!
socketOpened: fd
	<export>
	posixIO signal: posixIO SIGPIPE handler: posixIO SIG_IGN
!
cmdKeymod
	<export>
	^sdl SDL_KMOD_ALT
!
altKeymod
	<export>
	^sdl SDL_KMOD_GUI
!
shaderFormats
	<export>
	^sdlGpu SDL_GPU_SHADERFORMAT_SPIRV
!
utf8Ctype
	<export>
	^'LC_CTYPE=C.UTF-8'
!
compileShader: source stage: stage size: sizeOut
	<export>
	| fragment r n code |
	compiler isNull ifTrue: [
		compiler := shaderc compilerInitialize.
		vertexOptions := self optionsDefining: 'SAMALTAK_VERTEX'.
		fragmentOptions := self optionsDefining: 'SAMALTAK_FRAGMENT'].
	(compiler isNull or: [vertexOptions isNull or: [fragmentOptions isNull]]) ifTrue: [
		common setError: 'cannot initialize shaderc'.
		^self null].
	fragment := stage = PF_STAGE_FRAGMENT.
	r := shaderc compile: compiler source: source size: (libc strlen: source)
		kind: (fragment ifTrue: [shaderc shaderc_fragment_shader] ifFalse: [shaderc shaderc_vertex_shader])
		file: (fragment ifTrue: ['fragment'] ifFalse: ['vertex']) entry: 'main'
		options: (fragment ifTrue: [fragmentOptions] ifFalse: [vertexOptions]).
	r isNull ifTrue: [
		common setError: 'shaderc: out of memory'.
		^self null].
	(shaderc resultStatus: r) ~= shaderc shaderc_compilation_status_success ifTrue: [
		common setError: (shaderc resultErrorMessage: r).
		shaderc resultRelease: r.
		^self null].
	n := shaderc resultLength: r.
	code := libc malloc: n.
	code isNull
		ifTrue: [common setError: 'out of memory']
		ifFalse: [
			libc memcpy: code from: (shaderc resultBytes: r) size: n.
			sizeOut value: n].
	shaderc resultRelease: r.
	^code
!
optionsDefining: macro
	"Compile options for Vulkan: optimized, with macro defined (to 1)."
	| o |
	o := shaderc optionsInitialize.
	o notNull ifTrue: [
		shaderc options: o optimization: shaderc shaderc_optimization_level_performance.
		shaderc options: o define: macro length: (libc strlen: macro) value: '1' length: 1].
	^o
! !

CLibrary subclass: #DarwinPlatform
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

DarwinPlatform comment: 'The macOS calls of DarwinPlatformHost. Not simulated.'!

!DarwinPlatform class methodsFor: 'declaring'!
headers
	^#('<crt_externs.h>')
!
targetOS
	^#darwin
! !

!DarwinPlatform methodsFor: 'functions'!
environment
	"The environ of the process: the address of the environment array."
	<c: 'char ***_NSGetEnviron(void)'>
	^self error: 'not simulated'
! !

CLibrary subclass: #LinuxPlatform
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

LinuxPlatform comment: 'The Linux calls of LinuxPlatformHost (environ needs _GNU_SOURCE). Not simulated.'!

!LinuxPlatform class methodsFor: 'declaring'!
headers
	^#('<unistd.h>' '<time.h>')
!
targetOS
	^#linux
! !

!LinuxPlatform methodsFor: 'functions'!
environ
	<cVariable: 'char **environ'>
	^self error: 'not simulated'
!
clockNanosleep: clock flags: flags request: request remain: remain
	<c: 'int clock_nanosleep(clockid_t clock, int flags, const struct timespec *request, struct timespec *remain)'>
	^self error: 'not simulated'
!
TIMER_ABSTIME
	<cMacro: 'int TIMER_ABSTIME'>
	^1
! !

CLibrary subclass: #Shaderc
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

Shaderc comment: 'The shaderc C API (libshaderc_shared): GLSL to SPIR-V for LinuxPlatformHost. Not simulated.'!

!Shaderc class methodsFor: 'declaring'!
headers
	^#('<shaderc/shaderc.h>')
!
typedefs
	^#((shaderc_compiler_t 'void *') (shaderc_compile_options_t 'void *') (shaderc_compilation_result_t 'void *')
		(shaderc_shader_kind int32_t) (shaderc_compilation_status int32_t) (shaderc_optimization_level int32_t))
!
targetOS
	^#linux
! !

!Shaderc methodsFor: 'simulation'!
notSimulated
	^self error: 'shaderc is not simulated'
! !

!Shaderc methodsFor: 'compiling'!
compilerInitialize
	<c: 'shaderc_compiler_t shaderc_compiler_initialize(void)'>
	^self notSimulated
!
optionsInitialize
	<c: 'shaderc_compile_options_t shaderc_compile_options_initialize(void)'>
	^self notSimulated
!
options: options optimization: level
	<c: 'void shaderc_compile_options_set_optimization_level(shaderc_compile_options_t options, shaderc_optimization_level level)'>
	^self notSimulated
!
options: options define: name length: nameLength value: value length: valueLength
	<c: 'void shaderc_compile_options_add_macro_definition(shaderc_compile_options_t options, const char *name, size_t name_length, const char *value, size_t value_length)'>
	^self notSimulated
!
compile: compiler source: source size: size kind: kind file: fileName entry: entryName options: options
	<c: 'shaderc_compilation_result_t shaderc_compile_into_spv(shaderc_compiler_t compiler, const char *source, size_t size, shaderc_shader_kind kind, const char *file_name, const char *entry_name, shaderc_compile_options_t options)'>
	^self notSimulated
!
resultStatus: result
	<c: 'shaderc_compilation_status shaderc_result_get_compilation_status(shaderc_compilation_result_t result)'>
	^self notSimulated
!
resultLength: result
	<c: 'size_t shaderc_result_get_length(shaderc_compilation_result_t result)'>
	^self notSimulated
!
resultBytes: result
	<c: 'const char *shaderc_result_get_bytes(shaderc_compilation_result_t result)'>
	^self notSimulated
!
resultErrorMessage: result
	<c: 'const char *shaderc_result_get_error_message(shaderc_compilation_result_t result)'>
	^self notSimulated
!
resultRelease: result
	<c: 'void shaderc_result_release(shaderc_compilation_result_t result)'>
	^self notSimulated
!
shaderc_vertex_shader
	<cMacro: 'shaderc_shader_kind shaderc_vertex_shader'>
	^0
!
shaderc_fragment_shader
	<cMacro: 'shaderc_shader_kind shaderc_fragment_shader'>
	^1
!
shaderc_compilation_status_success
	<cMacro: 'shaderc_compilation_status shaderc_compilation_status_success'>
	^0
!
shaderc_optimization_level_performance
	<cMacro: 'shaderc_optimization_level shaderc_optimization_level_performance'>
	^2
! !

!DarwinPlatformHost class methodsFor: 'translation'!
cPreamble
	"CVDisplayLink is deprecated (CADisplayLink needs a view). Preserve event-local modifiers on shortcuts synthesized by clipboard managers."
	^'#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#ifdef __APPLE__
#include <SDL3/SDL.h>
#include <objc/runtime.h>
#include <objc/message.h>
static IMP samaltak_application_send_event;
static void samaltak_send_event(id receiver, SEL selector, id event)
{
    unsigned long type = ((unsigned long (*)(id, SEL))objc_msgSend)(event, sel_registerName("type"));
    if (type == 10 || type == 11) { /* NSEventTypeKeyDown / KeyUp */
        unsigned long flags = ((unsigned long (*)(id, SEL))objc_msgSend)(event, sel_registerName("modifierFlags"));
        SDL_Keymod saved = SDL_GetModState();
        SDL_Keymod mods = saved & ~(SDL_KMOD_SHIFT | SDL_KMOD_CTRL | SDL_KMOD_ALT | SDL_KMOD_GUI | SDL_KMOD_CAPS);
        if (flags & (1UL << 16)) mods |= SDL_KMOD_CAPS;
        if (flags & (1UL << 17)) mods |= (saved & SDL_KMOD_SHIFT) ? (saved & SDL_KMOD_SHIFT) : SDL_KMOD_LSHIFT;
        if (flags & (1UL << 18)) mods |= (saved & SDL_KMOD_CTRL) ? (saved & SDL_KMOD_CTRL) : SDL_KMOD_LCTRL;
        if (flags & (1UL << 19)) mods |= (saved & SDL_KMOD_ALT) ? (saved & SDL_KMOD_ALT) : SDL_KMOD_LALT;
        if (flags & (1UL << 20)) mods |= (saved & SDL_KMOD_GUI) ? (saved & SDL_KMOD_GUI) : SDL_KMOD_LGUI;
        SDL_SetModState(mods);
        ((void (*)(id, SEL, id))samaltak_application_send_event)(receiver, selector, event);
        SDL_SetModState(saved);
    } else {
        ((void (*)(id, SEL, id))samaltak_application_send_event)(receiver, selector, event);
    }
}
static void samaltak_install_paste(void)
{
    static bool installed = false;
    if (installed) return;
    Class application = objc_getClass("SDL3Application");
    Method method = application ? class_getInstanceMethod(application, sel_registerName("sendEvent:")) : NULL;
    if (!!method) return;
    samaltak_application_send_event = method_setImplementation(method, (IMP)samaltak_send_event);
    installed = true;
}
#endif'
! !


!DarwinPlatform methodsFor: 'paste'!
installPaste
	<c: 'void samaltak_install_paste(void)'>
	^self error: 'not simulated'
! !
