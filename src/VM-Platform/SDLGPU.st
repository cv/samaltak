CLibrary subclass: #SDLGPU
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

SDLGPU comment: 'The SDL_GPU functions of the platform layer (Metal on macOS, Vulkan on Linux): devices, shaders, pipelines, textures, samplers, buffers, transfers, passes, fences. Not simulated.'!

!SDLGPU class methodsFor: 'declaring'!
headers
	^#('<SDL3/SDL.h>')
!
typedefs
	^#((SDL_GPUDevice opaque) (SDL_GPUShader opaque) (SDL_GPUGraphicsPipeline opaque) (SDL_GPUTexture opaque) (SDL_GPUSampler opaque)
		(SDL_GPUBuffer opaque) (SDL_GPUTransferBuffer opaque) (SDL_GPUCommandBuffer opaque) (SDL_GPURenderPass opaque)
		(SDL_GPUCopyPass opaque) (SDL_GPUFence opaque)
		(SDL_PropertiesID uint32_t) (SDL_GPUShaderFormat uint32_t) (SDL_GPUShaderStage uint32_t) (SDL_GPUTextureFormat uint32_t)
		(SDL_GPUTextureType uint32_t) (SDL_GPUTextureUsageFlags uint32_t) (SDL_GPUSampleCount uint32_t) (SDL_GPUPresentMode uint32_t)
		(SDL_GPUSwapchainComposition uint32_t) (SDL_GPUVertexElementFormat uint32_t) (SDL_GPUVertexInputRate uint32_t)
		(SDL_GPUPrimitiveType uint32_t) (SDL_GPUFillMode uint32_t) (SDL_GPUCullMode uint32_t) (SDL_GPUFrontFace uint32_t)
		(SDL_GPUBlendFactor uint32_t) (SDL_GPUBlendOp uint32_t) (SDL_GPUColorComponentFlags uint8_t) (SDL_GPUFilter uint32_t)
		(SDL_GPUSamplerMipmapMode uint32_t) (SDL_GPUSamplerAddressMode uint32_t) (SDL_GPUCompareOp uint32_t)
		(SDL_GPUBufferUsageFlags uint32_t) (SDL_GPUTransferBufferUsage uint32_t) (SDL_GPULoadOp uint32_t) (SDL_GPUStoreOp uint32_t)
		(SDL_FlipMode uint32_t))
! !

!SDLGPU methodsFor: 'simulation'!
notSimulated
	^self error: 'SDL_GPU is not simulated'
! !

!SDLGPU methodsFor: 'devices'!
createDevice: formatFlags debug: debugMode name: name
	<c: 'SDL_GPUDevice *SDL_CreateGPUDevice(SDL_GPUShaderFormat format_flags, bool debug_mode, const char *name)'>
	^self notSimulated
!
shaderFormats: device
	<c: 'SDL_GPUShaderFormat SDL_GetGPUShaderFormats(SDL_GPUDevice *device)'>
	^self notSimulated
!
destroyDevice: device
	<c: 'void SDL_DestroyGPUDevice(SDL_GPUDevice *device)'>
	^self notSimulated
!
waitForIdle: device
	<c: 'bool SDL_WaitForGPUIdle(SDL_GPUDevice *device)'>
	^self notSimulated
!
claimWindow: device window: window
	<c: 'bool SDL_ClaimWindowForGPUDevice(SDL_GPUDevice *device, SDL_Window *window)'>
	^self notSimulated
!
releaseWindow: device window: window
	<c: 'void SDL_ReleaseWindowFromGPUDevice(SDL_GPUDevice *device, SDL_Window *window)'>
	^self notSimulated
!
windowSupportsPresentMode: device window: window mode: presentMode
	<c: 'bool SDL_WindowSupportsGPUPresentMode(SDL_GPUDevice *device, SDL_Window *window, SDL_GPUPresentMode present_mode)'>
	^self notSimulated
!
setSwapchainParameters: device window: window composition: composition mode: presentMode
	<c: 'bool SDL_SetGPUSwapchainParameters(SDL_GPUDevice *device, SDL_Window *window, SDL_GPUSwapchainComposition swapchain_composition, SDL_GPUPresentMode present_mode)'>
	^self notSimulated
