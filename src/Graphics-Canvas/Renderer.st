Object subclass: #Renderer
	instanceVariableNames: 'device pipeline nearestSampler linearSampler vertexBuffer bufferOffset commandBuffer white uniforms sourceGeneration pipelineVersion'
	classVariableNames: 'Default SourceGeneration ShaderErrorHandler'
	package: 'Graphics-Canvas'!

Renderer comment: 'I draw DisplayLists with the GPU: one uber-shader (MSL source below, and glslShaderSource for Vulkan) whose modes are solid, glyph (R8 coverage), image (premultiplied RGBA), halftone, stripes and antialiased lines; premultiplied-alpha blending into RGBA8 targets. Each DisplayList is uploaded into my vertex buffer at its own offset within a command buffer (uploads to one range would otherwise overwrite each other before the submit), then encoded batch by batch (texture, scissor, and the batch''s translation as a vertex uniform).

	Renderer default render: aDisplayList on: aSurface clear: Color white

My shaders are Smalltalk source: when my methods change (SystemChanges), every Renderer builds its pipeline again before its next render. If the new source does not compile, I keep the old pipeline and pass the error to the shaderErrorHandler (UI-Windows shows it as a toast). pipelineVersion counts the pipelines built, so the Compositor knows when to render its cached layers again.'!

!Renderer methodsFor: 'initialization'!
setDevice: aDevice
	device := aDevice.
	pipeline := self pipelineFrom: (self class shaderSourceFor: device shaderLanguage).
	sourceGeneration := self class sourceGeneration.
	pipelineVersion := 1.
	nearestSampler := device samplerLinear: false repeat: false.
	linearSampler := device samplerLinear: true repeat: false.
	vertexBuffer := device vertexBufferSize: 4 * 1024 * 1024.
	bufferOffset := 0.
	white := Form width: 1 height: 1.
	white fill: Color white.
	uniforms := ByteArray new: 16
! !

!Renderer methodsFor: 'accessing'!
device
	^device
!
pipeline
	^pipeline
!
pipelineVersion
	"Incremented whenever my pipeline was rebuilt from changed shader source."
	^pipelineVersion
! !

!Renderer methodsFor: 'pipeline'!
pipelineFrom: source
	| vs fs |
	vs := device shaderSource: source entry: 'vmain' stage: #vertex samplers: 0 uniformBuffers: 1.
	fs := device shaderSource: source entry: 'fmain' stage: #fragment samplers: 1 uniformBuffers: 0.
	^device
		pipelineVertex: vs fragment: fs stride: 40
		attributes: #(#(#float4 0) #(#uint 16) #(#uint 20) #(#ubyte4norm 24) #(#uint 28) #(#float2 32))
		primitive: #triangles blend: #premultiplied format: #rgba8
!
updatePipeline
	"If my shader source changed since my pipeline was built, build it from the new source (compiling it now); keep the old one if that fails. Answer whether the pipeline changed."
	| new |
	sourceGeneration = self class sourceGeneration ifTrue: [^false].
	sourceGeneration := self class sourceGeneration.
	new := [(self pipelineFrom: (self class shaderSourceFor: device shaderLanguage)) handle; yourself]
		on: Error
		do: [:e | self class reportShaderError: e. e return: nil].
	new isNil ifTrue: [^false].
	pipeline := new.
	pipelineVersion := pipelineVersion + 1.
	^true
! !

!Renderer methodsFor: 'rendering'!
render: aDisplayList on: aSurface clear: aColorOrNil
	"Render into aSurface in a command buffer of its own, submitted and waited for."
	| cmd |
	cmd := device commandBuffer.
	self render: aDisplayList into: aSurface texture clear: aColorOrNil commandBuffer: cmd.
	cmd submitWithFence wait
!
render: aDisplayList into: aTexture clear: aColorOrNil commandBuffer: aCommandBuffer
	"Encode a render pass drawing aDisplayList into aTexture (a GPUTexture of format rgba8). aColorOrNil clears first; nil keeps the contents."
	^self render: aDisplayList into: aTexture clear: aColorOrNil commandBuffer: aCommandBuffer within: nil
!
fill: scissors color: aColor into: aTexture commandBuffer: aCommandBuffer
	"Encode a render pass filling the rectangles scissors ({x. y. width. height} device pixels) of aTexture with aColor, as a clear would (an opaque color: blending over anything leaves it)."
	| c |
	c := Canvas extent: aTexture width @ aTexture height scale: 1.
	scissors do: [:s | c fillRect: ((s at: 1) @ (s at: 2) extent: (s at: 3) @ (s at: 4)) color: aColor].
	self render: c displayList into: aTexture clear: nil commandBuffer: aCommandBuffer
