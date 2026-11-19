VMPlatformModule subclass: #UefiGpu
	instanceVariableNames: 'objs claims rsPixels rsW rsH rsFmt rsClipX0 rsClipY0 rsClipX1 rsClipY1 rsBlend rsTex rsTexW rsTexH rsTexFmt rsLinear rsRepeat rsOx rsOy rsSx rsSy rsTx rsTy rsMode rsColor rsOrgX rsOrgY'
	classVariableNames: 'SW_CLAIMS SW_K_BUF SW_K_CMD SW_K_DEV SW_K_FENCE SW_K_PASS SW_K_PIPE SW_K_SAMPLER SW_K_SHADER SW_K_SWAP SW_K_TEX SW_MAX_COORD SW_MAX_SIZE SW_STRIDE'
	package: 'VM-UEFI'!

UefiGpu comment: 'The GPU on UEFI (in place of PlatformGPU): a software device with PlatformGPU''s functions, handles and errors, which runs the Renderer''s uber-shader (Renderer class>>glslShaderSource) and nothing else (createPipeline fails for any other pipeline: user FragmentShaders show their error).

Everything executes when it is called: uploads, clears, draws, blits and downloads; a command buffer only groups them (its vertex uniforms, the swapchain textures it acquired, the time its work took); fences are done when they are made (fenceElapsed: that time, µs). Textures are malloc''d pixels (R8, RGBA8, BGRA8 rows, tightly packed). A claimed window has a back buffer (BGRA8, the window''s pixel size), the swapchain texture acquireSwapchain answers; submitting the command buffer that acquired it presents it (UefiWindows>>present:pixels:width:height:).

A draw runs the vertex stage as the shader does (vertex uniform slot 0: viewport, translation; the viewport transform) and rasterizes like a GPU: positions snapped to 1/256 pixel, pixel centres at +0.5, the top-left fill rule (adjacent quads neither overlap nor leave gaps), attributes interpolated at pixel centres, round to nearest into unorm8, blending exact up to that rounding. A quad (six equal vertices without bit 31 of mode, at a vertex index divisible by six) is an axis-aligned rectangle and takes a path over pixel rows: solid fills, glyph coverage, 1:1 images (nearest, or linear at texel centres) and the patterns without per-pixel arithmetic beyond the blend; other quads (scaled images, line coverage) shade per pixel, and the triangles of bit-31 vertices go through a general triangle rasterizer (per-row spans from the edge functions). Sampling is textureLod(tex, uv / size): nearest takes texel floor(uv), linear is bilinear with texel centres at +0.5 and 8-bit weights; clamp to edge, or repeat.

The raster state of the draw or blit being executed is in the rs variables (target, clip, blend, texture, sampler, the vertex transform, the primitive''s flat attributes).'!

!UefiGpu class methodsFor: 'declaring'!
declarations
	^#((objs 'pf_table[1]') (claims 'UefiGpuClaim[SW_CLAIMS]')
		(rsPixels 'uint8_t *') (rsW int64_t) (rsH int64_t) (rsFmt int32_t)
		(rsClipX0 int64_t) (rsClipY0 int64_t) (rsClipX1 int64_t) (rsClipY1 int64_t) (rsBlend int32_t)
		(rsTex 'uint8_t *') (rsTexW int64_t) (rsTexH int64_t) (rsTexFmt int32_t) (rsLinear bool) (rsRepeat bool)
		(rsOx double) (rsOy double) (rsSx double) (rsSy double) (rsTx double) (rsTy double)
		(rsMode uint32_t) (rsColor uint32_t) (rsOrgX double) (rsOrgY double))
!
targetOS
	^#uefi
!
replaces
	^PlatformGPU
!
initialize
	SW_K_DEV := 1.
	SW_K_SHADER := 2.
	SW_K_PIPE := 3.
	SW_K_TEX := 4.
	SW_K_SAMPLER := 5.
	SW_K_BUF := 6.
	SW_K_CMD := 7.
	SW_K_PASS := 8.
	SW_K_FENCE := 9.
	SW_K_SWAP := 10.
	SW_CLAIMS := 16.
	"the Renderer's vertex"
	SW_STRIDE := 40.
	"the largest texture side"
	SW_MAX_SIZE := 16384.
	"vertex positions are clamped to this many pixels from the origin"
	SW_MAX_COORD := 1048576
! !

!UefiGpu methodsFor: 'private'!
get: h kind: kind what: what
	"The object of handle h of kind; NULL (and the error set) if it is none."
	<function>
	<var: #h type: 'int32_t'>
	<var: #kind type: 'int'>
	<var: #what type: 'char *'>
	<returns: 'pf_obj *'>
	| o |
	o := common table: objs at: h kind: kind.
	o isNull ifTrue: [common setError: 'bad %s handle %d' with: what with: h].
	^o
!
device: h
	"Whether h is a device (else the error is set)."
	<function>
	<var: #h type: 'int32_t'>
	<returns: 'bool'>
	^(self get: h kind: SW_K_DEV what: 'device') notNull
!
target: tex
	"A texture or swapchain texture."
	<function>
	<var: #tex type: 'int32_t'>
	<returns: 'pf_obj *'>
	| o |
	o := common table: objs at: tex kind: -1.
	(o isNull or: [o kind ~= SW_K_TEX and: [o kind ~= SW_K_SWAP]]) ifTrue: [
		common setError: 'bad texture handle %d' with: tex.
		^self null].
	^o
!
renderPass: h
	<function>
	<var: #h type: 'int32_t'>
	<returns: 'UefiGpuPass *'>
	| o |
	o := self get: h kind: SW_K_PASS what: 'render pass'.
	o isNull ifTrue: [^self null].
	^self cCoerce: o ptr to: 'UefiGpuPass *'
!
commandOf: o
	"The command buffer record of handle entry o (a command buffer or one of its passes); NULL if none."
	<function>
	<var: #o type: 'pf_obj *'>
	<returns: 'UefiGpuCmd *'>
	| c |
	c := o.
	o kind = SW_K_PASS ifTrue: [c := common table: objs at: o i asInt32 kind: SW_K_CMD].
	(c isNull or: [c kind ~= SW_K_CMD]) ifTrue: [^self null].
	^self cCoerce: c ptr to: 'UefiGpuCmd *'
!
monoUs
	<function>
	<returns: 'int64_t'>
	| ts |
	ts := self local: 'struct timespec'.
	posix clockGettime: posix CLOCK_MONOTONIC into: ts.
	^(ts tv_sec * 1000000) + (ts tv_nsec quo: 1000)
!
charge: cmd since: t0
	"Add the time since t0 to the work of command buffer handle cmd."
	<function>
	<var: #cmd type: 'int32_t'>
	<var: #t0 type: 'int64_t'>
	| o c |
	o := common table: objs at: cmd kind: SW_K_CMD.
	o isNull ifTrue: [^self].
	c := self cCoerce: o ptr to: 'UefiGpuCmd *'.
	c busyUs: c busyUs + (self monoUs - t0)
!
isPassOrSwapchain: h of: cmd
	<function>
	<var: #h type: 'int32_t'>
	<var: #cmd type: 'int32_t'>
	<returns: 'bool'>
	^((objs v + h) kind = SW_K_SWAP or: [(objs v + h) kind = SW_K_PASS]) and: [(objs v + h) i = cmd asInt64]
!
drop: h
	"Remove handle h, freeing what it owns."
	<function>
	<var: #h type: 'int32_t'>
	| o |
	o := objs v + h.
	(o kind = SW_K_TEX or: [o kind = SW_K_BUF or: [o kind = SW_K_CMD or: [o kind = SW_K_PASS]]]) ifTrue: [libc free: o ptr].
	common table: objs remove: h
!
dropPassesOf: cmd
	"Remove the passes and swapchain textures of command buffer cmd."
	<function>
	<var: #cmd type: 'int32_t'>
	1 to: objs n - 1 do: [:k | (self isPassOrSwapchain: k asInt32 of: cmd) ifTrue: [self drop: k asInt32]]
!
claimOf: win
	"The claim of window win, NULL if none."
	<function>
	<var: #win type: 'int32_t'>
	<returns: 'UefiGpuClaim *'>
	0 to: SW_CLAIMS - 1 do: [:i | (claims + i) win = win ifTrue: [^claims + i]].
	^self null
!
unclaim: c
	"Release claim c and its back buffer (and swapchain textures that are it)."
	<function>
	<var: #c type: 'UefiGpuClaim *'>
	c pixels notNull ifTrue: [
		1 to: objs n - 1 do: [:k |
			((objs v + k) kind = SW_K_SWAP and: [(objs v + k) ptr = c pixels]) ifTrue: [common table: objs remove: k asInt32]]].
	c pixels notNull ifTrue: [libc free: c pixels].
	c pixels: self null.
	c win: 0.
	c dev: 0.
	c w: 0.
	c h: 0
!
floorOf: x
	"floor(x) as an integer (0 for NaN; clamped to +-2^50)."
	<function>
	<var: #x type: 'double'>
	<returns: 'int64_t'>
	| t |
	(x = x) ifFalse: [^0].
	x < -1.0e15 ifTrue: [^-1000000000000000].
	x > 1.0e15 ifTrue: [^1000000000000000].
	t := x truncated.
	^t asFloat > x ifTrue: [t - 1] ifFalse: [t]
!
snap: x
	"x (pixels) in fixed point, 1/256 pixel: round(x * 256), x clamped to +-SW_MAX_COORD."
	<function>
	<var: #x type: 'double'>
	<returns: 'int64_t'>
	| c |
	c := x.
	c < SW_MAX_COORD negated asFloat ifTrue: [c := SW_MAX_COORD negated asFloat].
	c > SW_MAX_COORD asFloat ifTrue: [c := SW_MAX_COORD asFloat].
	^self floorOf: (c * 256.0) + 0.5
!
floorDiv: a by: b
	"floor(a / b), b > 0."
	<function>
	<var: #a type: 'int64_t'>
	<var: #b type: 'int64_t'>
	<returns: 'int64_t'>
	| q |
	q := a quo: b.
	^(q * b) > a ifTrue: [q - 1] ifFalse: [q]
!
unorm8: x
	"A float channel as unorm8: round(clamp(x, 0, 1) * 255)."
	<function>
	<var: #x type: 'double'>
	<returns: 'int64_t'>
	(x > 0.0) ifFalse: [^0].
	x >= 1.0 ifTrue: [^255].
	^self floorOf: (x * 255.0) + 0.5
! !

!UefiGpu methodsFor: 'pixels'!
swapRB: v
	"RGBA8 <-> BGRA8."
	^((v bitAnd: 16rFF00FF00) bitOr: ((v >> 16) bitAnd: 16rFF)) bitOr: ((v bitAnd: 16rFF) asUInt64 << 16)