!
swapchainTextureFormat: device window: window
	<c: 'SDL_GPUTextureFormat SDL_GetGPUSwapchainTextureFormat(SDL_GPUDevice *device, SDL_Window *window)'>
	^self notSimulated
!
SDL_GPU_SHADERFORMAT_SPIRV
	<cMacro: 'SDL_GPUShaderFormat SDL_GPU_SHADERFORMAT_SPIRV'>
	^self notSimulated
!
SDL_GPU_SHADERFORMAT_MSL
	<cMacro: 'SDL_GPUShaderFormat SDL_GPU_SHADERFORMAT_MSL'>
	^self notSimulated
!
SDL_GPU_PRESENTMODE_VSYNC
	<cMacro: 'SDL_GPUPresentMode SDL_GPU_PRESENTMODE_VSYNC'>
	^self notSimulated
!
SDL_GPU_PRESENTMODE_IMMEDIATE
	<cMacro: 'SDL_GPUPresentMode SDL_GPU_PRESENTMODE_IMMEDIATE'>
	^self notSimulated
!
SDL_GPU_PRESENTMODE_MAILBOX
	<cMacro: 'SDL_GPUPresentMode SDL_GPU_PRESENTMODE_MAILBOX'>
	^self notSimulated
!
SDL_GPU_SWAPCHAINCOMPOSITION_SDR
	<cMacro: 'SDL_GPUSwapchainComposition SDL_GPU_SWAPCHAINCOMPOSITION_SDR'>
	^self notSimulated
! !

!SDLGPU methodsFor: 'resources'!
createShader: device info: createinfo
	<c: 'SDL_GPUShader *SDL_CreateGPUShader(SDL_GPUDevice *device, const SDL_GPUShaderCreateInfo *createinfo)'>
	^self notSimulated
!
createGraphicsPipeline: device info: createinfo
	<c: 'SDL_GPUGraphicsPipeline *SDL_CreateGPUGraphicsPipeline(SDL_GPUDevice *device, const SDL_GPUGraphicsPipelineCreateInfo *createinfo)'>
	^self notSimulated
!
createTexture: device info: createinfo
	<c: 'SDL_GPUTexture *SDL_CreateGPUTexture(SDL_GPUDevice *device, const SDL_GPUTextureCreateInfo *createinfo)'>
	^self notSimulated
!
createSampler: device info: createinfo
	<c: 'SDL_GPUSampler *SDL_CreateGPUSampler(SDL_GPUDevice *device, const SDL_GPUSamplerCreateInfo *createinfo)'>
	^self notSimulated
!
createBuffer: device info: createinfo
	<c: 'SDL_GPUBuffer *SDL_CreateGPUBuffer(SDL_GPUDevice *device, const SDL_GPUBufferCreateInfo *createinfo)'>
	^self notSimulated
!
createTransferBuffer: device info: createinfo
	<c: 'SDL_GPUTransferBuffer *SDL_CreateGPUTransferBuffer(SDL_GPUDevice *device, const SDL_GPUTransferBufferCreateInfo *createinfo)'>
	^self notSimulated
!
releaseShader: device shader: shader
	<c: 'void SDL_ReleaseGPUShader(SDL_GPUDevice *device, SDL_GPUShader *shader)'>
	^self notSimulated
!
releaseGraphicsPipeline: device pipeline: pipeline
	<c: 'void SDL_ReleaseGPUGraphicsPipeline(SDL_GPUDevice *device, SDL_GPUGraphicsPipeline *graphics_pipeline)'>
	^self notSimulated
!
releaseTexture: device texture: texture
	<c: 'void SDL_ReleaseGPUTexture(SDL_GPUDevice *device, SDL_GPUTexture *texture)'>
	^self notSimulated
!
releaseSampler: device sampler: sampler
	<c: 'void SDL_ReleaseGPUSampler(SDL_GPUDevice *device, SDL_GPUSampler *sampler)'>
	^self notSimulated
