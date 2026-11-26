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

!PlatformHost methodsFor: 'desktop windows'!
openDesktopWindow: title width: w height: h flags: flags
	"A window on the desktop (PF_WIN_DESKTOP): above the wallpaper, below every window, placed by moveDesktopWindow:x:y:, never taking the keyboard focus; NULL where the system has none (PlatformWindows then opens an ordinary window)."
	self subclassResponsibility
!
resizeDesktopWindow: sw width: w height: h
	"Resize desktop window sw to w × h points; false if sw is no desktop window."
	self subclassResponsibility
!
moveDesktopWindow: sw x: x y: y
	"Place desktop window sw x @ y points from the top left of the area the bar and docks leave free; false if sw is no desktop window."
	self subclassResponsibility
!
raiseDesktopWindow: sw
	"Put desktop window sw above the other desktop windows; false if it is none."
	self subclassResponsibility
!
setDesktopWindowOpacity: sw permille: permille
	"Show desktop window sw at permille / 1000 opacity; false if it is none or the system cannot."
	self subclassResponsibility
!
desktopWindowCornerRadius: sw
	"The radius (points) the system rounds desktop window sw's corners with; 0 if they are square or sw is none."
	self subclassResponsibility
!
desktopMovedEvent
	"The SDL event type that reports where a desktop window was moved (data1: its window id, x and y as int32_t, malloc'd), once the system applied the move; 0 if none."
	self subclassResponsibility
!
closingDesktopWindow: sw
	"SDL window sw is about to be destroyed."
	self subclassResponsibility
! !

PlatformHost subclass: #DarwinPlatformHost
	instanceVariableNames: 'coreVideo darwin displayLink'
	classVariableNames: ''
	package: 'VM-Platform'!