!
over: d color: c
	"Premultiplied source-over of c on d (8-bit lanes): c + d * (255 - c.a) / 255 per lane, rounded once, saturated. Two lanes at a time."
	| ia t rb ag ov |
	ia := 255 - (c >> 24) asInt64.
	t := ((d asInt64 bitAnd: 16rFF00FF) * ia) + 16r800080.
	rb := (((t + ((t >> 8) bitAnd: 16rFF00FF)) >> 8) bitAnd: 16rFF00FF) + (c asInt64 bitAnd: 16rFF00FF).
	t := (((d asInt64 >> 8) bitAnd: 16rFF00FF) * ia) + 16r800080.
	ag := (((t + ((t >> 8) bitAnd: 16rFF00FF)) >> 8) bitAnd: 16rFF00FF) + ((c asInt64 >> 8) bitAnd: 16rFF00FF).
	ov := rb bitAnd: 16r1000100.
	rb := (rb bitOr: ov - (ov >> 8)) bitAnd: 16rFF00FF.
	ov := ag bitAnd: 16r1000100.
	ag := (ag bitOr: ov - (ov >> 8)) bitAnd: 16rFF00FF.
	^(rb bitOr: ag << 8) asUInt32
!
over: d color: c k: k
	"Premultiplied source-over of c * k / 255 on d, exact: round((c k 255 + d (65025 - c.a k)) / 65025) per lane."
	| ia r ch |
	ia := 65025 - ((c >> 24) asInt64 * k).
	r := 0.
	0 to: 24 by: 8 do: [:s |
		ch := ((((c >> s) bitAnd: 255) asInt64 * k * 255) + (((d >> s) bitAnd: 255) asInt64 * ia) + 32512) quo: 65025.
		ch > 255 ifTrue: [ch := 255].
		r := r bitOr: ch << s].
	^r asUInt32
!
blend: d source: c k: k
	"The color c * k / 255 (k 0..255) blended onto d by the pipeline's blend (rsBlend), rounded once to unorm8."
	<function>
	<var: #d type: 'uint32_t'>
	<var: #c type: 'uint32_t'>
	<var: #k type: 'int64_t'>
	<returns: 'uint32_t'>
	| sa r ch |
	rsBlend = PF_BLEND_PREMULTIPLIED ifTrue: [^self over: d color: c k: k].
	r := 0.
	rsBlend = PF_BLEND_NONE ifTrue: [
		0 to: 24 by: 8 do: [:s |
			ch := ((((c >> s) bitAnd: 255) asInt64 * k) + 127) quo: 255.
			r := r bitOr: ch << s].
		^r asUInt32].
	"alpha: s.rgb * s.a + d.rgb * (1 - s.a), s.a + d.a * (1 - s.a)"
	sa := (c >> 24) asInt64 * k.
	0 to: 16 by: 8 do: [:s |
		ch := ((((c >> s) bitAnd: 255) asInt64 * k * sa * 255) + (((d >> s) bitAnd: 255) asInt64 * (65025 - sa) * 65025) + 2114125312) quo: 4228250625.
		ch > 255 ifTrue: [ch := 255].
		r := r bitOr: ch << s].
	ch := ((sa * 255) + ((d >> 24) asInt64 * (65025 - sa)) + 32512) quo: 65025.
	ch > 255 ifTrue: [ch := 255].
	^(r bitOr: ch << 24) asUInt32
!
packClear: rgba format: fmt
	"The clear color (floats) as a pixel of fmt."
	<function>
	<var: #rgba type: 'float *'>
	<var: #fmt type: 'int32_t'>
	<returns: 'uint32_t'>
	| r g b a |
	r := self unorm8: (rgba at: 0).
	g := self unorm8: (rgba at: 1).
	b := self unorm8: (rgba at: 2).
	a := self unorm8: (rgba at: 3).
	fmt = PF_TEX_R8 ifTrue: [^r asUInt32].
	fmt = PF_TEX_BGRA8 ifTrue: [^(((b bitOr: g << 8) bitOr: r << 16) bitOr: a << 24) asUInt32].
	^(((r bitOr: g << 8) bitOr: b << 16) bitOr: a << 24) asUInt32
!
fill: pixels count: n bytesPerPixel: bpp value: v
	<function>
	<var: #pixels type: 'uint8_t *'>
	<var: #n type: 'int64_t'>
	<var: #bpp type: 'int'>
	<var: #v type: 'uint32_t'>
	| p |
	bpp = 1 ifTrue: [
		libc memset: pixels value: (v bitAnd: 255) asInt32 size: n asUInt64.
		^self].
	p := self cCoerce: pixels to: 'uint32_t *'.
	0 to: n - 1 do: [:i | p at: i put: v]
! !

!UefiGpu methodsFor: 'devices'!
init
	"From platform_interface_init."
	<function>
!
bytesPerPixel: format
	<function>
	<var: #format type: 'int32_t'>
	<returns: 'int'>
	^format = PF_TEX_R8 ifTrue: [1] ifFalse: [4]
!
createDevice: debug
	<function>
	<var: #debug type: 'bool'>
	<returns: 'int32_t'>
	| h |
	h := common table: objs add: SW_K_DEV pointer: self null.
	h = 0 ifTrue: [
		common setError: 'out of memory'.
		^0].
	(objs v + h) dev: h.
	^h
!
shaderLanguage: dev
	"What createShader: takes: 'software' (the source is ignored); NULL on error."
	<function>
	<var: #dev type: 'int32_t'>
	<returns: 'char *'>
	(self device: dev) ifFalse: [^self null].
	^'software'
!
claimWindow: dev window: win
	<function>
	<var: #dev type: 'int32_t'>
	<var: #win type: 'int32_t'>
	<returns: 'bool'>
	| w h c |
	(self device: dev) ifFalse: [^false].
	w := self local: 'int'.
	h := self local: 'int'.
	(windows pixelSize: win width: w height: h) ifFalse: [^false].
	c := self claimOf: win.
	c notNull ifTrue: [
		c dev = dev ifTrue: [^true].
		common setError: 'the window is claimed by another device'.
		^false].
	c := self claimOf: 0.
	c isNull ifTrue: [
		common setError: 'too many claimed windows'.
		^false].
	c win: win.
	c dev: dev.
	^true
!
windowClosing: win
	"Release window win from the device that claimed it."
	<function>
	<var: #win type: 'int32_t'>
	| c |
	win = 0 ifTrue: [^self].
	c := self claimOf: win.
	c notNull ifTrue: [self unclaim: c]
!
swapchainFormat: dev window: win
	"PF_TEX_BGRA8 (the firmware's framebuffer order), 0 on error."
	<function>
	<var: #dev type: 'int32_t'>
	<var: #win type: 'int32_t'>
	<returns: 'int'>
	| w h |
	(self device: dev) ifFalse: [^0].
	w := self local: 'int'.
	h := self local: 'int'.
	(windows pixelSize: win width: w height: h) ifFalse: [^0].
	^PF_TEX_BGRA8
!
waitIdle: dev
	<function>
	<var: #dev type: 'int32_t'>
	<returns: 'bool'>
	^self device: dev
! !

!UefiGpu methodsFor: 'resources'!
createShader: dev source: source entry: entry stage: stage samplers: samplers uniformBuffers: uniformBuffers storageBuffers: storageBuffers storageTextures: storageTextures
	"The source is not compiled: a shader is its stage (fmt), samplers (w) and uniform buffers (h)."
	<function>
	<var: #dev type: 'int32_t'>
	<var: #source type: 'char *'>
	<var: #entry type: 'char *'>
	<var: #stage type: 'int32_t'>
	<var: #samplers type: 'int32_t'>
	<var: #uniformBuffers type: 'int32_t'>
	<var: #storageBuffers type: 'int32_t'>
	<var: #storageTextures type: 'int32_t'>
	<returns: 'int32_t'>
	| h o |
	(self device: dev) ifFalse: [^0].
	h := common table: objs add: SW_K_SHADER pointer: self null.
	h = 0 ifTrue: [
		common setError: 'out of memory'.
		^0].
	o := objs v + h.
	o dev: dev.
	o fmt: stage.
	o w: samplers.
	o h: uniformBuffers.
	^h
!
isRendererPipelineStride: stride attributes: attrs count: nattrs primitive: prim
	"Whether the vertex layout is the Renderer's: 40 bytes, float4@0 uint@16 uint@20 ubyte4norm@24 uint@28 float2@32, triangles."
	<function>
	<var: #stride type: 'int32_t'>
	<var: #attrs type: 'pf_vattr *'>
	<var: #nattrs type: 'int32_t'>
	<var: #prim type: 'int32_t'>
	<returns: 'bool'>
	| want |
	(stride = SW_STRIDE and: [nattrs = 6 and: [prim = PF_PRIM_TRIANGLES]]) ifFalse: [^false].
	want := self local: 'int32_t[12]'.
	want at: 0 put: PF_VA_FLOAT4.
	want at: 1 put: 0.
	want at: 2 put: PF_VA_UINT.
	want at: 3 put: 16.
	want at: 4 put: PF_VA_UINT.
	want at: 5 put: 20.
	want at: 6 put: PF_VA_UBYTE4_NORM.
	want at: 7 put: 24.
	want at: 8 put: PF_VA_UINT.
	want at: 9 put: 28.
	want at: 10 put: PF_VA_FLOAT2.
	want at: 11 put: 32.
	0 to: 5 do: [:i |
		((attrs at: i) format = (want at: 2 * i) and: [(attrs at: i) offset = (want at: (2 * i) + 1)]) ifFalse: [^false]].
	^true
!
createPipeline: dev vertexShader: vs fragmentShader: fs stride: stride attributes: attrs count: nattrs primitive: prim blend: blend targetFormat: targetFormat
	"Only the Renderer's pipeline (any blend, an RGBA8 or BGRA8 target): the blend in i, the target format in fmt."
	<function>
	<var: #dev type: 'int32_t'>
	<var: #vs type: 'int32_t'>
	<var: #fs type: 'int32_t'>
	<var: #stride type: 'int32_t'>
	<var: #attrs type: 'pf_vattr *'>
	<var: #nattrs type: 'int32_t'>
	<var: #prim type: 'int32_t'>
	<var: #blend type: 'int32_t'>
	<var: #targetFormat type: 'int32_t'>
	<returns: 'int32_t'>
	| v f h o |
	(self device: dev) ifFalse: [^0].
	v := self get: vs kind: SW_K_SHADER what: 'vertex shader'.
	f := self get: fs kind: SW_K_SHADER what: 'fragment shader'.
	(v isNull or: [f isNull]) ifTrue: [^0].
	(nattrs < 0 or: [nattrs > 16]) ifTrue: [
		common setError: 'bad attribute count'.
		^0].
	(targetFormat < PF_TEX_R8 or: [targetFormat > PF_TEX_BGRA8]) ifTrue: [
		common setError: 'bad target format %d' with: targetFormat.
		^0].
	(prim < 0 or: [prim > PF_PRIM_POINTS]) ifTrue: [
		common setError: 'bad primitive type %d' with: prim.
		^0].
	(blend < PF_BLEND_NONE or: [blend > PF_BLEND_PREMULTIPLIED]) ifTrue: [
		common setError: 'bad blend mode %d' with: blend.
		^0].
	((self isRendererPipelineStride: stride attributes: attrs count: nattrs primitive: prim)
		and: [v fmt = PF_STAGE_VERTEX and: [f fmt = PF_STAGE_FRAGMENT and: [targetFormat ~= PF_TEX_R8]]]) ifFalse: [
			common setError: 'the software GPU runs the Renderer''s shader only'.
			^0].
	h := common table: objs add: SW_K_PIPE pointer: self null.
	h = 0 ifTrue: [
		common setError: 'out of memory'.
		^0].
	o := objs v + h.
	o dev: dev.
	o fmt: targetFormat.
	o i: blend.
	^h
