VMPlatformModule subclass: #PlatformRaster
	instanceVariableNames: 'rsPixels rsW rsH rsFmt rsClipX0 rsClipY0 rsClipX1 rsClipY1 rsBlend rsTex rsTexW rsTexH rsTexFmt rsLinear rsRepeat rsOx rsOy rsSx rsSy rsTx rsTy rsMode rsColor rsOrgX rsOrgY rows'
	classVariableNames: 'RS_MAX_COORD RS_STRIDE'
	package: 'VM-Platform'!

PlatformRaster comment: 'The pixel work of a software GPU (the raster primitives; the image''s SoftwareGPU is the device): the Renderer''s uber-shader (Renderer class>>glslShaderSource) run on a batch of its vertices into a pixel buffer, fills, blits, and copies of pixel rectangles. Pure computation on memory the caller owns: pixels are rows of R8, RGBA8 or BGRA8, tightly packed.

A draw runs the vertex stage as the shader does (the uniforms: viewport size, translation; the viewport transform) and rasterizes like a GPU: positions snapped to 1/256 pixel, pixel centres at +0.5, the top-left fill rule (adjacent quads neither overlap nor leave gaps), attributes interpolated at pixel centres, round to nearest into unorm8, blending exact up to that rounding. A quad (six equal vertices without bit 31 of mode, at a vertex index divisible by six) is an axis-aligned rectangle and takes a path over pixel rows: solid fills, glyph coverage, 1:1 images (nearest, or linear at texel centres) and the patterns without per-pixel arithmetic beyond the blend; other quads (scaled images, line coverage) shade per pixel, and the triangles of bit-31 vertices go through a general triangle rasterizer (per-row spans from the edge functions). Sampling is textureLod(tex, uv / size): nearest takes texel floor(uv), linear is bilinear with texel centres at +0.5 and 8-bit weights; clamp to edge, or repeat.

Fills, opaque and premultiplied solid rows, the rows of a pattern, 1:1 premultiplied images and red/blue swaps go 4 pixels at a time through rows (PixelRows: NEON on arm64, SSE2 on x86-64), the rest of a row one by one, with the same results to the bit.

The raster state of the draw or blit being executed is in the rs variables (target, clip, blend, texture, sampler, the vertex transform, the primitive''s flat attributes).'!

!PlatformRaster class methodsFor: 'declaring'!
declarations
	^#((rsPixels 'uint8_t *') (rsW int64_t) (rsH int64_t) (rsFmt int32_t)
		(rsClipX0 int64_t) (rsClipY0 int64_t) (rsClipX1 int64_t) (rsClipY1 int64_t) (rsBlend int32_t)
		(rsTex 'uint8_t *') (rsTexW int64_t) (rsTexH int64_t) (rsTexFmt int32_t) (rsLinear bool) (rsRepeat bool)
		(rsOx double) (rsOy double) (rsSx double) (rsSy double) (rsTx double) (rsTy double)
		(rsMode uint32_t) (rsColor uint32_t) (rsOrgX double) (rsOrgY double)
		(rows PixelRows))
!
initialize
	"The Renderer's vertex; vertex positions are clamped to RS_MAX_COORD pixels from the origin."
	RS_STRIDE := 40.
	RS_MAX_COORD := 1048576
! !

