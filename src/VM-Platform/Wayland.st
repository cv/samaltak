CLibrary subclass: #Wayland
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

Wayland comment: 'The libwayland-client calls of WaylandDesktop. Its protocol objects are void pointers here (struct wl_proxy underneath); requests are marshalled with wl_proxy_marshal_flags against interface descriptions WaylandDesktop builds, so no wayland-scanner output is needed. Not simulated.'!

!Wayland class methodsFor: 'declaring'!
headers
	^#('<wayland-client.h>')
!
targetOS
	^#linux
! !

!Wayland methodsFor: 'simulation'!
notSimulated
	^self error: 'Wayland is not simulated'
! !

!Wayland methodsFor: 'display'!
displayGetRegistry: display
	<c: 'void *wl_display_get_registry(void *display)'>
	^self notSimulated
!
displayRoundtrip: display
	<c: 'int wl_display_roundtrip(void *display)'>
	^self notSimulated
!
registry: registry bind: name interface: interface version: version
	<c: 'void *wl_registry_bind(void *registry, uint32_t name, const struct wl_interface *interface, uint32_t version)'>
	^self notSimulated
!
surfaceCommit: surface
	<c: 'void wl_surface_commit(void *surface)'>
	^self notSimulated
! !

!Wayland methodsFor: 'proxies'!
proxy: proxy addListener: implementation data: data
	<c: 'int wl_proxy_add_listener(void *proxy, void (**implementation)(void), void *data)'>
	^self notSimulated
!
proxyGetVersion: proxy
	<c: 'uint32_t wl_proxy_get_version(void *proxy)'>
	^self notSimulated
!
marshal: proxy opcode: opcode interface: interface version: version flags: flags
	<c: 'void *wl_proxy_marshal_flags(void *proxy, uint32_t opcode, const struct wl_interface *interface, uint32_t version, uint32_t flags, ...)'>
	^self notSimulated
!
marshal: proxy opcode: opcode interface: interface version: version flags: flags with: a
	<c: 'void *wl_proxy_marshal_flags(void *proxy, uint32_t opcode, const struct wl_interface *interface, uint32_t version, uint32_t flags, ...)'>
	^self notSimulated
!
marshal: proxy opcode: opcode interface: interface version: version flags: flags with: a with: b
	<c: 'void *wl_proxy_marshal_flags(void *proxy, uint32_t opcode, const struct wl_interface *interface, uint32_t version, uint32_t flags, ...)'>
	^self notSimulated
!
marshal: proxy opcode: opcode interface: interface version: version flags: flags with: a with: b with: c with: d
	<c: 'void *wl_proxy_marshal_flags(void *proxy, uint32_t opcode, const struct wl_interface *interface, uint32_t version, uint32_t flags, ...)'>
	^self notSimulated
!
marshal: proxy opcode: opcode interface: interface version: version flags: flags with: a with: b with: c with: d with: e
	<c: 'void *wl_proxy_marshal_flags(void *proxy, uint32_t opcode, const struct wl_interface *interface, uint32_t version, uint32_t flags, ...)'>
	^self notSimulated
!
WL_MARSHAL_FLAG_DESTROY
	<cMacro: 'uint32_t WL_MARSHAL_FLAG_DESTROY'>
	^1
! !

ExternStruct subclass: #WlInterface
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!WlInterface class methodsFor: 'declaring'!
cName
	^'struct wl_interface'
!
fields
	^#((name 'const char *') (version int) (method_count int) (methods 'const struct wl_message *')
		(event_count int) (events 'const struct wl_message *'))
! !

ExternStruct subclass: #WlMessage
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!WlMessage class methodsFor: 'declaring'!
cName
	^'struct wl_message'
!
fields
	^#((name 'const char *') (signature 'const char *') (types 'const struct wl_interface **'))
! !

VMPlatformModule subclass: #WaylandDesktop
	instanceVariableNames: 'wayland display registry layerShell shellVersion looked shellInterface surfaceInterface types registryListener surfaceListener'
	classVariableNames: 'ANCHOR_LEFT ANCHOR_TOP LAYER_BOTTOM SURFACE_ACK_CONFIGURE SURFACE_DESTROY SURFACE_SET_ANCHOR SURFACE_SET_MARGIN SURFACE_SET_SIZE'
	package: 'VM-Platform'!