!
releaseBuffer: device buffer: buffer
	<c: 'void SDL_ReleaseGPUBuffer(SDL_GPUDevice *device, SDL_GPUBuffer *buffer)'>
	^self notSimulated
!
releaseTransferBuffer: device buffer: transferBuffer
	<c: 'void SDL_ReleaseGPUTransferBuffer(SDL_GPUDevice *device, SDL_GPUTransferBuffer *transfer_buffer)'>
	^self notSimulated
!
releaseFence: device fence: fence
	<c: 'void SDL_ReleaseGPUFence(SDL_GPUDevice *device, SDL_GPUFence *fence)'>
	^self notSimulated
!
mapTransferBuffer: device buffer: transferBuffer cycle: cycle
	<c: 'void *SDL_MapGPUTransferBuffer(SDL_GPUDevice *device, SDL_GPUTransferBuffer *transfer_buffer, bool cycle)'>
	^self notSimulated
!
unmapTransferBuffer: device buffer: transferBuffer
	<c: 'void SDL_UnmapGPUTransferBuffer(SDL_GPUDevice *device, SDL_GPUTransferBuffer *transfer_buffer)'>
	^self notSimulated
!
SDL_GPU_SHADERSTAGE_VERTEX
	<cMacro: 'SDL_GPUShaderStage SDL_GPU_SHADERSTAGE_VERTEX'>
	^self notSimulated
!
SDL_GPU_SHADERSTAGE_FRAGMENT
	<cMacro: 'SDL_GPUShaderStage SDL_GPU_SHADERSTAGE_FRAGMENT'>
	^self notSimulated
!
SDL_GPU_TEXTUREFORMAT_INVALID
	<cMacro: 'SDL_GPUTextureFormat SDL_GPU_TEXTUREFORMAT_INVALID'>
	^self notSimulated
!
SDL_GPU_TEXTUREFORMAT_R8_UNORM
	<cMacro: 'SDL_GPUTextureFormat SDL_GPU_TEXTUREFORMAT_R8_UNORM'>
	^self notSimulated
!
SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM
	<cMacro: 'SDL_GPUTextureFormat SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM'>
	^self notSimulated
!
SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM
	<cMacro: 'SDL_GPUTextureFormat SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM'>
	^self notSimulated
!
SDL_GPU_TEXTURETYPE_2D
	<cMacro: 'SDL_GPUTextureType SDL_GPU_TEXTURETYPE_2D'>
	^self notSimulated
!
SDL_GPU_TEXTUREUSAGE_SAMPLER
	<cMacro: 'SDL_GPUTextureUsageFlags SDL_GPU_TEXTUREUSAGE_SAMPLER'>
	^self notSimulated
!
SDL_GPU_TEXTUREUSAGE_COLOR_TARGET
	<cMacro: 'SDL_GPUTextureUsageFlags SDL_GPU_TEXTUREUSAGE_COLOR_TARGET'>
	^self notSimulated
!
SDL_GPU_VERTEXELEMENTFORMAT_INVALID
	<cMacro: 'SDL_GPUVertexElementFormat SDL_GPU_VERTEXELEMENTFORMAT_INVALID'>
	^self notSimulated
!
SDL_GPU_VERTEXELEMENTFORMAT_FLOAT
	<cMacro: 'SDL_GPUVertexElementFormat SDL_GPU_VERTEXELEMENTFORMAT_FLOAT'>
	^self notSimulated
!
SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2
	<cMacro: 'SDL_GPUVertexElementFormat SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2'>
	^self notSimulated
!
SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3
	<cMacro: 'SDL_GPUVertexElementFormat SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3'>
	^self notSimulated
!
SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4
	<cMacro: 'SDL_GPUVertexElementFormat SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4'>
	^self notSimulated
!
SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM
	<cMacro: 'SDL_GPUVertexElementFormat SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM'>
	^self notSimulated
!
SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4
	<cMacro: 'SDL_GPUVertexElementFormat SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4'>
	^self notSimulated
!
SDL_GPU_VERTEXELEMENTFORMAT_UINT
	<cMacro: 'SDL_GPUVertexElementFormat SDL_GPU_VERTEXELEMENTFORMAT_UINT'>
	^self notSimulated