!PlatformRaster methodsFor: 'bounds'!
quadBounds: v count: n into: o
	"The device pixels the n quads at v cover (a DisplayList's vertices, 240 bytes a quad: its rect plus its origin, or with bit 31 of the mode six explicit positions plus origins), floored and ceiled, as int32 x0 y0 x1 y1 at o; n > 0."
	<function>
	<var: #v type: 'uint8_t *'>
	<var: #n type: 'int64_t'>
	<var: #o type: 'uint8_t *'>
	| f u x0 y0 x1 y1 x y i k b |
	x0 := 1.0e30.
	y0 := 1.0e30.
	x1 := -1.0e30.
	y1 := -1.0e30.
	i := 0.
	[i < n] whileTrue: [
		f := self cCoerce: v + (i * 240) to: 'float *'.
		u := self cCoerce: v + (i * 240) to: 'uint32_t *'.
		((u at: 7) bitAnd: 16r80000000) = 0
			ifTrue: [
				x := (f at: 0) asFloat + (f at: 8) asFloat.
				x < x0 ifTrue: [x0 := x].
				x := (f at: 2) asFloat + (f at: 8) asFloat.
				x > x1 ifTrue: [x1 := x].
				y := (f at: 1) asFloat + (f at: 9) asFloat.
				y < y0 ifTrue: [y0 := y].
				y := (f at: 3) asFloat + (f at: 9) asFloat.
				y > y1 ifTrue: [y1 := y]]
			ifFalse: [
				k := 0.
				[k < 6] whileTrue: [
					x := (f at: k * 10) asFloat + (f at: k * 10 + 8) asFloat.
					y := (f at: k * 10 + 1) asFloat + (f at: k * 10 + 9) asFloat.
					x < x0 ifTrue: [x0 := x].
					x > x1 ifTrue: [x1 := x].
					y < y0 ifTrue: [y0 := y].
					y > y1 ifTrue: [y1 := y].
					k := k + 1]].
		i := i + 1].
	b := self cCoerce: o to: 'int32_t *'.
	b at: 0 put: (self int32Of: (self floorOf: x0)).
	b at: 1 put: (self int32Of: (self floorOf: y0)).
	b at: 2 put: (self int32Of: 0 - (self floorOf: 0.0 - x1)).
	b at: 3 put: (self int32Of: 0 - (self floorOf: 0.0 - y1))
! !

!PlatformRaster methodsFor: 'private'!
int32Of: t
	"t clamped to +-2^30."
	<function>
	<var: #t type: 'int64_t'>
	<returns: 'int32_t'>
	t < -1073741824 ifTrue: [^-1073741824].
	t > 1073741824 ifTrue: [^1073741824].
	^t asInt32
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
	"x (pixels) in fixed point, 1/256 pixel: round(x * 256), x clamped to +-RS_MAX_COORD."
	<function>
	<var: #x type: 'double'>
	<returns: 'int64_t'>
	| c |
	c := x.
	c < RS_MAX_COORD negated asFloat ifTrue: [c := RS_MAX_COORD negated asFloat].
	c > RS_MAX_COORD asFloat ifTrue: [c := RS_MAX_COORD asFloat].
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
!
pixelBytes: format
	<function>
	<var: #format type: 'int32_t'>
	<returns: 'int'>
	^format = PF_TEX_R8 ifTrue: [1] ifFalse: [4]
! !

!PlatformRaster methodsFor: 'pixels'!
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
fill: pixels count: n bytesPerPixel: bpp value: v
	"n pixels of bpp bytes (1 or 4) set to v."
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
	(rows fill: p count: n value: v) to: n - 1 do: [:i | p at: i put: v]
!
copy: dst stride: dstStride from: src stride: srcStride width: w height: h bytesPerPixel: bpp mode: mode
	"Rows of w pixels of bpp bytes (1 or 4); 4-byte pixels with mode bit 1 swap red and blue, with bit 2 only those whose alpha is not 0 are copied."
	<function>
	<var: #dst type: 'uint8_t *'>
	<var: #dstStride type: 'int64_t'>
	<var: #src type: 'uint8_t *'>
	<var: #srcStride type: 'int64_t'>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	<var: #bpp type: 'int64_t'>
	<var: #mode type: 'int64_t'>
	| d s v swap keyed i0 |
	(bpp = 1 or: [mode = 0]) ifTrue: [
		0 to: h - 1 do: [:y | libc memcpy: dst + (y * dstStride) from: src + (y * srcStride) size: (w * bpp) asUInt64].
		^self].
	swap := (mode bitAnd: 1) ~= 0.
	keyed := (mode bitAnd: 2) ~= 0.
	0 to: h - 1 do: [:y |
		d := self cCoerce: dst + (y * dstStride) to: 'uint32_t *'.
		s := self cCoerce: src + (y * srcStride) to: 'uint32_t *'.
		i0 := 0.
		(swap and: [keyed not]) ifTrue: [i0 := rows swap: d from: s count: w].
		i0 to: w - 1 do: [:i |
			v := s at: i.
			(keyed not or: [(v >> 24) ~= 0]) ifTrue: [d at: i put: (swap ifTrue: [(self swapRB: v) asUInt32] ifFalse: [v])]]]