!
createTexture: dev width: w height: h format: format usage: usage
	"usage: PF_TEXUSE_* bits. The pixels start out zero."
	<function>
	<var: #dev type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<var: #format type: 'int32_t'>
	<var: #usage type: 'int32_t'>
	<returns: 'int32_t'>
	| p th o |
	(self device: dev) ifFalse: [^0].
	(w <= 0 or: [h <= 0 or: [w > SW_MAX_SIZE or: [h > SW_MAX_SIZE or: [format < PF_TEX_R8 or: [format > PF_TEX_BGRA8 or: [(usage bitAnd: 3) = 0]]]]]]) ifTrue: [
		common setError: 'bad texture parameters'.
		^0].
	p := libc calloc: w asUInt64 * h asUInt64 size: (self bytesPerPixel: format) asUInt64.
	p isNull ifTrue: [
		common setError: 'out of memory'.
		^0].
	th := common table: objs add: SW_K_TEX pointer: p.
	th = 0 ifTrue: [
		libc free: p.
		common setError: 'out of memory'.
		^0].
	o := objs v + th.
	o dev: dev.
	o w: w.
	o h: h.
	o fmt: format.
	^th
!
createSampler: dev linear: linear repeat: repeat
	"linear in w, repeat in h."
	<function>
	<var: #dev type: 'int32_t'>
	<var: #linear type: 'bool'>
	<var: #repeat type: 'bool'>
	<returns: 'int32_t'>
	| h o |
	(self device: dev) ifFalse: [^0].
	h := common table: objs add: SW_K_SAMPLER pointer: self null.
	h = 0 ifTrue: [
		common setError: 'out of memory'.
		^0].
	o := objs v + h.
	o dev: dev.
	o w: (linear ifTrue: [1] ifFalse: [0]).
	o h: (repeat ifTrue: [1] ifFalse: [0]).
	^h
!
createBuffer: dev usage: usage size: size
	"usage: PF_BUFUSE_VERTEX. The size in i."
	<function>
	<var: #dev type: 'int32_t'>
	<var: #usage type: 'int32_t'>
	<var: #size type: 'uint32_t'>
	<returns: 'int32_t'>
	| p h o |
	(self device: dev) ifFalse: [^0].
	(usage ~= PF_BUFUSE_VERTEX or: [size = 0]) ifTrue: [
		common setError: 'bad buffer parameters'.
		^0].
	p := libc calloc: 1 size: size asUInt64.
	p isNull ifTrue: [
		common setError: 'out of memory'.
		^0].
	h := common table: objs add: SW_K_BUF pointer: p.
	h = 0 ifTrue: [
		libc free: p.
		common setError: 'out of memory'.
		^0].
	o := objs v + h.
	o dev: dev.
	o i: size.
	^h
!
textureSize: tex width: w height: h format: format
	<function>
	<var: #tex type: 'int32_t'>
	<var: #w type: 'int *'>
	<var: #h type: 'int *'>
	<var: #format type: 'int *'>
	<returns: 'bool'>
	| o |
	o := self target: tex.
	o isNull ifTrue: [^false].
	w value: o w.
	h value: o h.
	format value: o fmt.
	^true
! !

!UefiGpu methodsFor: 'uploads'!
uploadBuffer: buf data: data count: n offset: dstOffset
	<function>
	<var: #buf type: 'int32_t'>
	<var: #data type: 'const void *'>
	<var: #n type: 'uint32_t'>
	<var: #dstOffset type: 'uint32_t'>
	<returns: 'bool'>
	| o |
	o := self get: buf kind: SW_K_BUF what: 'buffer'.
	o isNull ifTrue: [^false].
	n = 0 ifTrue: [^true].
	dstOffset asUInt64 + n asUInt64 > o i asUInt64 ifTrue: [
		common setError: 'upload out of buffer bounds'.
		^false].
	libc memcpy: (self cCoerce: o ptr to: 'uint8_t *') + dstOffset from: data size: n asUInt64.
	^true
!
uploadTexture: tex data: data length: len x: x y: y width: w height: h bytesPerRow: bytesPerRow
	<function>
	<var: #tex type: 'int32_t'>
	<var: #data type: 'const void *'>
	<var: #len type: 'size_t'>
	<var: #x type: 'int32_t'>
	<var: #y type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<var: #bytesPerRow type: 'int32_t'>
	<returns: 'bool'>
	| o bpp row dst src |
	o := self get: tex kind: SW_K_TEX what: 'texture'.
	o isNull ifTrue: [^false].
	bpp := (self bytesPerPixel: o fmt) asUInt64.
	row := w asUInt64 * bpp.
	(x < 0 or: [y < 0 or: [w <= 0 or: [h <= 0 or: [x + w > o w or: [y + h > o h
		or: [bytesPerRow < 0 or: [bytesPerRow asUInt64 < row or: [len < (((h - 1) asUInt64 * bytesPerRow asUInt64) + row)]]]]]]]]) ifTrue: [
			common setError: 'bad texture upload region'.
			^false].
	dst := self cCoerce: o ptr to: 'uint8_t *'.
	src := self cCoerce: data to: 'const uint8_t *'.
	0 to: h - 1 do: [:r |
		libc memcpy: dst + ((((y + r) asUInt64 * o w asUInt64) + x asUInt64) * bpp) from: src + (r asUInt64 * bytesPerRow asUInt64) size: row].
	^true
!
download: tex x: x y: y width: w height: h into: dst length: dstLen
	"Synchronous; BGRA8 is converted to RGBA8."
	<function>
	<var: #tex type: 'int32_t'>
	<var: #x type: 'int32_t'>
	<var: #y type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<var: #dst type: 'void *'>
	<var: #dstLen type: 'size_t'>
	<returns: 'bool'>
	| o bpp n row s t d |
	o := self get: tex kind: SW_K_TEX what: 'texture'.
	o isNull ifTrue: [^false].
	bpp := (self bytesPerPixel: o fmt) asUInt64.
	n := (w asUInt64 * h asUInt64) * bpp.
	(x < 0 or: [y < 0 or: [w <= 0 or: [h <= 0 or: [x + w > o w or: [y + h > o h or: [dstLen < n]]]]]]) ifTrue: [
		common setError: 'bad download region'.
		^false].
	row := w asUInt64 * bpp.
	d := self cCoerce: dst to: 'uint8_t *'.
	0 to: h - 1 do: [:r |
		s := (self cCoerce: o ptr to: 'uint8_t *') + ((((y + r) asUInt64 * o w asUInt64) + x asUInt64) * bpp).
		o fmt = PF_TEX_BGRA8
			ifTrue: [
				t := self cCoerce: d + (r asUInt64 * row) to: 'uint32_t *'.
				0 to: w - 1 do: [:i | t at: i put: (self swapRB: ((self cCoerce: s to: 'uint32_t *') at: i))]]
			ifFalse: [libc memcpy: d + (r asUInt64 * row) from: s size: row]].
	^true
! !

!UefiGpu methodsFor: 'command buffers and passes'!
acquireCommandBuffer: dev
	"Its record: the vertex uniforms, the time its work took."
	<function>
	<var: #dev type: 'int32_t'>
	<returns: 'int32_t'>
	| c h |
	(self device: dev) ifFalse: [^0].
	c := libc calloc: 1 size: (self sizeof: 'UefiGpuCmd').
	c isNull ifTrue: [
		common setError: 'out of memory'.
		^0].
	h := common table: objs add: SW_K_CMD pointer: c.
	h = 0 ifTrue: [
		libc free: c.
		common setError: 'out of memory'.
		^0].
	(objs v + h) dev: dev.
	^h
!
acquireSwapchain: cmd window: win width: w height: h
	"The back buffer of window win (BGRA8, the window's pixel size), presented when cmd is submitted. 0: none available (not an error if no error is set)."
	<function>
	<var: #cmd type: 'int32_t'>
	<var: #win type: 'int32_t'>
	<var: #w type: 'int *'>
	<var: #h type: 'int *'>
	<returns: 'int32_t'>
	| c cl wp hp sh o p |
	c := self get: cmd kind: SW_K_CMD what: 'command buffer'.
	common setError: ''.
	c isNull ifTrue: [^0].
	cl := self claimOf: win.
	(win = 0 or: [cl isNull]) ifTrue: [
		common setError: 'the window is not claimed'.
		^0].
	wp := self local: 'int'.
	hp := self local: 'int'.
	(windows pixelSize: win width: wp height: hp) ifFalse: [^0].
	(wp value <= 0 or: [hp value <= 0]) ifTrue: [^0].
	(cl pixels isNull or: [cl w ~= wp value or: [cl h ~= hp value]]) ifTrue: [
		p := self cCoerce: (libc calloc: wp value asUInt64 * hp value asUInt64 size: 4) to: 'uint8_t *'.
		p isNull ifTrue: [
			common setError: 'out of memory'.
			^0].
		1 to: objs n - 1 do: [:k |
			((objs v + k) kind = SW_K_SWAP and: [(objs v + k) ptr = cl pixels]) ifTrue: [(objs v + k) ptr: p]].
		cl pixels notNull ifTrue: [libc free: cl pixels].
		cl pixels: p.
		cl w: wp value.
		cl h: hp value].
	sh := common table: objs add: SW_K_SWAP pointer: cl pixels.
	sh = 0 ifTrue: [
		common setError: 'out of memory'.
		^0].
	o := objs v + sh.
	o dev: c dev.
	o w: cl w.
	o h: cl h.
	o fmt: PF_TEX_BGRA8.
	o i: cmd.
	w value: cl w.
	h value: cl h.
	^sh
!
beginPass: cmd target: tex clear: clear
	"clear: RGBA, NULL = load. Clears now."
	<function>
	<var: #cmd type: 'int32_t'>
	<var: #tex type: 'int32_t'>
	<var: #clear type: 'float *'>
	<returns: 'int'>
	| c t p h t0 |
	c := self get: cmd kind: SW_K_CMD what: 'command buffer'.
	t := self target: tex.
	(c isNull or: [t isNull]) ifTrue: [^0].
	p := self cCoerce: (libc calloc: 1 size: (self sizeof: 'UefiGpuPass')) to: 'UefiGpuPass *'.
	p isNull ifTrue: [
		common setError: 'out of memory'.
		^0].
	h := common table: objs add: SW_K_PASS pointer: p.
	h = 0 ifTrue: [
		libc free: p.
		common setError: 'out of memory'.
		^0].
	(objs v + h) dev: c dev.
	(objs v + h) i: cmd.
	p cmd: cmd.
	p target: tex.
	p vx: 0.0.
	p vy: 0.0.
	p vw: t w asFloat.
	p vh: t h asFloat.
	p sx: 0.
	p sy: 0.
	p sw: t w.
	p sh: t h.
	clear notNull ifTrue: [
		t0 := self monoUs.
		self fill: (self cCoerce: t ptr to: 'uint8_t *') count: t w asInt64 * t h asInt64 bytesPerPixel: (self bytesPerPixel: t fmt) value: (self packClear: clear format: t fmt).
		self charge: cmd since: t0].
	^h