!
SDL_GPU_VERTEXELEMENTFORMAT_INT
	<cMacro: 'SDL_GPUVertexElementFormat SDL_GPU_VERTEXELEMENTFORMAT_INT'>
	^self notSimulated
!
SDL_GPU_VERTEXINPUTRATE_VERTEX
	<cMacro: 'SDL_GPUVertexInputRate SDL_GPU_VERTEXINPUTRATE_VERTEX'>
	^self notSimulated
!
SDL_GPU_PRIMITIVETYPE_TRIANGLELIST
	<cMacro: 'SDL_GPUPrimitiveType SDL_GPU_PRIMITIVETYPE_TRIANGLELIST'>
	^self notSimulated
!
SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP
	<cMacro: 'SDL_GPUPrimitiveType SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP'>
	^self notSimulated
!
SDL_GPU_PRIMITIVETYPE_LINELIST
	<cMacro: 'SDL_GPUPrimitiveType SDL_GPU_PRIMITIVETYPE_LINELIST'>
	^self notSimulated
!
SDL_GPU_PRIMITIVETYPE_LINESTRIP
	<cMacro: 'SDL_GPUPrimitiveType SDL_GPU_PRIMITIVETYPE_LINESTRIP'>
	^self notSimulated
!
SDL_GPU_PRIMITIVETYPE_POINTLIST
	<cMacro: 'SDL_GPUPrimitiveType SDL_GPU_PRIMITIVETYPE_POINTLIST'>
	^self notSimulated
!
SDL_GPU_FILLMODE_FILL
	<cMacro: 'SDL_GPUFillMode SDL_GPU_FILLMODE_FILL'>
	^self notSimulated
!
SDL_GPU_CULLMODE_NONE
	<cMacro: 'SDL_GPUCullMode SDL_GPU_CULLMODE_NONE'>
	^self notSimulated
!
SDL_GPU_BLENDFACTOR_ONE
	<cMacro: 'SDL_GPUBlendFactor SDL_GPU_BLENDFACTOR_ONE'>
	^self notSimulated
!
SDL_GPU_BLENDFACTOR_SRC_ALPHA
	<cMacro: 'SDL_GPUBlendFactor SDL_GPU_BLENDFACTOR_SRC_ALPHA'>
	^self notSimulated
!
SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA
	<cMacro: 'SDL_GPUBlendFactor SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA'>
	^self notSimulated
!
SDL_GPU_BLENDOP_ADD
	<cMacro: 'SDL_GPUBlendOp SDL_GPU_BLENDOP_ADD'>
	^self notSimulated
!
SDL_GPU_FILTER_NEAREST
	<cMacro: 'SDL_GPUFilter SDL_GPU_FILTER_NEAREST'>
	^self notSimulated
!
SDL_GPU_FILTER_LINEAR
	<cMacro: 'SDL_GPUFilter SDL_GPU_FILTER_LINEAR'>
	^self notSimulated
!
SDL_GPU_SAMPLERMIPMAPMODE_NEAREST
	<cMacro: 'SDL_GPUSamplerMipmapMode SDL_GPU_SAMPLERMIPMAPMODE_NEAREST'>
	^self notSimulated
!
SDL_GPU_SAMPLERADDRESSMODE_REPEAT
	<cMacro: 'SDL_GPUSamplerAddressMode SDL_GPU_SAMPLERADDRESSMODE_REPEAT'>
	^self notSimulated
!
SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE
	<cMacro: 'SDL_GPUSamplerAddressMode SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE'>
	^self notSimulated
!
SDL_GPU_BUFFERUSAGE_VERTEX
	<cMacro: 'SDL_GPUBufferUsageFlags SDL_GPU_BUFFERUSAGE_VERTEX'>
	^self notSimulated
!
SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD
	<cMacro: 'SDL_GPUTransferBufferUsage SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD'>
	^self notSimulated
!
SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD
	<cMacro: 'SDL_GPUTransferBufferUsage SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD'>
	^self notSimulated