! !

!PlatformRaster methodsFor: 'drawing'!
rasterize: st vertices: base first: first count: count
	"Run the Renderer's pipeline on the vertices first .. first + count - 1 at base (RS_STRIDE bytes each): triangles, in order; six equal vertices from an index divisible by six (without bit 31 of mode) as one quad."
	<function>
	<var: #st type: 'RasterState *'>
	<var: #base type: 'uint8_t *'>
	<var: #first type: 'int64_t'>
	<var: #count type: 'int64_t'>
	| k last |
	count < 3 ifTrue: [^self].
	(self prepare: st) ifFalse: [^self].
	k := first.
	last := first + count.
	[k + 3 <= last] whileTrue: [
		((k rem: 6) = 0 and: [k + 6 <= last and: [self isQuad: base + (k * RS_STRIDE)]])
			ifTrue: [
				self drawQuad: base + (k * RS_STRIDE).
				k := k + 6]
			ifFalse: [
				self drawTriangle: base index: k.
				k := k + 3]]
!
prepare: st
	"Set the raster state for a draw; false if nothing can be drawn."
	<function>
	<var: #st type: 'RasterState *'>
	<returns: 'bool'>
	| x0 y0 x1 y1 v |
	(st format = PF_TEX_R8 or: [(st viewSizeX > 0.0 and: [st viewSizeY > 0.0]) not]) ifTrue: [^false].
	rsPixels := st pixels.
	rsW := st width.
	rsH := st height.
	rsFmt := st format.
	rsBlend := st blend.
	"clip: the scissor, the viewport (pixel centres inside it), the target"
	x0 := st scissorX max: 0.
	y0 := st scissorY max: 0.
	x1 := st scissorX + st scissorW.
	y1 := st scissorY + st scissorH.
	x1 := x1 min: rsW.
	y1 := y1 min: rsH.
	v := self floorOf: st viewportX + 0.5.
	x0 := x0 max: v.
	v := self floorOf: st viewportY + 0.5.
	y0 := y0 max: v.
	v := self floorOf: st viewportX + st viewportW + 0.5.
	x1 := x1 min: v.
	v := self floorOf: st viewportY + st viewportH + 0.5.
	y1 := y1 min: v.
	(x0 < x1 and: [y0 < y1]) ifFalse: [^false].
	rsClipX0 := x0.
	rsClipY0 := y0.
	rsClipX1 := x1.
	rsClipY1 := y1.
	"framebuffer x = vx + p.x / viewport.x * vw (p: position + origin + translation)"
	rsOx := st viewportX.
	rsOy := st viewportY.
	rsSx := st viewportW / st viewSizeX.
	rsSy := st viewportH / st viewSizeY.
	rsTx := st translateX.
	rsTy := st translateY.
	rsTex := st texture.
	rsTexW := st textureWidth.
	rsTexH := st textureHeight.
	rsTexFmt := st textureFormat.
	rsLinear := st linear.
	rsRepeat := st wrap.
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
			(rows fill: d count: w value: c) to: w - 1 do: [:i | d at: i put: c]].
		^self].
	rsBlend = PF_BLEND_PREMULTIPLIED ifFalse: [
		y to: y + h - 1 do: [:py |
			d := self row: py x: x.
			0 to: w - 1 do: [:i | d at: i put: (self blend: (d at: i) source: c k: 255)]].
		^self].
	c = 0 ifTrue: [^self].
	y to: y + h - 1 do: [:py |
		d := self row: py x: x.
		(rows over: d color: c count: w) to: w - 1 do: [:i | d at: i put: (self over: (d at: i) color: c)]]