WaylandDesktop comment: 'Desktop windows on Wayland (LinuxPlatformHost): an SDL window whose wl_surface SDL leaves without a role (SDL_PROP_WINDOW_CREATE_WAYLAND_SURFACE_ROLE_CUSTOM_BOOLEAN), made a wlr-layer-shell surface (zwlr_layer_shell_v1, which Hyprland, Sway and other wlroots compositors offer) on the bottom layer: above the wallpaper, below every window, anchored at the top left of the area other layer surfaces (the bar) leave free, at a margin that is its position, taking no keyboard focus. SDL still draws it and delivers its pointer events.

The interface descriptions are built at run time from the protocol''s XML (version 4: get_layer_surface and destroy; set_size, set_anchor, set_exclusive_zone, set_margin, set_keyboard_interactivity, get_popup, ack_configure, destroy, set_layer; the events configure and closed). Object types the client never checks are NULL in them. The layer surface is a property of its SDL window (samaltak.layer_surface). Everything runs on the VM thread, as SDL''s event pump, which dispatches the configure events, does.'!

!WaylandDesktop class methodsFor: 'declaring'!
declarations
	^#((wayland Wayland) (display 'void *') (registry 'void *') (layerShell 'void *') (shellVersion uint32_t) (looked bool)
		(shellInterface 'struct wl_interface *') (surfaceInterface 'struct wl_interface *') (types 'const struct wl_interface **')
		(registryListener 'void **') (surfaceListener 'void **'))
!
targetOS
	^#linux
!
initialize
	LAYER_BOTTOM := 1.
	ANCHOR_TOP := 1.
	ANCHOR_LEFT := 4.
	SURFACE_SET_SIZE := 0.
	SURFACE_SET_ANCHOR := 1.
	SURFACE_SET_MARGIN := 3.
	SURFACE_ACK_CONFIGURE := 6.
	SURFACE_DESTROY := 7
! !