! !

!SDLGPU methodsFor: 'commands'!
acquireCommandBuffer: device
	<c: 'SDL_GPUCommandBuffer *SDL_AcquireGPUCommandBuffer(SDL_GPUDevice *device)'>
	^self notSimulated
!
submitCommandBuffer: commandBuffer
	<c: 'bool SDL_SubmitGPUCommandBuffer(SDL_GPUCommandBuffer *command_buffer)'>
	^self notSimulated
!
submitCommandBufferAndAcquireFence: commandBuffer
	<c: 'SDL_GPUFence *SDL_SubmitGPUCommandBufferAndAcquireFence(SDL_GPUCommandBuffer *command_buffer)'>
	^self notSimulated
!
cancelCommandBuffer: commandBuffer
	<c: 'bool SDL_CancelGPUCommandBuffer(SDL_GPUCommandBuffer *command_buffer)'>
	^self notSimulated
!
acquireSwapchainTexture: commandBuffer window: window texture: texture width: w height: h
	<c: 'bool SDL_AcquireGPUSwapchainTexture(SDL_GPUCommandBuffer *command_buffer, SDL_Window *window, SDL_GPUTexture **swapchain_texture, Uint32 *swapchain_texture_width, Uint32 *swapchain_texture_height)'>
	^self notSimulated
!
pushVertexUniformData: commandBuffer slot: slotIndex data: data length: length
	<c: 'void SDL_PushGPUVertexUniformData(SDL_GPUCommandBuffer *command_buffer, Uint32 slot_index, const void *data, Uint32 length)'>
	^self notSimulated
!
pushFragmentUniformData: commandBuffer slot: slotIndex data: data length: length
	<c: 'void SDL_PushGPUFragmentUniformData(SDL_GPUCommandBuffer *command_buffer, Uint32 slot_index, const void *data, Uint32 length)'>
	^self notSimulated
!
blitTexture: commandBuffer info: info
	<c: 'void SDL_BlitGPUTexture(SDL_GPUCommandBuffer *command_buffer, const SDL_GPUBlitInfo *info)'>
	^self notSimulated
!
beginCopyPass: commandBuffer
	<c: 'SDL_GPUCopyPass *SDL_BeginGPUCopyPass(SDL_GPUCommandBuffer *command_buffer)'>
	^self notSimulated
!
endCopyPass: copyPass
	<c: 'void SDL_EndGPUCopyPass(SDL_GPUCopyPass *copy_pass)'>
	^self notSimulated
!
uploadToBuffer: copyPass source: source destination: destination cycle: cycle
	<c: 'void SDL_UploadToGPUBuffer(SDL_GPUCopyPass *copy_pass, const SDL_GPUTransferBufferLocation *source, const SDL_GPUBufferRegion *destination, bool cycle)'>
	^self notSimulated
!
uploadToTexture: copyPass source: source destination: destination cycle: cycle
	<c: 'void SDL_UploadToGPUTexture(SDL_GPUCopyPass *copy_pass, const SDL_GPUTextureTransferInfo *source, const SDL_GPUTextureRegion *destination, bool cycle)'>
	^self notSimulated
!
downloadFromTexture: copyPass source: source destination: destination
	<c: 'void SDL_DownloadFromGPUTexture(SDL_GPUCopyPass *copy_pass, const SDL_GPUTextureRegion *source, const SDL_GPUTextureTransferInfo *destination)'>
	^self notSimulated
!
beginRenderPass: commandBuffer targets: colorTargetInfos count: numColorTargets depthStencil: depthStencilTargetInfo
	<c: 'SDL_GPURenderPass *SDL_BeginGPURenderPass(SDL_GPUCommandBuffer *command_buffer, const SDL_GPUColorTargetInfo *color_target_infos, Uint32 num_color_targets, const void *depth_stencil_target_info)'>
	^self notSimulated
!
endRenderPass: renderPass
	<c: 'void SDL_EndGPURenderPass(SDL_GPURenderPass *render_pass)'>
	^self notSimulated