!
patternX: x y: y width: w height: h
	"Modes 3 (halftone) and 4 (stripes; every other mode but 5 is drawn as stripes, as by the shader): on pixels get the color, off ones nothing."
	<function>
	<var: #x type: 'int64_t'>
	<var: #y type: 'int64_t'>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	| m cell variant c d dx dy iy kind want t0 q s e rowOn |
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
			ifTrue: [rowOn ifTrue: [self patternRun: d count: w color: c]]
			ifFalse: [
				"pixel i is in cell max(t0 + i, 0) // cell, on if the cell's parity is want: runs of cell pixels from [s, e), the run of pixel 0 or the one after it"
				t0 := kind = 1 ifTrue: [dx] ifFalse: [dx + dy].
				q := (t0 max: 0) quo: cell.
				e := ((q + 1) * cell) - t0.
				s := 0.
				(q bitAnd: 1) = want ifFalse: [
					s := e.
					e := s + cell].
				[s < w] whileTrue: [
					self patternRun: d + s count: (e min: w) - s color: c.
					s := e + cell.
					e := s + cell]]]
!
patternRun: d count: n color: c
	"The n pixels at d on in a pattern of the color c: c over each, which for an opaque c is c."
	(c >> 24) = 255
		ifTrue: [
			n < 4
				ifTrue: [0 to: n - 1 do: [:i | d at: i put: c]]
				ifFalse: [(rows fill: d count: n value: c) to: n - 1 do: [:i | d at: i put: c]]]
		ifFalse: [(rows over: d color: c count: n) to: n - 1 do: [:i | d at: i put: (self over: (d at: i) color: c)]]
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
					self bilinear: (self fetch: r0 x: tx0 conversion: conv) with: (self fetch: r0 x: tx1 conversion: conv)
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
bilinear: a with: b with: c with: d fx: fx fy: fy
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
				(rows over: d texels: s count: n swap: true) to: n - 1 do: [:i |
					t := s at: i.
					(t >> 24) = 255
						ifTrue: [d at: i put: (self swapRB: t) asUInt32]
						ifFalse: [t ~= 0 ifTrue: [d at: i put: (self over: (d at: i) color: (self swapRB: t) asUInt32)]]]]
			ifFalse: [
				(rows over: d texels: s count: n swap: false) to: n - 1 do: [:i |
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
	| m src k cover au cell variant dx dy ix iy on s diagonal |
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
														diagonal := dx + dy.
														diagonal := diagonal max: 0.
														on := ((diagonal quo: cell) bitAnd: 1) = 0]
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
texelIndex: i size: n
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
		^self texelX: (self texelIndex: (self floorOf: u) size: rsTexW) y: (self texelIndex: (self floorOf: v) size: rsTexH)].
	uu := u - 0.5.
	vv := v - 0.5.
	x := self floorOf: uu.
	y := self floorOf: vv.
	fx := self floorOf: ((uu - x asFloat) * 256.0) + 0.5.
	fy := self floorOf: ((vv - y asFloat) * 256.0) + 0.5.
	x0 := self texelIndex: x size: rsTexW.
	x1 := self texelIndex: x + 1 size: rsTexW.
	y0 := self texelIndex: y size: rsTexH.
	y1 := self texelIndex: y + 1 size: rsTexH.
	^self bilinear: (self texelX: x0 y: y0) with: (self texelX: x1 y: y0) with: (self texelX: x0 y: y1) with: (self texelX: x1 y: y1) fx: fx fy: fy
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
		f := self cCoerce: base + ((k + j) * RS_STRIDE) to: 'float *'.
		u := self cCoerce: base + ((k + j) * RS_STRIDE) to: 'uint32_t *'.
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
	flat := ((self cCoerce: base + ((k + 1) * RS_STRIDE) to: 'uint32_t *') at: 6) = ((self cCoerce: base + (k * RS_STRIDE) to: 'uint32_t *') at: 6)
		and: [((self cCoerce: base + ((k + 2) * RS_STRIDE) to: 'uint32_t *') at: 6) = ((self cCoerce: base + (k * RS_STRIDE) to: 'uint32_t *') at: 6)].
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

