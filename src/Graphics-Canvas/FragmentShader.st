Object subclass: #FragmentShader
	instanceVariableNames: 'device source pipeline failedSource texture rendered renderedGeneration size'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

FragmentShader comment: 'I render a fragment shader over the whole of a texture of mine: pictures computed on the GPU, drawn with Canvas>>image:in: like a Form. imageExtent:source:uniforms: answers a ShaderImage, one frame: what it shows is rendered when the Renderer first draws it, and again only when my texture lost its contents (a new session).

The source is in my device''s shaderLanguage. MSL (Metal): a fragment function named fmain after my prelude (metal_stdlib, and the struct ShaderIn: pos, uv 0..1 from the top-left, size in pixels); its uniforms are [[buffer(0)]]:

	fragment float4 fmain(ShaderIn in [[stage_in]], constant float4 &tint [[buffer(0)]]) { return tint; }

GLSL (Vulkan): main after my glslPrelude (#version 450; the inputs uv, 0..1 from the top-left, and size in pixels; the output fragColor; gl_FragCoord is pos); its uniforms are a block at set 3, binding 0:

	layout(set = 3, binding = 0) uniform U { vec4 tint; };
	void main() { fragColor = tint; }

Its output is premultiplied RGBA. A new source builds a new pipeline before the next frame; if it does not compile the old one stays and Renderer reportShaderError: gets the error.'!

!FragmentShader methodsFor: 'initialization'!
setDevice: aDevice
	device := aDevice.
	size := ByteArray new: 16
! !

!FragmentShader methodsFor: 'accessing'!
device
	^device
!
texture
	^texture
! !

!FragmentShader methodsFor: 'images'!
imageExtent: aPoint source: aString uniforms: aByteArray
	"A frame of aPoint pixels, rendered from aString (in my device's shaderLanguage) with aByteArray (16-byte padded) as its uniforms."
	^ShaderImage new setShader: self extent: aPoint source: aString uniforms: aByteArray
! !

!FragmentShader methodsFor: 'rendering'!
textureFor: aShaderImage
	"My texture showing aShaderImage, rendered unless it already does."
	(texture isNil or: [texture extent ~= aShaderImage extent]) ifTrue: [
		texture isNil ifFalse: [texture release].
		texture := device textureWidth: aShaderImage width height: aShaderImage height format: #rgba8 usage: #(#sampler #colorTarget).
		rendered := nil].
	(rendered == aShaderImage and: [renderedGeneration = texture generation]) ifTrue: [^texture].
	self updatePipeline: aShaderImage source.
	pipeline isNil ifFalse: [self render: aShaderImage].
	rendered := aShaderImage.
	renderedGeneration := texture generation.
	^texture
!
render: aShaderImage
	"In a command buffer of my own: it is submitted before the one drawing the frame."
	| cmd pass |
	cmd := device commandBuffer.
	size float32At: 1 put: aShaderImage width asFloat.
	size float32At: 5 put: aShaderImage height asFloat.
	cmd pushVertexUniforms: size slot: 0.
	cmd pushFragmentUniforms: aShaderImage uniforms slot: 0.
	pass := cmd beginPassOn: texture clear: #(0.0 0.0 0.0 0.0).
	pass pipeline: pipeline.
	pass draw: 3 from: 0.
	pass end.
	cmd submit
! !

!FragmentShader methodsFor: 'pipeline'!
updatePipeline: aString
	| new |
	(aString == source or: [aString == failedSource]) ifTrue: [^self].
	new := [(self pipelineFrom: aString) handle; yourself]
		on: Error
		do: [:e | Renderer reportShaderError: e. e return: nil].
	new isNil ifTrue: [^failedSource := aString].
	pipeline isNil ifFalse: [pipeline release].
	pipeline := new.
	source := aString
!
pipelineFrom: aString
	| vs fs |
	device shaderLanguage == #glsl
		ifTrue: [
			vs := device shaderSource: self class glslVertexSource entry: 'main' stage: #vertex samplers: 0 uniformBuffers: 1.
			fs := device shaderSource: self class glslPrelude, aString entry: 'main' stage: #fragment samplers: 0 uniformBuffers: 1]
		ifFalse: [
			vs := device shaderSource: self class prelude, self class vertexSource entry: 'vmain' stage: #vertex samplers: 0 uniformBuffers: 1.
			fs := device shaderSource: self class prelude, aString entry: 'fmain' stage: #fragment samplers: 0 uniformBuffers: 1].
	^device pipelineVertex: vs fragment: fs stride: 0 attributes: #() primitive: #triangles blend: #none format: #rgba8
! !

!FragmentShader methodsFor: 'releasing'!
release
	pipeline isNil ifFalse: [pipeline release].
	texture isNil ifFalse: [texture release].
	pipeline := texture := source := rendered := nil
! !

!FragmentShader class methodsFor: 'instance creation'!
new
	^self on: GPUDevice default
!
on: aDevice
	^self basicNew setDevice: aDevice
! !

!FragmentShader class methodsFor: 'shaders'!
glslPrelude
	"What a GLSL fragment source follows."
	^'#version 450
layout(location = 0) in vec2 uv;
layout(location = 1) flat in vec2 size;
layout(location = 0) out vec4 fragColor;
'
!
glslVertexSource
	"vertexSource in GLSL."
	^'#version 450
layout(location = 0) out vec2 uv;
layout(location = 1) flat out vec2 size;
layout(set = 1, binding = 0) uniform U { vec2 targetSize; };
void main() {
	uint vid = uint(gl_VertexIndex);
	vec2 k = vec2(float((vid << 1) & 2u), float(vid & 2u));
	gl_Position = vec4(k.x * 2.0 - 1.0, 1.0 - k.y * 2.0, 0.0, 1.0);
	uv = k;
	size = targetSize;
}
'
!
prelude
	^'#include <metal_stdlib>
using namespace metal;
struct ShaderIn { float4 pos [[position]]; float2 uv; float2 size [[flat]]; };
'
!
vertexSource
	"One triangle covering the target."
	^'vertex ShaderIn vmain(uint vid [[vertex_id]], constant float2 &size [[buffer(0)]]) {
	ShaderIn o;
	float2 k = float2((vid << 1) & 2u, vid & 2u);
	o.pos = float4(k.x * 2.0 - 1.0, 1.0 - k.y * 2.0, 0.0, 1.0);
	o.uv = k;
	o.size = size;
	return o;
}
'
! !