!
render: aDisplayList into: aTexture clear: aColorOrNil commandBuffer: aCommandBuffer within: scissorsOrNil
	"The same, drawing only inside the rectangles scissorsOrNil ({x. y. width. height} device pixels; nil: everywhere): each batch once per rectangle, its clip cut to it, those it leaves nothing of skipped. Inside them the pixels are those of drawing everywhere (damage-limited rendering, DamageRegion)."
	| byteCount offset textures pass w h tx ty |
	sourceGeneration = SourceGeneration ifFalse: [self updatePipeline].
	commandBuffer := aCommandBuffer.
	byteCount := aDisplayList byteCount.
	offset := self reserve: byteCount.
	byteCount > 0 ifTrue: [vertexBuffer upload: aDisplayList vertices count: byteCount offset: offset].
	textures := aDisplayList batches collect: [:each |
		(each texture ifNil: [white]) textureOn: device].
	w := aTexture width.
	h := aTexture height.
	uniforms float32At: 1 put: w.
	uniforms float32At: 5 put: h.
	uniforms float32At: 9 put: 0.0.
	uniforms float32At: 13 put: 0.0.
	tx := 0.
	ty := 0.
	aCommandBuffer pushVertexUniforms: uniforms slot: 0.
	pass := aCommandBuffer beginPassOn: aTexture clear: (aColorOrNil ifNotNil: [:c | c asArray]).
	aDisplayList batches isEmpty ifFalse: [
		pass pipeline: pipeline.
		pass vertexBuffer: vertexBuffer offset: offset.
		(scissorsOrNil ifNil: [#(nil)]) do: [:within |
			aDisplayList batches doWithIndex: [:each :i |
				| s |
				s := each scissor.
				within isNil ifFalse: [s := self cut: (s ifNil: [Array with: 0 with: 0 with: w with: h]) to: within].
				s == #none ifFalse: [
					s isNil
						ifTrue: [pass scissorX: 0 y: 0 width: w height: h]
						ifFalse: [self scissor: s on: pass width: w height: h].
					(each dx = tx and: [each dy = ty]) ifFalse: [
						tx := each dx.
						ty := each dy.
						uniforms float32At: 9 put: tx asFloat.
						uniforms float32At: 13 put: ty asFloat.
						aCommandBuffer pushVertexUniforms: uniforms slot: 0].
					pass texture: (textures at: i)
						sampler: ((each texture ifNil: [white]) isLinearFiltered ifTrue: [linearSampler] ifFalse: [nearestSampler])
						slot: 0.
					pass draw: each count from: each first]]]].
	pass end
! !

!Renderer methodsFor: 'private'!
reserve: byteCount
	"Answer the offset of byteCount free bytes in the vertex buffer, used as a ring: the lists of the frames in flight keep their bytes (an upload into a range a submitted command buffer still reads would race with it; damage-limited frames draw different lists from frame to frame, and a frame's pixels stay). Replace the buffer by a larger one when a list takes more than a quarter of it."
	| offset size |
	offset := bufferOffset.
	byteCount * 4 > vertexBuffer size ifTrue: [
		size := vertexBuffer size.
		[size < (byteCount * 4)] whileTrue: [size := size * 2].
		vertexBuffer release.
		vertexBuffer := device vertexBufferSize: size.
		offset := 0].
	offset + byteCount > vertexBuffer size ifTrue: [offset := 0].
	bufferOffset := offset + byteCount + 255 // 256 * 256.
	^offset
!
cut: a to: b
	"The intersection of the rectangles a and b ({x. y. width. height}), or #none."
	| x y x1 y1 |
	x := (a at: 1) max: (b at: 1).
	y := (a at: 2) max: (b at: 2).
	x1 := (a at: 1) + (a at: 3) min: (b at: 1) + (b at: 3).
	y1 := (a at: 2) + (a at: 4) min: (b at: 2) + (b at: 4).
	(x < x1 and: [y < y1]) ifFalse: [^#none].
	^Array with: x with: y with: x1 - x with: y1 - y
!
scissor: anArray on: aPass width: w height: h
	| x y x1 y1 |
	x := (anArray at: 1) max: 0.
	y := (anArray at: 2) max: 0.
	x1 := (anArray at: 1) + (anArray at: 3) min: w.
	y1 := (anArray at: 2) + (anArray at: 4) min: h.
	aPass scissorX: x y: y width: (x1 - x max: 0) height: (y1 - y max: 0)
! !

!Renderer class methodsFor: 'instance creation'!
on: aDevice
	^self new setDevice: aDevice
!
default
	(Default isNil or: [Default device ~~ GPUDevice default]) ifTrue: [Default := self on: GPUDevice default].
	^Default
! !

!Renderer class methodsFor: 'class initialization'!
initialize
	SystemChanges subscribe: #Renderer do: [:change |
		(change affects: Renderer) ifTrue: [self shaderSourceChanged]].
	"The image keeps the uber-shader's SPIR-V, so it starts without compiling it (GPUShader)."
	Smalltalk addStage2Step: [GPUShader forgetCompiled; precompile: self glslShaderSource] named: 'Shaders'