!
setViewport: renderPass viewport: viewport
	<c: 'void SDL_SetGPUViewport(SDL_GPURenderPass *render_pass, const SDL_GPUViewport *viewport)'>
	^self notSimulated
!
setScissor: renderPass rect: scissor
	<c: 'void SDL_SetGPUScissor(SDL_GPURenderPass *render_pass, const SDL_Rect *scissor)'>
	^self notSimulated
!
bindGraphicsPipeline: renderPass pipeline: pipeline
	<c: 'void SDL_BindGPUGraphicsPipeline(SDL_GPURenderPass *render_pass, SDL_GPUGraphicsPipeline *graphics_pipeline)'>
	^self notSimulated
!
bindVertexBuffers: renderPass firstSlot: firstSlot bindings: bindings count: numBindings
	<c: 'void SDL_BindGPUVertexBuffers(SDL_GPURenderPass *render_pass, Uint32 first_slot, const SDL_GPUBufferBinding *bindings, Uint32 num_bindings)'>
	^self notSimulated
!
bindFragmentSamplers: renderPass firstSlot: firstSlot bindings: bindings count: numBindings
	<c: 'void SDL_BindGPUFragmentSamplers(SDL_GPURenderPass *render_pass, Uint32 first_slot, const SDL_GPUTextureSamplerBinding *texture_sampler_bindings, Uint32 num_bindings)'>
	^self notSimulated
!
drawPrimitives: renderPass vertices: numVertices instances: numInstances firstVertex: firstVertex firstInstance: firstInstance
	<c: 'void SDL_DrawGPUPrimitives(SDL_GPURenderPass *render_pass, Uint32 num_vertices, Uint32 num_instances, Uint32 first_vertex, Uint32 first_instance)'>
	^self notSimulated
!
SDL_GPU_LOADOP_LOAD
	<cMacro: 'SDL_GPULoadOp SDL_GPU_LOADOP_LOAD'>
	^self notSimulated
!
SDL_GPU_LOADOP_CLEAR
	<cMacro: 'SDL_GPULoadOp SDL_GPU_LOADOP_CLEAR'>
	^self notSimulated
!
SDL_GPU_LOADOP_DONT_CARE
	<cMacro: 'SDL_GPULoadOp SDL_GPU_LOADOP_DONT_CARE'>
	^self notSimulated
!
SDL_GPU_STOREOP_STORE
	<cMacro: 'SDL_GPUStoreOp SDL_GPU_STOREOP_STORE'>
	^self notSimulated
! !

!SDLGPU methodsFor: 'fences'!
queryFence: device fence: fence
	<c: 'bool SDL_QueryGPUFence(SDL_GPUDevice *device, SDL_GPUFence *fence)'>
	^self notSimulated
!
waitForFences: device waitAll: waitAll fences: fences count: numFences
	<c: 'bool SDL_WaitForGPUFences(SDL_GPUDevice *device, bool wait_all, SDL_GPUFence **fences, Uint32 num_fences)'>
	^self notSimulated
! !

ExternStruct subclass: #SDLGPUShaderCreateInfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUShaderCreateInfo class methodsFor: 'declaring'!
cName
	^'SDL_GPUShaderCreateInfo'
!
fields
	^#((code_size size_t) (code 'const Uint8 *') (entrypoint 'const char *') (format SDL_GPUShaderFormat) (stage SDL_GPUShaderStage)
		(num_samplers Uint32) (num_storage_textures Uint32) (num_storage_buffers Uint32) (num_uniform_buffers Uint32))
! !

ExternStruct subclass: #SDLGPUVertexAttribute
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUVertexAttribute class methodsFor: 'declaring'!
cName
	^'SDL_GPUVertexAttribute'
!
fields
	^#((location Uint32) (buffer_slot Uint32) (format SDL_GPUVertexElementFormat) (offset Uint32))
! !

ExternStruct subclass: #SDLGPUVertexBufferDescription
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUVertexBufferDescription class methodsFor: 'declaring'!
cName
	^'SDL_GPUVertexBufferDescription'
!
fields
	^#((slot Uint32) (pitch Uint32) (input_rate SDL_GPUVertexInputRate))