!
setViewport: pass x: x y: y width: w height: h
	<function>
	<var: #pass type: 'int32_t'>
	<var: #x type: 'float'>
	<var: #y type: 'float'>
	<var: #w type: 'float'>
	<var: #h type: 'float'>
	<returns: 'bool'>
	| p |
	p := self renderPass: pass.
	p isNull ifTrue: [^false].
	p vx: x.
	p vy: y.
	p vw: w.
	p vh: h.
	^true
!
setScissor: pass x: x y: y width: w height: h
	<function>
	<var: #pass type: 'int32_t'>
	<var: #x type: 'int32_t'>
	<var: #y type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<returns: 'bool'>
	| p |
	p := self renderPass: pass.
	p isNull ifTrue: [^false].
	p sx: x.
	p sy: y.
	p sw: w.
	p sh: h.
	^true
!
bindPipeline: pass pipeline: pipe
	<function>
	<var: #pass type: 'int32_t'>
	<var: #pipe type: 'int32_t'>
	<returns: 'bool'>
	| p o |
	p := self renderPass: pass.
	p isNull ifTrue: [^false].
	o := self get: pipe kind: SW_K_PIPE what: 'pipeline'.
	o isNull ifTrue: [^false].
	p pipe: pipe.
	p blend: o i asInt32.
	^true
!
bindVertexBuffer: pass slot: slot buffer: buf offset: offset
	"The pipeline reads slot 0 only."
	<function>
	<var: #pass type: 'int32_t'>
	<var: #slot type: 'int32_t'>
	<var: #buf type: 'int32_t'>
	<var: #offset type: 'uint32_t'>
	<returns: 'bool'>
	| p o |
	p := self renderPass: pass.
	p isNull ifTrue: [^false].
	o := self get: buf kind: SW_K_BUF what: 'buffer'.
	o isNull ifTrue: [^false].
	slot = 0 ifTrue: [
		p vbuf: buf.
		p voff: offset].
	^true
!
bindTexture: pass slot: slot texture: tex sampler: sampler
	"The shader samples slot 0 only."
	<function>
	<var: #pass type: 'int32_t'>
	<var: #slot type: 'int32_t'>
	<var: #tex type: 'int32_t'>
	<var: #sampler type: 'int32_t'>
	<returns: 'bool'>
	| p t s |
	p := self renderPass: pass.
	p isNull ifTrue: [^false].
	t := self get: tex kind: SW_K_TEX what: 'texture'.
	s := self get: sampler kind: SW_K_SAMPLER what: 'sampler'.
	(t isNull or: [s isNull]) ifTrue: [^false].
	slot = 0 ifTrue: [
		p tex: tex.
		p linear: s w ~= 0.
		p wrap: s h ~= 0].
	^true
!
pushUniforms: cmdOrPass stage: stage slot: slot data: data count: n
	"The shader reads vertex slot 0 only (viewport, translation: four floats)."
	<function>
	<var: #cmdOrPass type: 'int32_t'>
	<var: #stage type: 'int32_t'>
	<var: #slot type: 'int32_t'>
	<var: #data type: 'const void *'>
	<var: #n type: 'uint32_t'>
	<returns: 'bool'>
	| o c |
	o := common table: objs at: cmdOrPass kind: -1.
	c := o isNull ifTrue: [self null] ifFalse: [self commandOf: o].
	c isNull ifTrue: [
		common setError: 'bad command buffer handle %d' with: cmdOrPass.
		^false].
	(stage = PF_STAGE_VERTEX and: [slot = 0]) ifTrue: [
		libc memcpy: c vu from: data size: (n < 16 ifTrue: [n] ifFalse: [16]) asUInt64].
	^true
!
endPass: pass
	<function>
	<var: #pass type: 'int32_t'>
	<returns: 'bool'>
	(self renderPass: pass) isNull ifTrue: [^false].
	self drop: pass.
	^true
!
blit: cmd source: src rect: sr destination: dst rect: dr linear: linear
	"Rects: x y w h. Now, like SDL_BlitGPUTexture: each destination pixel of dr samples the source at its centre mapped into sr (nearest, or linear; clamped to the source's edge), converted to the destination's format."
	<function>
	<var: #cmd type: 'int32_t'>
	<var: #src type: 'int32_t'>
	<var: #sr type: 'int *'>
	<var: #dst type: 'int32_t'>
	<var: #dr type: 'int *'>
	<var: #linear type: 'bool'>
	<returns: 'bool'>
	| c s t t0 sx sy sw sh dx dy dw dh x0 y0 x1 y1 sbpp tbpp same d v u p |
	c := self get: cmd kind: SW_K_CMD what: 'command buffer'.
	s := self get: src kind: SW_K_TEX what: 'texture'.
	t := self target: dst.
	(c isNull or: [s isNull or: [t isNull]]) ifTrue: [^false].
	sx := (sr at: 0) asInt64.
	sy := (sr at: 1) asInt64.
	sw := (sr at: 2) asInt64.
	sh := (sr at: 3) asInt64.
	dx := (dr at: 0) asInt64.
	dy := (dr at: 1) asInt64.
	dw := (dr at: 2) asInt64.
	dh := (dr at: 3) asInt64.
	(sw <= 0 or: [sh <= 0 or: [dw <= 0 or: [dh <= 0]]]) ifTrue: [^true].
	t0 := self monoUs.
	x0 := dx max: 0.
	y0 := dy max: 0.
	x1 := dx + dw.
	x1 := x1 min: t w asInt64.
	y1 := dy + dh.
	y1 := y1 min: t h asInt64.
	sbpp := (self bytesPerPixel: s fmt) asInt64.
	tbpp := (self bytesPerPixel: t fmt) asInt64.
	rsTex := self cCoerce: s ptr to: 'uint8_t *'.
	rsTexW := s w.
	rsTexH := s h.
	rsTexFmt := s fmt.
	rsLinear := linear.
	rsRepeat := false.
	rsFmt := PF_TEX_RGBA8.
	same := sw = dw and: [sh = dh and: [sx >= 0 and: [sy >= 0 and: [sx + sw <= rsTexW and: [sy + sh <= rsTexH]]]]].
	y0 to: y1 - 1 do: [:py |
		d := (self cCoerce: t ptr to: 'uint8_t *') + ((((py * t w asInt64) + x0) * tbpp) asUInt64).
		same
			ifTrue: [
				self convert: d format: t fmt
					from: rsTex + (((((py - dy + sy) * rsTexW) + (x0 - dx + sx)) * sbpp) asUInt64) format: s fmt
					count: x1 - x0]
			ifFalse: [
				v := sy asFloat + ((((py asFloat + 0.5) - dy asFloat) * sh asFloat) / dh asFloat).
				x0 to: x1 - 1 do: [:px |
					u := sx asFloat + ((((px asFloat + 0.5) - dx asFloat) * sw asFloat) / dw asFloat).
					p := self sampleU: u v: v.
					t fmt = PF_TEX_R8
						ifTrue: [d at: px - x0 put: (p bitAnd: 255)]
						ifFalse: [
							(self cCoerce: d to: 'uint32_t *')
								at: px - x0
								put: (t fmt = PF_TEX_BGRA8 ifTrue: [(self swapRB: p) asUInt32] ifFalse: [p])]]]].
	self charge: cmd since: t0.
	^true
!
convert: d format: df from: s format: sf count: n
	"n pixels of format sf to format df (R8 reads as (r, 0, 0, 1); to R8 is the red channel)."
	<function>
	<var: #d type: 'uint8_t *'>
	<var: #df type: 'int32_t'>
	<var: #s type: 'uint8_t *'>
	<var: #sf type: 'int32_t'>
	<var: #n type: 'int64_t'>
	| d4 s4 |
	sf = df ifTrue: [
		libc memcpy: d from: s size: (n * (self bytesPerPixel: sf) asInt64) asUInt64.
		^self].
	d4 := self cCoerce: d to: 'uint32_t *'.
	s4 := self cCoerce: s to: 'uint32_t *'.
	sf = PF_TEX_R8 ifTrue: [
		df = PF_TEX_BGRA8
			ifTrue: [0 to: n - 1 do: [:i | d4 at: i put: ((s at: i) asUInt64 << 16) asUInt32 + 16rFF000000]]
			ifFalse: [0 to: n - 1 do: [:i | d4 at: i put: (s at: i) asUInt32 + 16rFF000000]].
		^self].
	df = PF_TEX_R8 ifTrue: [
		sf = PF_TEX_BGRA8
			ifTrue: [0 to: n - 1 do: [:i | d at: i put: (s at: (i * 4) + 2)]]
			ifFalse: [0 to: n - 1 do: [:i | d at: i put: (s at: i * 4)]].
		^self].
	0 to: n - 1 do: [:i | d4 at: i put: (self swapRB: (s4 at: i)) asUInt32]
!
submit: cmd fence: wantFence ok: ok
	"Present the swapchain textures cmd acquired; the fence handle or 0 (done already: i is the time cmd's work took, µs); ok tells whether it went well."
	<function>
	<var: #cmd type: 'int32_t'>
	<var: #wantFence type: 'bool'>
	<var: #ok type: 'bool *'>
	<returns: 'int'>
	| o c busy dev cl h |
	o := self get: cmd kind: SW_K_CMD what: 'command buffer'.
	ok value: false.
	o isNull ifTrue: [^0].
	c := self cCoerce: o ptr to: 'UefiGpuCmd *'.
	busy := c busyUs.
	dev := o dev.
	1 to: objs n - 1 do: [:k |
		((objs v + k) kind = SW_K_SWAP and: [(objs v + k) i = cmd asInt64]) ifTrue: [
			0 to: SW_CLAIMS - 1 do: [:j |
				cl := claims + j.
				(cl win ~= 0 and: [cl pixels = (objs v + k) ptr]) ifTrue: [
					windows present: cl win pixels: cl pixels width: cl w height: cl h]]]].
	self dropPassesOf: cmd.
	self drop: cmd.
	ok value: true.
	wantFence ifFalse: [^0].
	h := common table: objs add: SW_K_FENCE pointer: self null.
	h = 0 ifTrue: [
		ok value: false.
		common setError: 'out of memory'.
		^0].
	(objs v + h) dev: dev.
	(objs v + h) i: busy.
	^h
! !