! !

!Renderer class methodsFor: 'shader changes'!
sourceGeneration
	^SourceGeneration ifNil: [SourceGeneration := 0]
!
shaderSourceChanged
	"My shader source may have changed: every Renderer rebuilds its pipeline before its next render."
	SourceGeneration := self sourceGeneration + 1
!
shaderErrorHandler
	^ShaderErrorHandler
!
shaderErrorHandler: aBlockOrNil
	"aBlockOrNil receives the error (a GPUError with the Metal log, or any Error) when changed shader source does not build; nil: the Transcript."
	ShaderErrorHandler := aBlockOrNil
!
reportShaderError: anError
	| text |
	text := 'Shader not rebuilt (keeping the old pipeline): ', anError messageText asString.
	ShaderErrorHandler isNil ifFalse: [^ShaderErrorHandler value: anError].
	Transcript show: text; cr
! !

!Renderer class methodsFor: 'shaders'!
shaderSourceFor: aLanguage
	"The uber-shader in aLanguage (GPUDevice>>shaderLanguage)."
	^aLanguage == #glsl ifTrue: [self glslShaderSource] ifFalse: [self shaderSource]
!
glslShaderSource
	"shaderSource in GLSL (Vulkan): both stages, chosen by SAMALTAK_VERTEX / SAMALTAK_FRAGMENT."
	^'#version 450

#ifdef SAMALTAK_VERTEX
layout(location = 0) in vec4 rect;
layout(location = 1) in uint uv0;
layout(location = 2) in uint uv1;
layout(location = 3) in vec4 color;
layout(location = 4) in uint mode;
layout(location = 5) in vec2 origin;
layout(location = 0) out vec2 vUv;
layout(location = 1) out vec4 vColor;
layout(location = 2) flat out vec2 vOrg;
layout(location = 3) flat out uint vMode;
layout(set = 1, binding = 0) uniform U { vec2 viewport; vec2 translation; } u;

void main() {
	vec2 p;
	if ((mode & 0x80000000u) !!= 0u) {
		p = rect.xy;
		vUv = vec2(uintBitsToFloat(uv0), uintBitsToFloat(uv1));
	} else {
		uint c = uint(gl_VertexIndex) % 6u;
		vec2 k = vec2((c == 1u || c == 3u || c == 4u) ? 1.0 : 0.0, (c == 2u || c == 4u || c == 5u) ? 1.0 : 0.0);
		p = mix(rect.xy, rect.zw, k);
		vec2 a = vec2(float(uv0 & 0xFFFFu), float(uv0 >> 16));
		vec2 b = vec2(float(uv1 & 0xFFFFu), float(uv1 >> 16));
		vUv = mix(a, b, k);
	}
	p += origin + u.translation;
	gl_Position = vec4(p.x / u.viewport.x * 2.0 - 1.0, 1.0 - p.y / u.viewport.y * 2.0, 0.0, 1.0);
	vOrg = rect.xy + origin + u.translation;
	vColor = color;
	vMode = mode;
}
#endif

#ifdef SAMALTAK_FRAGMENT
layout(location = 0) in vec2 vUv;
layout(location = 1) in vec4 vColor;
layout(location = 2) flat in vec2 vOrg;
layout(location = 3) flat in uint vMode;
layout(location = 0) out vec4 fragColor;
layout(set = 2, binding = 0) uniform sampler2D tex;