DarwinPlatformHost comment: 'The platform layer on macOS: a CVDisplayLink thread for the refreshes, _NSGetEnviron, SO_NOSIGPIPE, the command key as cmd, MSL shaders (SDL_GPU on Metal; GLSL is not compiled here), desktop windows as borderless windows on every Space at the level just above Finder''s desktop.'!

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
	| link ref |
	darwin installPaste.
	link := self local: 'CVDisplayLinkRef'.
	(coreVideo createWithActiveCGDisplays: link) ~= coreVideo kCVReturnSuccess ifTrue: [
		common setError: 'CVDisplayLinkCreateWithActiveCGDisplays failed'.
		^false].
	ref := link value.
	(coreVideo setOutputCallback: ref callback: (self functionPointer: #onRefresh:now:output:flags:flagsOut:context:) userInfo: self null) ~= coreVideo kCVReturnSuccess ifTrue: [
		coreVideo release: ref.
		common setError: 'CVDisplayLinkSetOutputCallback failed'.
		^false].
	(coreVideo start: ref) ~= coreVideo kCVReturnSuccess ifTrue: [
		coreVideo release: ref.
		common setError: 'CVDisplayLinkStart failed'.
		^false].
	displayLink := ref.
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

!DarwinPlatformHost methodsFor: 'desktop windows'!
openDesktopWindow: title width: w height: h flags: flags
	"A borderless window that never takes the focus, on every Space at the level just above Finder's desktop; a transparent one (SDL_WINDOW_TRANSPARENT) lets the pointer through."
	<export>
	<returns: 'SDL_Window *'>
	<var: #flags type: 'SDL_WindowFlags'>
	| sw |
	sw := sdl createWindow: title width: w height: h
		flags: (flags bitOr: ((sdl SDL_WINDOW_BORDERLESS bitOr: sdl SDL_WINDOW_NOT_FOCUSABLE) bitOr: sdl SDL_WINDOW_HIDDEN)).
	sw isNull ifTrue: [^sw].
	darwin configureDesktop: sw passThrough: (flags bitAnd: sdl SDL_WINDOW_TRANSPARENT) ~= 0.
	sdl setHint: sdl SDL_HINT_WINDOW_ACTIVATE_WHEN_SHOWN value: '0'.
	sdl showWindow: sw.
	sdl resetHint: sdl SDL_HINT_WINDOW_ACTIVATE_WHEN_SHOWN.
	^sw
!
resizeDesktopWindow: sw width: w height: h
	"SDL resizes it."
	<export>
	<var: #sw type: 'SDL_Window *'>
	^false
!
moveDesktopWindow: sw x: x y: y
	"From the top left of the primary display's area the menu bar and the Dock leave free. The move is applied at once, so PF_EV_WINDOW_MOVED follows at once."
	<export>
	<var: #sw type: 'SDL_Window *'>
	| r ev |
	(darwin isDesktop: sw) ifFalse: [^false].
	r := self local: 'SDL_Rect'.
	(sdl getDisplayUsableBounds: sdl getPrimaryDisplay rect: r) ifFalse: [^false].
	(sdl setWindowPosition: sw x: r x + x y: r y + y) ifFalse: [^false].
	ev := self local: 'pf_event'.
	ev type: PF_EV_WINDOW_MOVED.
	ev timeMs: common nowMs.
	ev x: x asFloat.
	ev y: y asFloat.
	ev window: (windows fromSDLId: (sdl getWindowID: sw)).
	events push: ev.
	^true
!
raiseDesktopWindow: sw
	<export>
	<var: #sw type: 'SDL_Window *'>
	(darwin isDesktop: sw) ifFalse: [^false].
	((sdl getWindowFlags: sw) bitAnd: sdl SDL_WINDOW_HIDDEN) ~= 0 ifTrue: [
		sdl setHint: sdl SDL_HINT_WINDOW_ACTIVATE_WHEN_SHOWN value: '0'.
		sdl showWindow: sw.
		sdl resetHint: sdl SDL_HINT_WINDOW_ACTIVATE_WHEN_SHOWN].
	darwin orderFront: sw.
	^true
!
setDesktopWindowOpacity: sw permille: permille
	"SDL sets it."
	<export>
	<var: #sw type: 'SDL_Window *'>
	^false
!
desktopWindowCornerRadius: sw
	<export>
	<var: #sw type: 'SDL_Window *'>
	<returns: 'int'>
	^darwin cornerRadius: sw
!
desktopMovedEvent
	<export>
	<returns: 'Uint32'>
	^0
!
closingDesktopWindow: sw
	<export>
	<var: #sw type: 'SDL_Window *'>
! !

PlatformHost subclass: #LinuxPlatformHost
	instanceVariableNames: 'linux desktop shaderc compiler vertexOptions fragmentOptions vsyncOn vsyncPeriodUs vsyncStarted'
	classVariableNames: ''
	package: 'VM-Platform'!

LinuxPlatformHost comment: 'The platform layer on Linux: a thread that wakes at the display''s refresh rate (absolute CLOCK_MONOTONIC deadlines) for the refreshes, environ, SIGPIPE ignored (there is no SO_NOSIGPIPE), the alt key as cmd and the super key as alt (the window manager keeps most super combinations), GLSL compiled to SPIR-V with shaderc (SDL_GPU on Vulkan), desktop windows as Wayland layer surfaces (WaylandDesktop; none under X11).'!

!LinuxPlatformHost class methodsFor: 'declaring'!
declarations
	^#((linux LinuxPlatform) (desktop WaylandDesktop) (shaderc Shaderc) (compiler shaderc_compiler_t) (vertexOptions shaderc_compile_options_t)
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

!LinuxPlatformHost methodsFor: 'desktop windows'!
openDesktopWindow: title width: w height: h flags: flags
	<export>
	<returns: 'SDL_Window *'>
	<var: #flags type: 'SDL_WindowFlags'>
	^desktop openSurface: title width: w height: h flags: flags
!
resizeDesktopWindow: sw width: w height: h
	<export>
	<var: #sw type: 'SDL_Window *'>
	^desktop resizeSurface: sw width: w height: h
!
moveDesktopWindow: sw x: x y: y
	<export>
	<var: #sw type: 'SDL_Window *'>
	^desktop placeSurface: sw x: x y: y
!
raiseDesktopWindow: sw
	<export>
	<var: #sw type: 'SDL_Window *'>
	^desktop raiseSurface: sw
!
setDesktopWindowOpacity: sw permille: permille
	<export>
	<var: #sw type: 'SDL_Window *'>
	^desktop setSurfaceOpacity: sw permille: permille
!
desktopWindowCornerRadius: sw
	"Layer surfaces are square."
	<export>
	<var: #sw type: 'SDL_Window *'>
	<returns: 'int'>
	^0
!
desktopMovedEvent
	<export>
	<returns: 'Uint32'>
	^desktop movedEventType
!
closingDesktopWindow: sw
	<export>
	<var: #sw type: 'SDL_Window *'>
	desktop destroySurface: sw
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
#include <CoreGraphics/CoreGraphics.h>
static id samaltak_ns_window(SDL_Window *sw)
{
    return (id)SDL_GetPointerProperty(SDL_GetWindowProperties(sw), SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
}
static long samaltak_desktop_level(void)
{
    /* above Finder''s desktop (its icons take the clicks below them), below every window */
    return (long)CGWindowLevelForKey(kCGDesktopIconWindowLevelKey) + 1;
}
static double samaltak_system_corner_radius(void)
{
    /* the corners of the system''s titled windows (NSWindow''s _cornerRadius: 16 points on macOS 26, 10 before) */
    static double radius = -1;
    if (radius < 0) {
        SEL sel = sel_registerName("_cornerRadius");
        id window = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSWindow"), sel_registerName("alloc"));
        window = ((id (*)(id, SEL, CGRect, unsigned long, unsigned long, BOOL))objc_msgSend)(window,
            sel_registerName("initWithContentRect:styleMask:backing:defer:"), CGRectMake(0, 0, 100, 100), 1, 2, YES);
        radius = window && ((BOOL (*)(id, SEL, SEL))objc_msgSend)(window, sel_registerName("respondsToSelector:"), sel)
            ? ((double (*)(id, SEL))objc_msgSend)(window, sel) : 10;
        if (window) ((void (*)(id, SEL))objc_msgSend)(window, sel_registerName("release"));
    }
    return radius;
}
static void samaltak_round_corners(id window)
{
    /* clip the content (SDL''s Metal layer is a sublayer) to the system''s corners; the window is clear outside them */
    id view = ((id (*)(id, SEL))objc_msgSend)(window, sel_registerName("contentView"));
    id layer;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(view, sel_registerName("setWantsLayer:"), YES);
    layer = ((id (*)(id, SEL))objc_msgSend)(view, sel_registerName("layer"));
    ((void (*)(id, SEL, double))objc_msgSend)(layer, sel_registerName("setCornerRadius:"), samaltak_system_corner_radius());
    ((void (*)(id, SEL, BOOL))objc_msgSend)(layer, sel_registerName("setMasksToBounds:"), YES);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(window, sel_registerName("setOpaque:"), NO);
    ((void (*)(id, SEL, id))objc_msgSend)(window, sel_registerName("setBackgroundColor:"),
        ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSColor"), sel_registerName("clearColor")));
}
static int samaltak_corner_radius(SDL_Window *sw)
{
    id window = samaltak_ns_window(sw);
    id view = window ? ((id (*)(id, SEL))objc_msgSend)(window, sel_registerName("contentView")) : nil;
    id layer = view ? ((id (*)(id, SEL))objc_msgSend)(view, sel_registerName("layer")) : nil;
    return layer ? (int)((double (*)(id, SEL))objc_msgSend)(layer, sel_registerName("cornerRadius")) : 0;
}
static void samaltak_desktop_configure(SDL_Window *sw, bool passThrough)
{
    id window = samaltak_ns_window(sw);
    id app = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
    SEL prevents = sel_registerName("_setPreventsActivation:");
    if (!!window) return;
    ((void (*)(id, SEL, long))objc_msgSend)(window, sel_registerName("setLevel:"), samaltak_desktop_level());
    /* on every Space, left in place by Mission Control, not cycled through */
    ((void (*)(id, SEL, unsigned long))objc_msgSend)(window, sel_registerName("setCollectionBehavior:"), (1UL << 0) | (1UL << 4) | (1UL << 6));
    ((void (*)(id, SEL, BOOL))objc_msgSend)(window, sel_registerName("setHasShadow:"), NO);
    if (passThrough) ((void (*)(id, SEL, BOOL))objc_msgSend)(window, sel_registerName("setIgnoresMouseEvents:"), YES);
    else samaltak_round_corners(window);
    /* a process with desktop windows has no Dock icon and is not in the app switcher (NSApplicationActivationPolicyAccessory) */
    ((BOOL (*)(id, SEL, long))objc_msgSend)(app, sel_registerName("setActivationPolicy:"), 1);
    /* a click does not activate the process (and take the focus from the active app) */
    if (((BOOL (*)(id, SEL, SEL))objc_msgSend)(window, sel_registerName("respondsToSelector:"), prevents))
        ((void (*)(id, SEL, BOOL))objc_msgSend)(window, prevents, YES);
}
static bool samaltak_is_desktop(SDL_Window *sw)
{
    id window = samaltak_ns_window(sw);
    return window && ((long (*)(id, SEL))objc_msgSend)(window, sel_registerName("level")) == samaltak_desktop_level();
}
static void samaltak_order_front(SDL_Window *sw)
{
    id window = samaltak_ns_window(sw);
    if (window) ((void (*)(id, SEL))objc_msgSend)(window, sel_registerName("orderFrontRegardless"));
}
#endif'
! !


!DarwinPlatform methodsFor: 'paste'!
installPaste
	<c: 'void samaltak_install_paste(void)'>
	^self error: 'not simulated'
! !

!DarwinPlatform methodsFor: 'desktop windows'!
configureDesktop: sw passThrough: aBoolean
	"Make SDL window sw a desktop window: on every Space above Finder's desktop, below every window, without a shadow; the pointer passes through it if aBoolean, else its corners are rounded as the system's windows are."
	<c: 'void samaltak_desktop_configure(SDL_Window *sw, bool passThrough)'>
	^self error: 'not simulated'
!
isDesktop: sw
	<c: 'bool samaltak_is_desktop(SDL_Window *sw)'>
	^self error: 'not simulated'
!
orderFront: sw
	"Put sw above the other windows of its level, without activating the process."
	<c: 'void samaltak_order_front(SDL_Window *sw)'>
	^self error: 'not simulated'
!
cornerRadius: sw
	"The radius (points) sw's corners are rounded with, 0 if square."
	<c: 'int samaltak_corner_radius(SDL_Window *sw)'>
	^self error: 'not simulated'
! !