!WaylandDesktop methodsFor: 'protocol'!
describeProtocol
	"The interfaces zwlr_layer_shell_v1 and zwlr_layer_surface_v1 (version 4), as wayland-scanner would emit them."
	<function>
	| shellRequests surfaceRequests surfaceEvents |
	types := self cCoerce: (libc calloc: 8 size: (self sizeof: 'void *')) to: 'const struct wl_interface **'.
	shellInterface := self cCoerce: (libc calloc: 1 size: (self sizeof: 'struct wl_interface')) to: 'struct wl_interface *'.
	surfaceInterface := self cCoerce: (libc calloc: 1 size: (self sizeof: 'struct wl_interface')) to: 'struct wl_interface *'.
	shellRequests := self cCoerce: (libc calloc: 2 size: (self sizeof: 'struct wl_message')) to: 'struct wl_message *'.
	surfaceRequests := self cCoerce: (libc calloc: 9 size: (self sizeof: 'struct wl_message')) to: 'struct wl_message *'.
	surfaceEvents := self cCoerce: (libc calloc: 2 size: (self sizeof: 'struct wl_message')) to: 'struct wl_message *'.
	"types: get_layer_surface's new id, then NULLs for every argument the client does not check"
	types at: 0 put: surfaceInterface.
	self message: shellRequests + 0 name: 'get_layer_surface' signature: 'no?ous' types: types.
	self message: shellRequests + 1 name: 'destroy' signature: '3' types: types + 1.
	self message: surfaceRequests + 0 name: 'set_size' signature: 'uu' types: types + 1.
	self message: surfaceRequests + 1 name: 'set_anchor' signature: 'u' types: types + 1.
	self message: surfaceRequests + 2 name: 'set_exclusive_zone' signature: 'i' types: types + 1.
	self message: surfaceRequests + 3 name: 'set_margin' signature: 'iiii' types: types + 1.
	self message: surfaceRequests + 4 name: 'set_keyboard_interactivity' signature: 'u' types: types + 1.
	self message: surfaceRequests + 5 name: 'get_popup' signature: 'o' types: types + 1.
	self message: surfaceRequests + 6 name: 'ack_configure' signature: 'u' types: types + 1.
	self message: surfaceRequests + 7 name: 'destroy' signature: '' types: types + 1.
	self message: surfaceRequests + 8 name: 'set_layer' signature: '2u' types: types + 1.
	self message: surfaceEvents + 0 name: 'configure' signature: 'uuu' types: types + 1.
	self message: surfaceEvents + 1 name: 'closed' signature: '' types: types + 1.
	shellInterface name: 'zwlr_layer_shell_v1'.
	shellInterface version: 4.
	shellInterface method_count: 2.
	shellInterface methods: shellRequests.
	shellInterface event_count: 0.
	shellInterface events: self null.
	surfaceInterface name: 'zwlr_layer_surface_v1'.
	surfaceInterface version: 4.
	surfaceInterface method_count: 9.
	surfaceInterface methods: surfaceRequests.
	surfaceInterface event_count: 2.
	surfaceInterface events: surfaceEvents.
	registryListener := self cCoerce: (libc calloc: 2 size: (self sizeof: 'void *')) to: 'void **'.
	registryListener at: 0 put: (self cCoerce: (self functionPointer: #registryGlobal:registry:name:interface:version:) to: 'void *').
	registryListener at: 1 put: (self cCoerce: (self functionPointer: #registryGlobalRemove:registry:name:) to: 'void *').
	surfaceListener := self cCoerce: (libc calloc: 2 size: (self sizeof: 'void *')) to: 'void **'.
	surfaceListener at: 0 put: (self cCoerce: (self functionPointer: #surfaceConfigure:surface:serial:width:height:) to: 'void *').
	surfaceListener at: 1 put: (self cCoerce: (self functionPointer: #surfaceClosed:surface:) to: 'void *')
!
message: m name: name signature: signature types: messageTypes
	m name: name.
	m signature: signature.
	m types: messageTypes
!
registryGlobal: data registry: aRegistry name: name interface: interface version: version
	"A global of the compositor: bind the layer shell."
	<function>
	<var: #data type: 'void *'>
	<var: #aRegistry type: 'void *'>
	<var: #name type: 'uint32_t'>
	<var: #interface type: 'const char *'>
	<var: #version type: 'uint32_t'>
	(layerShell isNull and: [(libc strcmp: interface with: 'zwlr_layer_shell_v1') = 0]) ifTrue: [
		shellVersion := version min: 4.
		layerShell := wayland registry: aRegistry bind: name interface: shellInterface version: shellVersion]
!
registryGlobalRemove: data registry: aRegistry name: name
	<function>
	<var: #data type: 'void *'>
	<var: #aRegistry type: 'void *'>
	<var: #name type: 'uint32_t'>
!
surfaceConfigure: data surface: surface serial: serial width: w height: h
	"The compositor's size for the layer surface of SDL window data: acknowledge it; SDL learns sizes only from SDL_SetWindowSize."
	<function>
	<var: #data type: 'void *'>
	<var: #surface type: 'void *'>
	<var: #serial type: 'uint32_t'>
	<var: #w type: 'uint32_t'>
	<var: #h type: 'uint32_t'>
	wayland marshal: surface opcode: SURFACE_ACK_CONFIGURE interface: self null version: (wayland proxyGetVersion: surface) flags: 0 with: serial.
	(w > 0 and: [h > 0]) ifTrue: [
		sdl setWindowSize: (self cCoerce: data to: 'SDL_Window *') w: w asInt32 h: h asInt32]
!
surfaceClosed: data surface: surface
	"The compositor took the layer surface away (its output went): it stays unmapped."
	<function>
	<var: #data type: 'void *'>
	<var: #surface type: 'void *'>
! !

!WaylandDesktop methodsFor: 'desktop windows'!
isAvailable
	"Whether SDL runs on Wayland and the compositor offers the layer shell (looked up once, after SDL_Init)."
	<function>
	| driver |
	looked ifTrue: [^layerShell notNull].
	looked := true.
	driver := sdl getCurrentVideoDriver.
	(driver isNull or: [(libc strcmp: driver with: 'wayland') ~= 0]) ifTrue: [^false].
	display := sdl getPointerProperty: sdl getGlobalProperties name: sdl SDL_PROP_GLOBAL_VIDEO_WAYLAND_WL_DISPLAY_POINTER default: self null.
	display isNull ifTrue: [^false].
	self describeProtocol.
	registry := wayland displayGetRegistry: display.
	registry isNull ifTrue: [^false].
	wayland proxy: registry addListener: (self cCoerce: registryListener to: 'void (**)(void)') data: self null.
	wayland displayRoundtrip: display.
	^layerShell notNull
!
openSurface: title width: w height: h flags: flags
	"A desktop window: an SDL window with a layer surface of w × h points, or NULL where there is no layer shell."
	<function>
	<returns: 'SDL_Window *'>
	<var: #flags type: 'SDL_WindowFlags'>
	| props sw surface layer |
	self isAvailable ifFalse: [^self null].
	props := sdl createProperties.
	sdl setStringProperty: props name: sdl SDL_PROP_WINDOW_CREATE_TITLE_STRING value: title.
	sdl setNumberProperty: props name: sdl SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER value: w asInt64.
	sdl setNumberProperty: props name: sdl SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER value: h asInt64.
	sdl setNumberProperty: props name: sdl SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER value: flags asInt64.
	sdl setBooleanProperty: props name: sdl SDL_PROP_WINDOW_CREATE_WAYLAND_SURFACE_ROLE_CUSTOM_BOOLEAN value: true.
	sw := sdl createWindowWithProperties: props.
	sdl destroyProperties: props.
	sw isNull ifTrue: [^self null].
	surface := sdl getPointerProperty: (sdl getWindowProperties: sw) name: sdl SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER default: self null.
	surface isNull ifTrue: [
		sdl destroyWindow: sw.
		^self null].
	"get_layer_surface: the new id, the surface, no output (the compositor's choice: the focused one), the layer, a namespace for window rules"
	layer := wayland marshal: layerShell opcode: 0 interface: surfaceInterface version: shellVersion flags: 0
		with: self null with: surface with: self null with: LAYER_BOTTOM asUInt32 with: 'samaltak-desktop'.
	layer isNull ifTrue: [
		sdl destroyWindow: sw.
		^self null].
	wayland proxy: layer addListener: (self cCoerce: surfaceListener to: 'void (**)(void)') data: sw.
	wayland marshal: layer opcode: SURFACE_SET_SIZE interface: self null version: shellVersion flags: 0 with: w asUInt32 with: h asUInt32.
	wayland marshal: layer opcode: SURFACE_SET_ANCHOR interface: self null version: shellVersion flags: 0 with: (ANCHOR_TOP bitOr: ANCHOR_LEFT) asUInt32.
	sdl setPointerProperty: (sdl getWindowProperties: sw) name: 'samaltak.layer_surface' value: layer.
	"The first commit, without a buffer, asks for the configure that has to be acknowledged before SDL presents."
	wayland surfaceCommit: surface.
	wayland displayRoundtrip: display.
	^sw
!
layerOf: sw
	<function>
	<var: #sw type: 'SDL_Window *'>
	looked ifFalse: [^self null].
	^sdl getPointerProperty: (sdl getWindowProperties: sw) name: 'samaltak.layer_surface' default: self null
!
surfaceOf: sw
	<function>
	<var: #sw type: 'SDL_Window *'>
	^sdl getPointerProperty: (sdl getWindowProperties: sw) name: sdl SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER default: self null
!
resizeSurface: sw width: w height: h
	"Answer false if sw is no desktop window."
	<function>
	<var: #sw type: 'SDL_Window *'>
	| layer |
	layer := self layerOf: sw.
	layer isNull ifTrue: [^false].
	wayland marshal: layer opcode: SURFACE_SET_SIZE interface: self null version: shellVersion flags: 0 with: w asUInt32 with: h asUInt32.
	sdl setWindowSize: sw w: w h: h.
	wayland surfaceCommit: (self surfaceOf: sw).
	^true
!
placeSurface: sw x: x y: y
	"Place desktop window sw x @ y points from the top left of the free area; answer false if it is none."
	<function>
	<var: #sw type: 'SDL_Window *'>
	| layer |
	layer := self layerOf: sw.
	layer isNull ifTrue: [^false].
	"set_margin: top, right, bottom, left"
	wayland marshal: layer opcode: SURFACE_SET_MARGIN interface: self null version: shellVersion flags: 0
		with: y asInt32 with: 0 asInt32 with: 0 asInt32 with: x asInt32.
	wayland surfaceCommit: (self surfaceOf: sw).
	^true
!
destroySurface: sw
	"Before SDL destroys window sw (and its wl_surface): destroy its layer surface first."
	<function>
	<var: #sw type: 'SDL_Window *'>
	| layer |
	layer := self layerOf: sw.
	layer isNull ifTrue: [^self].
	wayland marshal: layer opcode: SURFACE_DESTROY interface: self null version: shellVersion flags: wayland WL_MARSHAL_FLAG_DESTROY.
	sdl setPointerProperty: (sdl getWindowProperties: sw) name: 'samaltak.layer_surface' value: self null
! !