vec4 shade() {
	uint m = vMode & 0xFFu;
	if (m == 0u) return vColor;
	if (m == 1u) {
		vec2 size = vec2(textureSize(tex, 0));
		return vColor * textureLod(tex, vUv / size, 0.0).r;
	}
	if (m == 2u) {
		vec2 size = vec2(textureSize(tex, 0));
		return textureLod(tex, vUv / size, 0.0) * vColor.a;
	}
	if (m == 5u) {
		float cover = clamp(vUv.y + 0.5 - abs(vUv.x), 0.0, 1.0);
		return vColor * cover;
	}
	uint cell = max((vMode >> 8) & 0xFFu, 1u);
	uint variant = (vMode >> 16) & 0xFFu;
	vec2 d = floor(gl_FragCoord.xy - vOrg);
	uint ix = uint(max(d.x, 0.0)) / cell;
	uint iy = uint(max(d.y, 0.0)) / cell;
	bool on;
	if (m == 3u) {
		on = variant == 1u ? ((ix + iy) & 1u) == 0u : ((ix & 1u) == 1u && (iy & 1u) == 1u);
	} else {
		if (variant == 1u) on = (ix & 1u) == 0u;
		else if (variant == 2u) on = ((uint(max(d.x + d.y, 0.0)) / cell) & 1u) == 0u;
		else on = (iy & 1u) == 0u;
	}
	return on ? vColor : vec4(0.0);
}

void main() {
	fragColor = shade();
}
#endif
'
!
shaderSource
	"The uber-shader. Vertex: pick the quad corner from the vertex index (all six vertices of a quad are equal), or take the explicit position (bit 31 of mode), then add the origin and the batch's translation. Fragment: by mode."
	^'#include <metal_stdlib>
using namespace metal;

struct VIn {
	float4 rect [[attribute(0)]];
	uint uv0 [[attribute(1)]];
	uint uv1 [[attribute(2)]];
	float4 color [[attribute(3)]];
	uint mode [[attribute(4)]];
	float2 origin [[attribute(5)]];
};
struct VOut {
	float4 pos [[position]];
	float2 uv;
	float4 color;
	float2 org [[flat]];
	uint mode [[flat]];
};
struct U { float2 viewport; float2 translation; };

vertex VOut vmain(VIn in [[stage_in]], uint vid [[vertex_id]], constant U &u [[buffer(0)]]) {
	VOut o;
	float2 p;
	if (in.mode & 0x80000000u) {
		p = in.rect.xy;
		o.uv = float2(as_type<float>(in.uv0), as_type<float>(in.uv1));
	} else {
		uint c = vid % 6u;
		float2 k = float2((c == 1u || c == 3u || c == 4u) ? 1.0 : 0.0, (c == 2u || c == 4u || c == 5u) ? 1.0 : 0.0);
		p = mix(in.rect.xy, in.rect.zw, k);
		float2 a = float2(float(in.uv0 & 0xFFFFu), float(in.uv0 >> 16));
		float2 b = float2(float(in.uv1 & 0xFFFFu), float(in.uv1 >> 16));
		o.uv = mix(a, b, k);
	}
	p += in.origin + u.translation;
	o.pos = float4(p.x / u.viewport.x * 2.0 - 1.0, 1.0 - p.y / u.viewport.y * 2.0, 0.0, 1.0);
	o.org = in.rect.xy + in.origin + u.translation;
	o.color = in.color;
	o.mode = in.mode;
	return o;
}

fragment float4 fmain(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler s [[sampler(0)]]) {
	uint m = in.mode & 0xFFu;
	if (m == 0u) return in.color;
	if (m == 1u) {
		float2 size = float2(tex.get_width(), tex.get_height());
		return in.color * tex.sample(s, in.uv / size).r;
	}
	if (m == 2u) {
		float2 size = float2(tex.get_width(), tex.get_height());
		return tex.sample(s, in.uv / size) * in.color.a;
	}
	if (m == 5u) {
		float cover = clamp(in.uv.y + 0.5 - abs(in.uv.x), 0.0, 1.0);
		return in.color * cover;
	}
	uint cell = max((in.mode >> 8) & 0xFFu, 1u);
	uint variant = (in.mode >> 16) & 0xFFu;
	float2 d = floor(in.pos.xy - in.org);
	uint ix = uint(max(d.x, 0.0)) / cell;
	uint iy = uint(max(d.y, 0.0)) / cell;
	bool on;
	if (m == 3u) {
		on = variant == 1u ? ((ix + iy) & 1u) == 0u : ((ix & 1u) == 1u && (iy & 1u) == 1u);
	} else {
		if (variant == 1u) on = (ix & 1u) == 0u;
		else if (variant == 2u) on = ((uint(max(d.x + d.y, 0.0)) / cell) & 1u) == 0u;
		else on = (iy & 1u) == 0u;
	}
	return on ? in.color : float4(0.0);
}
'
! !