!UefiGpu methodsFor: 'fences'!
fenceElapsed: fence
	"µs of work of the fence's command buffer; -2 bad handle."
	<function>
	<var: #fence type: 'int32_t'>
	<returns: 'int64_t'>
	| o |
	o := self get: fence kind: SW_K_FENCE what: 'fence'.
	o isNull ifTrue: [^-2].
	^o i
!
waitFence: fence
	<function>
	<var: #fence type: 'int32_t'>
	<returns: 'bool'>
	^(self get: fence kind: SW_K_FENCE what: 'fence') notNull
!
fenceDone: fence
	"1 done, -1 error."
	<function>
	<var: #fence type: 'int32_t'>
	<returns: 'int'>
	^(self get: fence kind: SW_K_FENCE what: 'fence') isNull ifTrue: [-1] ifFalse: [1]
! !

!UefiGpu methodsFor: 'release'!
release: h
	"Release the object of handle h (not a device)."
	<function>
	<var: #h type: 'int32_t'>
	(objs v + h) kind = SW_K_CMD ifTrue: [self dropPassesOf: h].
	self drop: h
!
releaseDevice: dh
	<function>
	<var: #dh type: 'int32_t'>
	1 to: objs n - 1 do: [:h |
		(h ~= dh asInt64 and: [(objs v + h) kind = SW_K_CMD and: [(objs v + h) dev = dh]]) ifTrue: [self release: h asInt32]].
	1 to: objs n - 1 do: [:h |
		(h ~= dh asInt64 and: [(objs v + h) kind ~= 0 and: [(objs v + h) dev = dh]]) ifTrue: [self release: h asInt32]].
	0 to: SW_CLAIMS - 1 do: [:i | ((claims + i) win ~= 0 and: [(claims + i) dev = dh]) ifTrue: [self unclaim: claims + i]].
	common table: objs remove: dh
!
releaseHandle: h
	"A device releases everything created on it; passes and swapchain textures end with their command buffer."
	<function>
	<var: #h type: 'int32_t'>
	<returns: 'bool'>
	| o |
	o := common table: objs at: h kind: -1.
	o isNull ifTrue: [
		common setError: 'bad GPU handle %d' with: h.
		^false].
	(o kind = SW_K_PASS or: [o kind = SW_K_SWAP]) ifTrue: [
		common setError: 'pass/swapchain handles end with their command buffer'.
		^false].
	o kind = SW_K_DEV
		ifTrue: [self releaseDevice: h]
		ifFalse: [self release: h].
	^true
!
shutdown
	<function>
	1 to: objs n - 1 do: [:h | (objs v + h) kind = SW_K_DEV ifTrue: [self releaseDevice: h asInt32]]
!
handleCounts: out
	"devices shaders pipelines textures samplers buffers fences"
	<function>
	<var: #out type: 'int64_t *'>
	out at: 0 put: (common table: objs count: SW_K_DEV).
	out at: 1 put: (common table: objs count: SW_K_SHADER).
	out at: 2 put: (common table: objs count: SW_K_PIPE).
	out at: 3 put: (common table: objs count: SW_K_TEX).
	out at: 4 put: (common table: objs count: SW_K_SAMPLER).
	out at: 5 put: (common table: objs count: SW_K_BUF).
	out at: 6 put: (common table: objs count: SW_K_FENCE)
! !

!UefiGpu methodsFor: 'drawing'!
draw: pass vertices: vertexCount first: firstVertex
	"Run the pipeline on the vertices now: triangles, in order; six equal vertices from an index divisible by six (without bit 31 of mode) as one quad."
	<function>
	<var: #pass type: 'int32_t'>
	<var: #vertexCount type: 'int32_t'>
	<var: #firstVertex type: 'int32_t'>
	<returns: 'bool'>
	| p b base k last t0 |
	p := self renderPass: pass.
	p isNull ifTrue: [^false].
	p pipe = 0 ifTrue: [
		common setError: 'no pipeline bound'.
		^false].
	(vertexCount < 0 or: [firstVertex < 0]) ifTrue: [
		common setError: 'bad vertex range'.
		^false].
	vertexCount < 3 ifTrue: [^true].
	b := self get: p vbuf kind: SW_K_BUF what: 'vertex buffer'.
	b isNull ifTrue: [^false].
	p voff asInt64 + ((firstVertex asInt64 + vertexCount asInt64) * SW_STRIDE) > b i ifTrue: [
		common setError: 'the draw reads beyond the vertex buffer'.
		^false].
	t0 := self monoUs.
	(self prepare: p) ifTrue: [
		base := (self cCoerce: b ptr to: 'uint8_t *') + p voff.
		k := firstVertex asInt64.
		last := firstVertex asInt64 + vertexCount asInt64.
		[k + 3 <= last] whileTrue: [
			((k rem: 6) = 0 and: [k + 6 <= last and: [self isQuad: base + (k * SW_STRIDE)]])
				ifTrue: [
					self drawQuad: base + (k * SW_STRIDE).
					k := k + 6]
				ifFalse: [
					self drawTriangle: base index: k.
					k := k + 3]]].
	self charge: p cmd since: t0.
	^true
!
prepare: p
	"Set the raster state for a draw in pass p; false if nothing can be drawn."
	<function>
	<var: #p type: 'UefiGpuPass *'>
	<returns: 'bool'>
	| c o t x0 y0 x1 y1 v |
	t := common table: objs at: p target kind: -1.
	(t isNull or: [(t kind ~= SW_K_TEX and: [t kind ~= SW_K_SWAP]) or: [t fmt = PF_TEX_R8]]) ifTrue: [^false].
	o := common table: objs at: p cmd kind: SW_K_CMD.
	o isNull ifTrue: [^false].
	c := self cCoerce: o ptr to: 'UefiGpuCmd *'.
	((c vu at: 0) > 0.0 and: [(c vu at: 1) > 0.0]) ifFalse: [^false].
	rsPixels := self cCoerce: t ptr to: 'uint8_t *'.
	rsW := t w.
	rsH := t h.
	rsFmt := t fmt.
	rsBlend := p blend.
	"clip: the scissor, the viewport (pixel centres inside it), the target"
	x0 := p sx asInt64 max: 0.
	y0 := p sy asInt64 max: 0.
	x1 := p sx asInt64 + p sw asInt64.
	y1 := p sy asInt64 + p sh asInt64.
	x1 := x1 min: rsW.
	y1 := y1 min: rsH.
	v := self floorOf: p vx + 0.5.
	x0 := x0 max: v.
	v := self floorOf: p vy + 0.5.
	y0 := y0 max: v.
	v := self floorOf: p vx + p vw + 0.5.
	x1 := x1 min: v.
	v := self floorOf: p vy + p vh + 0.5.
	y1 := y1 min: v.
	(x0 < x1 and: [y0 < y1]) ifFalse: [^false].
	rsClipX0 := x0.
	rsClipY0 := y0.
	rsClipX1 := x1.
	rsClipY1 := y1.
	"framebuffer x = vx + p.x / viewport.x * vw (p: position + origin + translation)"
	rsOx := p vx.
	rsOy := p vy.
	rsSx := p vw / (c vu at: 0).
	rsSy := p vh / (c vu at: 1).
	rsTx := c vu at: 2.
	rsTy := c vu at: 3.
	rsTex := self null.
	o := common table: objs at: p tex kind: SW_K_TEX.
	o notNull ifTrue: [
		rsTex := self cCoerce: o ptr to: 'uint8_t *'.
		rsTexW := o w.
		rsTexH := o h.
		rsTexFmt := o fmt.
		rsLinear := p linear.
		rsRepeat := p wrap].
	^true
!
isQuad: v
	"Whether the six vertices at v are equal and not explicitly positioned."
	<function>
	<var: #v type: 'uint8_t *'>
	<returns: 'bool'>
	| w |
	w := self cCoerce: v to: 'uint64_t *'.
	((w at: 3) >> 63) = 0 ifFalse: [^false].
	0 to: 24 do: [:i | (w at: i) = (w at: i + 5) ifFalse: [^false]].
	^true
!
targetColor: rgba
	"A vertex color (RGBA8) in the target's channel order."
	<function>
	<var: #rgba type: 'uint32_t'>
	<returns: 'uint32_t'>
	^rsFmt = PF_TEX_BGRA8 ifTrue: [(self swapRB: rgba) asUInt32] ifFalse: [rgba]
!
drawQuad: v
	"The axis-aligned rectangle of the quad whose six vertices are v: its corners, uv0 and uv1 (texels), color, mode."
	<function>
	<var: #v type: 'uint8_t *'>
	| f u ox oy x0 y0 x1 y1 xa xb ya yb px0 px1 py0 py1 m ua ub va vb du dv sx0 sy0 |
	f := self cCoerce: v to: 'float *'.
	u := self cCoerce: v to: 'uint32_t *'.
	ox := (f at: 8) asFloat + rsTx.
	oy := (f at: 9) asFloat + rsTy.
	x0 := (f at: 0) asFloat + ox.
	y0 := (f at: 1) asFloat + oy.
	x1 := (f at: 2) asFloat + ox.
	y1 := (f at: 3) asFloat + oy.
	rsMode := u at: 7.
	rsColor := self targetColor: (u at: 6).
	rsOrgX := x0.
	rsOrgY := y0.
	"framebuffer, fixed point"
	xa := self snap: rsOx + (x0 * rsSx).
	xb := self snap: rsOx + (x1 * rsSx).
	ya := self snap: rsOy + (y0 * rsSy).
	yb := self snap: rsOy + (y1 * rsSy).
	"pixels whose centres are inside: left and top edges in, right and bottom out"
	xa <= xb
		ifTrue: [
			px0 := (xa + 127) >> 8.
			px1 := (xb + 127) >> 8]
		ifFalse: [
			px0 := (xb + 127) >> 8.
			px1 := (xa + 127) >> 8].
	ya <= yb
		ifTrue: [
			py0 := (ya + 127) >> 8.
			py1 := (yb + 127) >> 8]
		ifFalse: [
			py0 := (yb + 127) >> 8.
			py1 := (ya + 127) >> 8].
	px0 := px0 max: rsClipX0.
	py0 := py0 max: rsClipY0.
	px1 := px1 min: rsClipX1.
	py1 := py1 min: rsClipY1.
	(px0 < px1 and: [py0 < py1]) ifFalse: [^self].
	m := rsMode bitAnd: 255.
	m = 0 ifTrue: [^self solidX: px0 y: py0 width: px1 - px0 height: py1 - py0].
	(m = 1 or: [m = 2]) ifFalse: [
		m ~= 5 ifTrue: [^self patternX: px0 y: py0 width: px1 - px0 height: py1 - py0]].
	"uv at pixel centres: from uv0 at the first corner to uv1 at the opposite one"
	ua := ((u at: 4) bitAnd: 16rFFFF) asFloat.
	va := ((u at: 4) >> 16) asFloat.
	ub := ((u at: 5) bitAnd: 16rFFFF) asFloat.
	vb := ((u at: 5) >> 16) asFloat.
	sx0 := xa asFloat / 256.0.
	sy0 := ya asFloat / 256.0.
	du := (ub - ua) / ((xb - xa) asFloat / 256.0).
	dv := (vb - va) / ((yb - ya) asFloat / 256.0).
	ua := ua + (du * ((px0 asFloat + 0.5) - sx0)).
	va := va + (dv * ((py0 asFloat + 0.5) - sy0)).
	m ~= 5 ifTrue: [
		(self texturedX: px0 y: py0 width: px1 - px0 height: py1 - py0 u: ua v: va du: du dv: dv) ifTrue: [^self].
		(self scaledX: px0 y: py0 width: px1 - px0 height: py1 - py0 u: ua v: va du: du dv: dv) ifTrue: [^self]].
	self shadeX: px0 y: py0 width: px1 - px0 height: py1 - py0 u: ua v: va du: du dv: dv