! !

ExternStruct subclass: #SDLGPUColorTargetBlendState
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUColorTargetBlendState class methodsFor: 'declaring'!
cName
	^'SDL_GPUColorTargetBlendState'
!
fields
	^#((src_color_blendfactor SDL_GPUBlendFactor) (dst_color_blendfactor SDL_GPUBlendFactor) (color_blend_op SDL_GPUBlendOp)
		(src_alpha_blendfactor SDL_GPUBlendFactor) (dst_alpha_blendfactor SDL_GPUBlendFactor) (alpha_blend_op SDL_GPUBlendOp)
		(color_write_mask SDL_GPUColorComponentFlags) (enable_blend bool))
! !

ExternStruct subclass: #SDLGPUColorTargetDescription
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUColorTargetDescription class methodsFor: 'declaring'!
cName
	^'SDL_GPUColorTargetDescription'
!
fields
	^#((format SDL_GPUTextureFormat) (blend_state SDL_GPUColorTargetBlendState))
! !

ExternStruct subclass: #SDLGPUVertexInputState
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUVertexInputState class methodsFor: 'declaring'!
cName
	^'SDL_GPUVertexInputState'
!
fields
	^#((vertex_buffer_descriptions 'const SDL_GPUVertexBufferDescription *') (num_vertex_buffers Uint32)
		(vertex_attributes 'const SDL_GPUVertexAttribute *') (num_vertex_attributes Uint32))
! !

ExternStruct subclass: #SDLGPURasterizerState
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPURasterizerState class methodsFor: 'declaring'!
cName
	^'SDL_GPURasterizerState'
!
fields
	^#((fill_mode SDL_GPUFillMode) (cull_mode SDL_GPUCullMode))
! !

ExternStruct subclass: #SDLGPUGraphicsPipelineTargetInfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUGraphicsPipelineTargetInfo class methodsFor: 'declaring'!
cName
	^'SDL_GPUGraphicsPipelineTargetInfo'
!
fields
	^#((color_target_descriptions 'const SDL_GPUColorTargetDescription *') (num_color_targets Uint32))
! !

ExternStruct subclass: #SDLGPUGraphicsPipelineCreateInfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUGraphicsPipelineCreateInfo class methodsFor: 'declaring'!
cName
	^'SDL_GPUGraphicsPipelineCreateInfo'
!
fields
	^#((vertex_shader 'SDL_GPUShader *') (fragment_shader 'SDL_GPUShader *') (vertex_input_state SDL_GPUVertexInputState)
		(primitive_type SDL_GPUPrimitiveType) (rasterizer_state SDL_GPURasterizerState) (target_info SDL_GPUGraphicsPipelineTargetInfo))
! !

ExternStruct subclass: #SDLGPUTextureCreateInfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUTextureCreateInfo class methodsFor: 'declaring'!
cName
	^'SDL_GPUTextureCreateInfo'
!
fields
	^#((type SDL_GPUTextureType) (format SDL_GPUTextureFormat) (usage SDL_GPUTextureUsageFlags) (width Uint32) (height Uint32)
		(layer_count_or_depth Uint32) (num_levels Uint32))
! !

ExternStruct subclass: #SDLGPUSamplerCreateInfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUSamplerCreateInfo class methodsFor: 'declaring'!
cName
	^'SDL_GPUSamplerCreateInfo'
!
fields
	^#((min_filter SDL_GPUFilter) (mag_filter SDL_GPUFilter) (mipmap_mode SDL_GPUSamplerMipmapMode)
		(address_mode_u SDL_GPUSamplerAddressMode) (address_mode_v SDL_GPUSamplerAddressMode) (address_mode_w SDL_GPUSamplerAddressMode))
! !

ExternStruct subclass: #SDLGPUBufferCreateInfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

SDLGPUBufferCreateInfo comment: 'size is only written: in the simulator a VMStruct answers its own size.'!

!SDLGPUBufferCreateInfo class methodsFor: 'declaring'!
cName
	^'SDL_GPUBufferCreateInfo'
!
fields
	^#((usage SDL_GPUBufferUsageFlags) (size Uint32))