!PlatformRaster methodsFor: 'blits'!
blitPixels: src width: srcW height: srcH format: srcFmt rect: sr to: dst width: dstW height: dstH format: dstFmt rect: dr linear: linear
	"Rects: x y w h. Like SDL_BlitGPUTexture: each destination pixel of dr samples the source at its centre mapped into sr (nearest, or linear; clamped to the source's edge), converted to the destination's format."
	<function>
	<var: #src type: 'uint8_t *'>
	<var: #srcW type: 'int64_t'>
	<var: #srcH type: 'int64_t'>
	<var: #srcFmt type: 'int32_t'>
	<var: #sr type: 'int64_t *'>
	<var: #dst type: 'uint8_t *'>
	<var: #dstW type: 'int64_t'>
	<var: #dstH type: 'int64_t'>
	<var: #dstFmt type: 'int32_t'>
	<var: #dr type: 'int64_t *'>
	<var: #linear type: 'bool'>
	| sx sy sw sh dx dy dw dh x0 y0 x1 y1 sbpp tbpp same d v u p |
	sx := sr at: 0.
	sy := sr at: 1.
	sw := sr at: 2.
	sh := sr at: 3.
	dx := dr at: 0.
	dy := dr at: 1.
	dw := dr at: 2.
	dh := dr at: 3.
	(sw <= 0 or: [sh <= 0 or: [dw <= 0 or: [dh <= 0]]]) ifTrue: [^self].
	x0 := dx max: 0.
	y0 := dy max: 0.
	x1 := dx + dw.
	x1 := x1 min: dstW.
	y1 := dy + dh.
	y1 := y1 min: dstH.
	sbpp := (self pixelBytes: srcFmt) asInt64.
	tbpp := (self pixelBytes: dstFmt) asInt64.
	rsTex := src.
	rsTexW := srcW.
	rsTexH := srcH.
	rsTexFmt := srcFmt.
	rsLinear := linear.
	rsRepeat := false.
	rsFmt := PF_TEX_RGBA8.
	same := sw = dw and: [sh = dh and: [sx >= 0 and: [sy >= 0 and: [sx + sw <= rsTexW and: [sy + sh <= rsTexH]]]]].
	y0 to: y1 - 1 do: [:py |
		d := dst + ((((py * dstW) + x0) * tbpp) asUInt64).
		same
			ifTrue: [
				self convert: d format: dstFmt
					from: rsTex + (((((py - dy + sy) * rsTexW) + (x0 - dx + sx)) * sbpp) asUInt64) format: srcFmt
					count: x1 - x0]
			ifFalse: [
				v := sy asFloat + ((((py asFloat + 0.5) - dy asFloat) * sh asFloat) / dh asFloat).
				x0 to: x1 - 1 do: [:px |
					u := sx asFloat + ((((px asFloat + 0.5) - dx asFloat) * sw asFloat) / dw asFloat).
					p := self sampleU: u v: v.
					dstFmt = PF_TEX_R8
						ifTrue: [d at: px - x0 put: (p bitAnd: 255)]
						ifFalse: [
							(self cCoerce: d to: 'uint32_t *')
								at: px - x0
								put: (dstFmt = PF_TEX_BGRA8 ifTrue: [(self swapRB: p) asUInt32] ifFalse: [p])]]]]
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
		libc memcpy: d from: s size: (n * (self pixelBytes: sf) asInt64) asUInt64.
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
	(rows swap: d4 from: s4 count: n) to: n - 1 do: [:i | d4 at: i put: (self swapRB: (s4 at: i)) asUInt32]
! !

VMStruct subclass: #RasterState
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

RasterState comment: 'What a draw of PlatformRaster needs: the target (pixels, size, format), the pipeline''s blend, the scissor and viewport (pixels), the vertex uniforms (viewSize: the viewport in the vertices'' units, translate: added to their positions), the texture of slot 0 (NULL: none) and its sampler.'!

!RasterState class methodsFor: 'declaring'!
fields
	^#((pixels 'uint8_t *') (width int64_t) (height int64_t) (format int32_t) (blend int32_t)
		(scissorX int64_t) (scissorY int64_t) (scissorW int64_t) (scissorH int64_t)
		(viewportX double) (viewportY double) (viewportW double) (viewportH double)
		(viewSizeX double) (viewSizeY double) (translateX double) (translateY double)
		(texture 'uint8_t *') (textureWidth int64_t) (textureHeight int64_t) (textureFormat int32_t) (linear bool) (wrap bool))
! !