!
row: py x: px
	<function>
	<var: #py type: 'int64_t'>
	<var: #px type: 'int64_t'>
	<returns: 'uint32_t *'>
	^self cCoerce: rsPixels + ((((py * rsW) + px) * 4) asUInt64) to: 'uint32_t *'
!
solidX: x y: y width: w height: h
	"Mode 0 over a rectangle of pixels."
	<function>
	<var: #x type: 'int64_t'>
	<var: #y type: 'int64_t'>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	| c d ca |
	c := rsColor.
	ca := c >> 24.
	(rsBlend = PF_BLEND_NONE or: [ca = 255]) ifTrue: [
		y to: y + h - 1 do: [:py |
			d := self row: py x: x.
			0 to: w - 1 do: [:i | d at: i put: c]].
		^self].
	rsBlend = PF_BLEND_PREMULTIPLIED ifFalse: [
		y to: y + h - 1 do: [:py |
			d := self row: py x: x.
			0 to: w - 1 do: [:i | d at: i put: (self blend: (d at: i) source: c k: 255)]].
		^self].
	c = 0 ifTrue: [^self].
	y to: y + h - 1 do: [:py |
		d := self row: py x: x.
		0 to: w - 1 do: [:i | d at: i put: (self over: (d at: i) color: c)]]
!
patternX: x y: y width: w height: h
	"Modes 3 (halftone) and 4 (stripes; every other mode but 5 is drawn as stripes, as by the shader): on pixels get the color, off ones nothing."
	<function>
	<var: #x type: 'int64_t'>
	<var: #y type: 'int64_t'>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	| m cell variant c d dx dy iy kind want t0 t q r rowOn |
	rsBlend = PF_BLEND_PREMULTIPLIED ifFalse: [^self shadeX: x y: y width: w height: h u: 0.0 v: 0.0 du: 0.0 dv: 0.0].
	m := rsMode bitAnd: 255.
	cell := (rsMode >> 8) bitAnd: 255.
	cell = 0 ifTrue: [cell := 1].
	variant := (rsMode >> 16) bitAnd: 255.
	c := rsColor.
	c = 0 ifTrue: [^self].
	dx := self floorOf: (x asFloat + 0.5) - rsOrgX.
	y to: y + h - 1 do: [:py |
		d := self row: py x: x.
		dy := self floorOf: (py asFloat + 0.5) - rsOrgY.
		iy := (dy max: 0) quo: cell.
		"kind 0: the whole row on or off (rowOn); 1: on where (ix & 1) = want; 2: on where ((dx + dy) / cell & 1) = 0"
		kind := 0.
		want := 0.
		rowOn := false.
		m = 3
			ifTrue: [
				variant = 1
					ifTrue: [
						kind := 1.
						want := iy bitAnd: 1]
					ifFalse: [
						(iy bitAnd: 1) = 1 ifTrue: [
							kind := 1.
							want := 1]]]
			ifFalse: [
				variant = 1
					ifTrue: [kind := 1]
					ifFalse: [
						variant = 2
							ifTrue: [kind := 2]
							ifFalse: [rowOn := (iy bitAnd: 1) = 0]]].
		kind = 0
			ifTrue: [
				rowOn ifTrue: [
					(c >> 24) = 255
						ifTrue: [0 to: w - 1 do: [:i | d at: i put: c]]
						ifFalse: [0 to: w - 1 do: [:i | d at: i put: (self over: (d at: i) color: c)]]]]
			ifFalse: [
				t0 := kind = 1 ifTrue: [dx] ifFalse: [dx + dy].
				t := t0 max: 0.
				q := t quo: cell.
				r := t rem: cell.
				t := t0.
				0 to: w - 1 do: [:i |
					(q bitAnd: 1) = want ifTrue: [d at: i put: (self over: (d at: i) color: c)].
					t := t + 1.
					t > 0 ifTrue: [
						r := r + 1.
						r = cell ifTrue: [
							r := 0.
							q := q + 1]]]]]
!
texturedX: x y: y width: w height: h u: u0 v: v0 du: du dv: dv
	"Modes 1 and 2 where the pixels map 1:1 on texels inside the texture (u, v at the first pixel centre): copy texel rows (premultiplied blending only). Answer whether done."
	<function>
	<var: #x type: 'int64_t'>
	<var: #y type: 'int64_t'>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	<var: #u0 type: 'double'>
	<var: #v0 type: 'double'>
	<var: #du type: 'double'>
	<var: #dv type: 'double'>
	<returns: 'bool'>
	| tx ty bpp m |
	(rsTex isNull or: [rsBlend ~= PF_BLEND_PREMULTIPLIED or: [du ~= 1.0 or: [dv ~= 1.0]]]) ifTrue: [^false].
	rsLinear
		ifTrue: [
			"at texel centres: bilinear is the texel"
			tx := self floorOf: u0 - 0.5.
			ty := self floorOf: v0 - 0.5.
			(tx asFloat = (u0 - 0.5) and: [ty asFloat = (v0 - 0.5)]) ifFalse: [^false]]
		ifFalse: [
			tx := self floorOf: u0.
			ty := self floorOf: v0].
	(tx >= 0 and: [ty >= 0 and: [tx + w <= rsTexW and: [ty + h <= rsTexH]]]) ifFalse: [^false].
	m := rsMode bitAnd: 255.
	bpp := rsTexFmt = PF_TEX_R8 ifTrue: [1] ifFalse: [4].
	0 to: h - 1 do: [:j |
		m = 1
			ifTrue: [
				self glyphRow: (self row: y + j x: x)
					coverage: rsTex + ((((((ty + j) * rsTexW) + tx) * bpp) + (rsTexFmt = PF_TEX_BGRA8 ifTrue: [2] ifFalse: [0])) asUInt64)
					step: bpp count: w]
			ifFalse: [
				self imageRow: (self row: y + j x: x) texels: rsTex + (((((ty + j) * rsTexW) + tx) * bpp) asUInt64) count: w]].
	^true
!
scaledX: x y: y width: w height: h u: u0 v: v0 du: du dv: dv
	"Modes 1 and 2 at any scale, clamped to the edge (premultiplied blending only): per row the texel rows and their weight, per pixel the texel columns; the same sampling as sampleU:v:. Answer whether done."
	<function>
	<var: #x type: 'int64_t'>
	<var: #y type: 'int64_t'>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	<var: #u0 type: 'double'>
	<var: #v0 type: 'double'>
	<var: #du type: 'double'>
	<var: #dv type: 'double'>
	<returns: 'bool'>
	| m bpp maxX maxY ca c d v vv uu u t tx0 tx1 ty0 ty1 fx fy r0 r1 s k glyphShift conv lin tex texW |
	(rsTex isNull or: [rsRepeat or: [rsBlend ~= PF_BLEND_PREMULTIPLIED]]) ifTrue: [^false].
	"only coordinates whose floor is an int64"
	u := u0 + (du * w asFloat).
	v := v0 + (dv * h asFloat).
	((u0 > -1.0e9 and: [u0 < 1.0e9]) and: [(u > -1.0e9 and: [u < 1.0e9]) and: [(v0 > -1.0e9 and: [v0 < 1.0e9]) and: [v > -1.0e9 and: [v < 1.0e9]]]]) ifFalse: [^false].
	"the raster state in locals: stores through d may alias the globals"
	m := rsMode bitAnd: 255.
	conv := self texelConversion.
	lin := rsLinear.
	tex := rsTex.
	texW := rsTexW.
	bpp := rsTexFmt = PF_TEX_R8 ifTrue: [1] ifFalse: [4].
	maxX := rsTexW - 1.
	maxY := rsTexH - 1.
	c := rsColor.
	ca := (c >> 24) asInt64.
	glyphShift := rsFmt = PF_TEX_BGRA8 ifTrue: [16] ifFalse: [0].
	(m = 2 and: [ca = 0]) ifTrue: [^true].
	0 to: h - 1 do: [:j |
		d := self row: y + j x: x.
		v := v0 + (dv * j asFloat).
		lin
			ifTrue: [
				vv := v - 0.5.
				t := self floorOf: vv.
				fy := self floorOf: ((vv - t asFloat) * 256.0) + 0.5.
				ty0 := t < 0 ifTrue: [0] ifFalse: [t > maxY ifTrue: [maxY] ifFalse: [t]].
				t := t + 1.
				ty1 := t < 0 ifTrue: [0] ifFalse: [t > maxY ifTrue: [maxY] ifFalse: [t]]]
			ifFalse: [
				t := self floorOf: v.
				ty0 := t < 0 ifTrue: [0] ifFalse: [t > maxY ifTrue: [maxY] ifFalse: [t]].
				ty1 := ty0.
				fy := 0].
		r0 := tex + ((ty0 * texW * bpp) asUInt64).
		r1 := tex + ((ty1 * texW * bpp) asUInt64).
		0 to: w - 1 do: [:i |
			u := u0 + (du * i asFloat).
			lin
				ifTrue: [
					uu := u - 0.5.
					t := self floorOf: uu.
					fx := self floorOf: ((uu - t asFloat) * 256.0) + 0.5.
					tx0 := t < 0 ifTrue: [0] ifFalse: [t > maxX ifTrue: [maxX] ifFalse: [t]].
					t := t + 1.
					tx1 := t < 0 ifTrue: [0] ifFalse: [t > maxX ifTrue: [maxX] ifFalse: [t]]]
				ifFalse: [
					t := self floorOf: u.
					tx0 := t < 0 ifTrue: [0] ifFalse: [t > maxX ifTrue: [maxX] ifFalse: [t]].
					tx1 := tx0.
					fx := 0].
			s := (fx = 0 and: [fy = 0])
				ifTrue: [self fetch: r0 x: tx0 conversion: conv]
				ifFalse: [
					self mix: (self fetch: r0 x: tx0 conversion: conv) with: (self fetch: r0 x: tx1 conversion: conv)
						with: (self fetch: r1 x: tx0 conversion: conv) with: (self fetch: r1 x: tx1 conversion: conv) fx: fx fy: fy].
			m = 1
				ifTrue: [
					k := (s >> glyphShift) asInt64 bitAnd: 255.
					k ~= 0 ifTrue: [d at: i put: (self over: (d at: i) color: c k: k)]]
				ifFalse: [
					s ~= 0 ifTrue: [d at: i put: (ca = 255 ifTrue: [self over: (d at: i) color: s] ifFalse: [self over: (d at: i) color: s k: ca])]]]].
	^true