! !

ExternStruct subclass: #SDLGPUTransferBufferCreateInfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

SDLGPUTransferBufferCreateInfo comment: 'size is only written: in the simulator a VMStruct answers its own size.'!

!SDLGPUTransferBufferCreateInfo class methodsFor: 'declaring'!
cName
	^'SDL_GPUTransferBufferCreateInfo'
!
fields
	^#((usage SDL_GPUTransferBufferUsage) (size Uint32))
! !

ExternStruct subclass: #SDLGPUTransferBufferLocation
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUTransferBufferLocation class methodsFor: 'declaring'!
cName
	^'SDL_GPUTransferBufferLocation'
!
fields
	^#((transfer_buffer 'SDL_GPUTransferBuffer *') (offset Uint32))
! !

ExternStruct subclass: #SDLGPUBufferRegion
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

SDLGPUBufferRegion comment: 'size is only written: in the simulator a VMStruct answers its own size.'!

!SDLGPUBufferRegion class methodsFor: 'declaring'!
cName
	^'SDL_GPUBufferRegion'
!
fields
	^#((buffer 'SDL_GPUBuffer *') (offset Uint32) (size Uint32))
! !

ExternStruct subclass: #SDLGPUTextureTransferInfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUTextureTransferInfo class methodsFor: 'declaring'!
cName
	^'SDL_GPUTextureTransferInfo'
!
fields
	^#((transfer_buffer 'SDL_GPUTransferBuffer *') (offset Uint32) (pixels_per_row Uint32) (rows_per_layer Uint32))
! !

ExternStruct subclass: #SDLGPUTextureRegion
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUTextureRegion class methodsFor: 'declaring'!
cName
	^'SDL_GPUTextureRegion'
!
fields
	^#((texture 'SDL_GPUTexture *') (mip_level Uint32) (layer Uint32) (x Uint32) (y Uint32) (z Uint32) (w Uint32) (h Uint32) (d Uint32))
! !

ExternStruct subclass: #SDLGPUColorTargetInfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUColorTargetInfo class methodsFor: 'declaring'!
cName
	^'SDL_GPUColorTargetInfo'
!
fields
	^#((texture 'SDL_GPUTexture *') (mip_level Uint32) (layer_or_depth_plane Uint32) (clear_color SDL_FColor)
		(load_op SDL_GPULoadOp) (store_op SDL_GPUStoreOp))
! !

ExternStruct subclass: #SDLGPUViewport
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUViewport class methodsFor: 'declaring'!
cName
	^'SDL_GPUViewport'
!
fields
	^#((x float) (y float) (w float) (h float) (min_depth float) (max_depth float))
! !

ExternStruct subclass: #SDLGPUBufferBinding
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUBufferBinding class methodsFor: 'declaring'!
cName
	^'SDL_GPUBufferBinding'
!
fields
	^#((buffer 'SDL_GPUBuffer *') (offset Uint32))
! !

ExternStruct subclass: #SDLGPUTextureSamplerBinding
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUTextureSamplerBinding class methodsFor: 'declaring'!
cName
	^'SDL_GPUTextureSamplerBinding'
!
fields
	^#((texture 'SDL_GPUTexture *') (sampler 'SDL_GPUSampler *'))
! !

ExternStruct subclass: #SDLGPUBlitRegion
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUBlitRegion class methodsFor: 'declaring'!
cName
	^'SDL_GPUBlitRegion'
!
fields
	^#((texture 'SDL_GPUTexture *') (mip_level Uint32) (layer_or_depth_plane Uint32) (x Uint32) (y Uint32) (w Uint32) (h Uint32))
! !

ExternStruct subclass: #SDLGPUBlitInfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLGPUBlitInfo class methodsFor: 'declaring'!
cName
	^'SDL_GPUBlitInfo'
!
fields
	^#((source SDL_GPUBlitRegion) (destination SDL_GPUBlitRegion) (load_op SDL_GPULoadOp) (clear_color SDL_FColor)
		(flip_mode SDL_FlipMode) (filter SDL_GPUFilter))
! !