!
texelConversion
	"How fetch:x:conversion: turns the texture's texels into the target's order: 0 as they are, 1 red and blue swapped, 2 R8 to (r, 0, 0, 1) RGBA, 3 to BGRA."
	<function>
	<returns: 'int64_t'>
	rsTexFmt = PF_TEX_R8 ifTrue: [^rsFmt = PF_TEX_BGRA8 ifTrue: [3] ifFalse: [2]].
	^rsTexFmt = rsFmt ifTrue: [0] ifFalse: [1]
!
fetch: r x: tx conversion: conv
	"Texel tx of the texture row r, in the target's order (texelConversion)."
	<function>
	<var: #r type: 'uint8_t *'>
	<var: #tx type: 'int64_t'>
	<var: #conv type: 'int64_t'>
	<returns: 'uint32_t'>
	| v |
	conv = 0 ifTrue: [^(self cCoerce: r to: 'uint32_t *') at: tx].
	conv = 1 ifTrue: [
		v := (self cCoerce: r to: 'uint32_t *') at: tx.
		^(self swapRB: v) asUInt32].
	conv = 2 ifTrue: [^(r at: tx) asUInt32 bitOr: 16rFF000000].
	^((r at: tx) asUInt64 << 16) asUInt32 bitOr: 16rFF000000
!
mix: a with: b with: c with: d fx: fx fy: fy
	"Bilinear: a b the upper texels, c d the lower; 8-bit weights, each channel rounded. Two channels at a time, 32 bits apart."
	<function>
	<var: #a type: 'uint32_t'>
	<var: #b type: 'uint32_t'>
	<var: #c type: 'uint32_t'>
	<var: #d type: 'uint32_t'>
	<var: #fx type: 'int64_t'>
	<var: #fy type: 'int64_t'>
	<returns: 'uint32_t'>
	| gx gy rb ag |
	gx := (256 - fx) asUInt64.
	gy := (256 - fy) asUInt64.
	rb := ((((self spread: a) * gx) + ((self spread: b) * fx asUInt64)) * gy) + ((((self spread: c) * gx) + ((self spread: d) * fx asUInt64)) * fy asUInt64) + 16r0000800000008000.
	ag := ((((self spread: a >> 8) * gx) + ((self spread: b >> 8) * fx asUInt64)) * gy) + ((((self spread: c >> 8) * gx) + ((self spread: d >> 8) * fx asUInt64)) * fy asUInt64) + 16r0000800000008000.
	^(((rb >> 16) bitAnd: 16rFF) bitOr: ((rb >> 32) bitAnd: 16rFF0000)) asUInt32
		bitOr: ((((ag >> 8) bitAnd: 16rFF00) bitOr: ((ag >> 24) bitAnd: 16rFF000000)) asUInt32)
!
spread: v
	"Bytes 0 and 2 of v, 32 bits apart."
	^(v bitAnd: 16rFF) asUInt64 bitOr: ((v bitAnd: 16rFF0000) asUInt64 << 16)
!
glyphRow: d coverage: cov step: step count: n
	"Mode 1: the color times the coverage (every step bytes) over n pixels."
	<function>
	<var: #d type: 'uint32_t *'>
	<var: #cov type: 'uint8_t *'>
	<var: #step type: 'int64_t'>
	<var: #n type: 'int64_t'>
	| c k |
	c := rsColor.
	(c >> 24) = 255
		ifTrue: [
			0 to: n - 1 do: [:i |
				k := cov at: i * step.
				k ~= 0 ifTrue: [
					d at: i put: (k = 255 ifTrue: [c] ifFalse: [self over: (d at: i) color: c k: k asInt64])]]]
		ifFalse: [
			0 to: n - 1 do: [:i |
				k := cov at: i * step.
				k ~= 0 ifTrue: [d at: i put: (self over: (d at: i) color: c k: k asInt64)]]]
!
imageRow: d texels: src count: n
	"Mode 2: the texels times the color's alpha over n pixels."
	<function>
	<var: #d type: 'uint32_t *'>
	<var: #src type: 'uint8_t *'>
	<var: #n type: 'int64_t'>
	| s t ca swap |
	ca := (rsColor >> 24) asInt64.
	ca = 0 ifTrue: [^self].
	rsTexFmt = PF_TEX_R8 ifTrue: [
		0 to: n - 1 do: [:i | d at: i put: (self over: (d at: i) color: (self texelOf: (src at: i) asUInt32) k: ca)].
		^self].
	s := self cCoerce: src to: 'uint32_t *'.
	swap := rsTexFmt ~= rsFmt.
	ca = 255 ifTrue: [
		swap
			ifTrue: [
				0 to: n - 1 do: [:i |
					t := s at: i.
					(t >> 24) = 255
						ifTrue: [d at: i put: (self swapRB: t) asUInt32]
						ifFalse: [t ~= 0 ifTrue: [d at: i put: (self over: (d at: i) color: (self swapRB: t) asUInt32)]]]]
			ifFalse: [
				0 to: n - 1 do: [:i |
					t := s at: i.
					(t >> 24) = 255
						ifTrue: [d at: i put: t]
						ifFalse: [t ~= 0 ifTrue: [d at: i put: (self over: (d at: i) color: t)]]]].
		^self].
	0 to: n - 1 do: [:i |
		t := s at: i.
		swap ifTrue: [t := (self swapRB: t) asUInt32].
		t ~= 0 ifTrue: [d at: i put: (self over: (d at: i) color: t k: ca)]]
!
shadeX: x y: y width: w height: h u: u0 v: v0 du: du dv: dv
	"Any mode, pixel by pixel (uv: u0 v0 at the first pixel centre, du dv a pixel)."
	<function>
	<var: #x type: 'int64_t'>
	<var: #y type: 'int64_t'>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	<var: #u0 type: 'double'>
	<var: #v0 type: 'double'>
	<var: #du type: 'double'>
	<var: #dv type: 'double'>
	| d v |
	0 to: h - 1 do: [:j |
		d := self row: y + j x: x.
		v := v0 + (dv * j asFloat).
		0 to: w - 1 do: [:i |
			self shade: d + i x: x + i y: y + j u: u0 + (du * i asFloat) v: v]]
!
shade: d x: px y: py u: u v: v
	"The fragment shader at pixel (px, py) with the interpolated uv (and color, rsColor), blended into d."
	<function>
	<var: #d type: 'uint32_t *'>
	<var: #px type: 'int64_t'>
	<var: #py type: 'int64_t'>
	<var: #u type: 'double'>
	<var: #v type: 'double'>
	| m src k cover au cell variant dx dy ix iy on s sum |
	m := rsMode bitAnd: 255.
	src := rsColor.
	k := 255.
	m = 1
		ifTrue: [
			s := self sampleU: u v: v.
			k := (rsFmt = PF_TEX_BGRA8 ifTrue: [s >> 16] ifFalse: [s]) asInt64 bitAnd: 255]
		ifFalse: [
			m = 2
				ifTrue: [
					src := self sampleU: u v: v.
					k := (rsColor >> 24) asInt64]
				ifFalse: [
					m = 5
						ifTrue: [
							au := u < 0.0 ifTrue: [u negated] ifFalse: [u].
							cover := (v + 0.5) - au.
							k := self unorm8: cover]
						ifFalse: [
							m ~= 0 ifTrue: [
								cell := (rsMode >> 8) bitAnd: 255.
								cell = 0 ifTrue: [cell := 1].
								variant := (rsMode >> 16) bitAnd: 255.
								dx := self floorOf: (px asFloat + 0.5) - rsOrgX.
								dy := self floorOf: (py asFloat + 0.5) - rsOrgY.
								ix := (dx max: 0) quo: cell.
								iy := (dy max: 0) quo: cell.
								m = 3
									ifTrue: [
										on := variant = 1
											ifTrue: [((ix + iy) bitAnd: 1) = 0]
											ifFalse: [(ix bitAnd: 1) = 1 and: [(iy bitAnd: 1) = 1]]]
									ifFalse: [
										variant = 1
											ifTrue: [on := (ix bitAnd: 1) = 0]
											ifFalse: [
												variant = 2
													ifTrue: [
														sum := dx + dy.
														sum := sum max: 0.
														on := ((sum quo: cell) bitAnd: 1) = 0]
													ifFalse: [on := (iy bitAnd: 1) = 0]]].
								on ifFalse: [k := 0]]]]].
	(k = 0 and: [rsBlend ~= PF_BLEND_NONE]) ifTrue: [^self].
	d value: (self blend: d value source: src k: k)
!
texelOf: r
	"An R8 texel as the shader samples it, (r, 0, 0, 1), in the target's order."
	<function>
	<var: #r type: 'uint32_t'>
	<returns: 'uint32_t'>
	^rsFmt = PF_TEX_BGRA8 ifTrue: [(r asUInt64 << 16) asUInt32 bitOr: 16rFF000000] ifFalse: [r bitOr: 16rFF000000]
!
texelX: x y: y
	"The texel at (x, y) in the target's order."
	<function>
	<var: #x type: 'int64_t'>
	<var: #y type: 'int64_t'>
	<returns: 'uint32_t'>
	| v |
	rsTexFmt = PF_TEX_R8 ifTrue: [^self texelOf: (rsTex at: (y * rsTexW) + x) asUInt32].
	v := (self cCoerce: rsTex to: 'uint32_t *') at: (y * rsTexW) + x.
	^rsTexFmt = rsFmt ifTrue: [v] ifFalse: [(self swapRB: v) asUInt32]
!
wrap: i size: n
	"Texel index i inside 0..n-1: clamped to the edge, or repeated."
	<function>
	<var: #i type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<returns: 'int64_t'>
	| m |
	rsRepeat ifTrue: [
		m := i rem: n.
		^m < 0 ifTrue: [m + n] ifFalse: [m]].
	i < 0 ifTrue: [^0].
	^i >= n ifTrue: [n - 1] ifFalse: [i]
!
sampleU: u v: v
	"textureLod(tex, (u, v) / size, 0) with u, v in texels, as a pixel of the target's order: nearest = texel floor(uv), linear = bilinear between texel centres (8-bit weights). 0 with no texture."
	<function>
	<var: #u type: 'double'>
	<var: #v type: 'double'>
	<returns: 'uint32_t'>
	| uu vv x y fx fy x0 x1 y0 y1 |
	rsTex isNull ifTrue: [^0].
	rsLinear ifFalse: [
		^self texelX: (self wrap: (self floorOf: u) size: rsTexW) y: (self wrap: (self floorOf: v) size: rsTexH)].
	uu := u - 0.5.
	vv := v - 0.5.
	x := self floorOf: uu.
	y := self floorOf: vv.
	fx := self floorOf: ((uu - x asFloat) * 256.0) + 0.5.
	fy := self floorOf: ((vv - y asFloat) * 256.0) + 0.5.
	x0 := self wrap: x size: rsTexW.
	x1 := self wrap: x + 1 size: rsTexW.
	y0 := self wrap: y size: rsTexH.
	y1 := self wrap: y + 1 size: rsTexH.
	^self mix: (self texelX: x0 y: y0) with: (self texelX: x1 y: y0) with: (self texelX: x0 y: y1) with: (self texelX: x1 y: y1) fx: fx fy: fy
!
drawTriangle: base index: k
	"The triangle of vertices k, k + 1, k + 2 (each positioned explicitly if bit 31 of its mode is set, else at its quad corner vertexIndex % 6); the flat attributes (mode, origin) from vertex k, the provoking vertex."
	<function>
	<var: #base type: 'uint8_t *'>
	<var: #k type: 'int64_t'>
	| xs ys at ea eb ec et f u c corner kx ky px py uu vv area tmp minX maxX minY maxY x0 x1 y0 y1 det
	  ax ay bx by dx dy flat cy xl xr r a lim fx0 fy0 ia ib |
	xs := self local: 'int64_t[3]'.
	ys := self local: 'int64_t[3]'.
	at := self local: 'double[18]'.
	"the vertex stage; attributes u v and the color's four lanes (target order, 0..255) at 6 j"
	0 to: 2 do: [:j |
		f := self cCoerce: base + ((k + j) * SW_STRIDE) to: 'float *'.
		u := self cCoerce: base + ((k + j) * SW_STRIDE) to: 'uint32_t *'.
		((u at: 7) >> 31) ~= 0
			ifTrue: [
				px := (f at: 0) asFloat.
				py := (f at: 1) asFloat.
				uu := (f at: 4) asFloat.
				vv := (f at: 5) asFloat]
			ifFalse: [
				corner := (k + j) rem: 6.
				kx := (corner = 1 or: [corner = 3 or: [corner = 4]]) ifTrue: [1.0] ifFalse: [0.0].
				ky := (corner = 2 or: [corner = 4 or: [corner = 5]]) ifTrue: [1.0] ifFalse: [0.0].
				px := (f at: 0) asFloat + (((f at: 2) asFloat - (f at: 0) asFloat) * kx).
				py := (f at: 1) asFloat + (((f at: 3) asFloat - (f at: 1) asFloat) * ky).
				uu := ((u at: 4) bitAnd: 16rFFFF) asFloat.
				uu := uu + ((((u at: 5) bitAnd: 16rFFFF) asFloat - uu) * kx).
				vv := ((u at: 4) >> 16) asFloat.
				vv := vv + ((((u at: 5) >> 16) asFloat - vv) * ky)].
		px := px + ((f at: 8) asFloat + rsTx).
		py := py + ((f at: 9) asFloat + rsTy).
		xs at: j put: (self snap: rsOx + (px * rsSx)).
		ys at: j put: (self snap: rsOy + (py * rsSy)).
		c := self targetColor: (u at: 6).
		at at: j * 6 put: uu.
		at at: (j * 6) + 1 put: vv.
		0 to: 3 do: [:l | at at: (j * 6) + 2 + l put: ((c >> (l * 8)) bitAnd: 255) asFloat].
		j = 0 ifTrue: [
			rsMode := u at: 7.
			rsColor := c.
			rsOrgX := (f at: 0) asFloat + ((f at: 8) asFloat + rsTx).
			rsOrgY := (f at: 1) asFloat + ((f at: 9) asFloat + rsTy)]].
	flat := ((self cCoerce: base + ((k + 1) * SW_STRIDE) to: 'uint32_t *') at: 6) = ((self cCoerce: base + (k * SW_STRIDE) to: 'uint32_t *') at: 6)
		and: [((self cCoerce: base + ((k + 2) * SW_STRIDE) to: 'uint32_t *') at: 6) = ((self cCoerce: base + (k * SW_STRIDE) to: 'uint32_t *') at: 6)].
	area := (((xs at: 1) - (xs at: 0)) * ((ys at: 2) - (ys at: 0))) - (((ys at: 1) - (ys at: 0)) * ((xs at: 2) - (xs at: 0))).
	area = 0 ifTrue: [^self].
	"the edges a -> b of the counterclockwise order (E > 0 inside): E = ea (x - xa) + eb (y - ya); et = 0 on a top or left edge (a pixel centre on it is in), else 1"
	ea := self local: 'int64_t[3]'.
	eb := self local: 'int64_t[3]'.
	ec := self local: 'int64_t[3]'.
	et := self local: 'int64_t[3]'.
	0 to: 2 do: [:e |
		area > 0
			ifTrue: [
				ia := e.
				ib := (e + 1) rem: 3]
			ifFalse: [
				ia := (e + 1) rem: 3.
				ib := e].
		ea at: e put: ((ys at: ib) - (ys at: ia)) negated.
		eb at: e put: (xs at: ib) - (xs at: ia).
		ec at: e put: ia.
		et at: e put: (((ea at: e) > 0 or: [(ea at: e) = 0 and: [(eb at: e) > 0]]) ifTrue: [0] ifFalse: [1])].
	minX := (xs at: 0) min: (xs at: 1).
	tmp := xs at: 2.
	minX := minX min: tmp.
	maxX := (xs at: 0) max: (xs at: 1).
	maxX := maxX max: tmp.
	minY := (ys at: 0) min: (ys at: 1).
	tmp := ys at: 2.
	minY := minY min: tmp.
	maxY := (ys at: 0) max: (ys at: 1).
	maxY := maxY max: tmp.
	x0 := (minX + 127) >> 8.
	x1 := ((maxX + 127) >> 8) + 1.
	y0 := (minY + 127) >> 8.
	y1 := ((maxY + 127) >> 8) + 1.
	x0 := x0 max: rsClipX0.
	y0 := y0 max: rsClipY0.
	x1 := x1 min: rsClipX1.
	y1 := y1 min: rsClipY1.
	(x0 < x1 and: [y0 < y1]) ifFalse: [^self].
	"attribute planes from vertex 0: a = a0 + dx (x - x0) + dy (y - y0), the slopes of u, v and the four color lanes in dx and dy"
	fx0 := (xs at: 0) asFloat / 256.0.
	fy0 := (ys at: 0) asFloat / 256.0.
	ax := ((xs at: 1) - (xs at: 0)) asFloat / 256.0.
	ay := ((ys at: 1) - (ys at: 0)) asFloat / 256.0.
	bx := ((xs at: 2) - (xs at: 0)) asFloat / 256.0.
	by := ((ys at: 2) - (ys at: 0)) asFloat / 256.0.
	det := (ax * by) - (bx * ay).
	dx := self local: 'double[6]'.
	dy := self local: 'double[6]'.
	0 to: 5 do: [:l |
		dx at: l put: ((((at at: 6 + l) - (at at: l)) * by) - (((at at: 12 + l) - (at at: l)) * ay)) / det.
		dy at: l put: ((((at at: 12 + l) - (at at: l)) * ax) - (((at at: 6 + l) - (at at: l)) * bx)) / det].
	y0 to: y1 - 1 do: [:py2 |
		"the span of the row: E(px) = 256 ea px + r >= et for each edge"
		cy := (py2 * 256) + 128.
		xl := x0.
		xr := x1 - 1.
		0 to: 2 do: [:e |
			a := (ea at: e) * 256.
			r := ((ea at: e) * (128 - (xs at: (ec at: e)))) + ((eb at: e) * (cy - (ys at: (ec at: e)))).
			a = 0
				ifTrue: [r < (et at: e) ifTrue: [xr := xl - 1]]
				ifFalse: [
					a > 0
						ifTrue: [
							lim := (self floorDiv: ((et at: e) - r) + a - 1 by: a).
							xl := xl max: lim]
						ifFalse: [
							lim := self floorDiv: r - (et at: e) by: a negated.
							xr := xr min: lim]]].
		xl <= xr ifTrue: [self triangleSpan: py2 from: xl to: xr planes: at dx: dx dy: dy x0: fx0 y0: fy0 flat: flat]]
!
triangleSpan: py from: xl to: xr planes: at dx: dx dy: dy x0: fx0 y0: fy0 flat: flat
	"Shade pixels xl..xr of row py of a triangle: attributes from vertex 0's values (at) and the planes' slopes."
	<function>
	<var: #py type: 'int64_t'>
	<var: #xl type: 'int64_t'>
	<var: #xr type: 'int64_t'>
	<var: #at type: 'double *'>
	<var: #dx type: 'double *'>
	<var: #dy type: 'double *'>
	<var: #fx0 type: 'double'>
	<var: #fy0 type: 'double'>
	<var: #flat type: 'bool'>
	| d ex ey c ch |
	d := self row: py x: 0.
	ey := (py asFloat + 0.5) - fy0.
	xl to: xr do: [:px |
		ex := (px asFloat + 0.5) - fx0.
		flat ifFalse: [
			c := 0.
			0 to: 3 do: [:l |
				ch := self floorOf: (at at: 2 + l) + ((dx at: 2 + l) * ex) + ((dy at: 2 + l) * ey) + 0.5.
				ch < 0 ifTrue: [ch := 0].
				ch > 255 ifTrue: [ch := 255].
				c := c bitOr: ch << (l * 8)].
			rsColor := c asUInt32].
		self shade: d + px x: px y: py
			u: (at at: 0) + ((dx at: 0) * ex) + ((dy at: 0) * ey)
			v: (at at: 1) + ((dx at: 1) * ex) + ((dy at: 1) * ey)]
! !

VMStruct subclass: #UefiGpuClaim
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiGpuClaim comment: 'A window claimed by a device (win 0: a free entry) and its back buffer: w x h BGRA8 pixels (NULL until the first acquire).'!

!UefiGpuClaim class methodsFor: 'declaring'!
fields
	^#((win int32_t) (dev int32_t) (pixels 'uint8_t *') (w int32_t) (h int32_t))
! !

VMStruct subclass: #UefiGpuCmd
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiGpuCmd comment: 'A command buffer: the vertex uniforms of slot 0 pushed last (viewport, translation) and the µs its work took so far.'!

!UefiGpuCmd class methodsFor: 'declaring'!
fields
	^#((vu 'float[4]') (busyUs int64_t))
! !

VMStruct subclass: #UefiGpuPass
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiGpuPass comment: 'A render pass: its command buffer, its target (a texture or swapchain texture handle), the bound pipeline (and its blend), vertex buffer (slot 0) and texture (slot 0, with its sampler''s filter and address mode), the viewport and the scissor.'!

!UefiGpuPass class methodsFor: 'declaring'!
fields
	^#((cmd int32_t) (target int32_t) (pipe int32_t) (blend int32_t)
		(vbuf int32_t) (voff uint32_t) (tex int32_t) (linear bool) (wrap bool)
		(vx double) (vy double) (vw double) (vh double) (sx int32_t) (sy int32_t) (sw int32_t) (sh int32_t))
! !
