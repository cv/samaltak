# Fragment shaders on the GB10 (NvComputeGPU)

A `FragmentShader` (Graphics-Canvas: `ShaderView`, Claude's Robot's `JugglerStage`) runs on an `NvComputeGPU`
(docs/nv-gpu.md) as a CUDA kernel, made from the shader's GLSL by the image's own front end and compiled for the GB10
(sm_121) either at build time (the shipped shaders) or in the image by NVIDIA's NVRTC, so shaders can be edited live. No
CUDA driver library is involved: System-NV launches the cubin through the kernel module's RM (docs/nv-rm.md).

    GLSL (FragmentShader's prelude + the source)
      → GlslShader (Graphics-Shaders: preprocess, parse, type-check; ShaderErrors at line:column)
      → GlslCudaWriter (CUDA C++: GLSL's types and built-ins in namespace gl, the kernel gl_fragment)
      → key: SHA-256 of that CUDA
      → cubin: this session's cache, else NvPrecompiledShaders (make nv-shaders), else NVRTC now (NvRtc → core_nvrtc_*)
      → NvCubin / NvCompute: launched over the FragmentShader's texture, a thread a pixel

## The front end (Graphics-Shaders)

Package Graphics-Shaders (layer 1) is GLSL 4.50's subset that Samaltak's fragment shaders use, independent of NVIDIA:
`GlslLexer` (tokens with line and column; the preprocessor: object- and function-like `#define`, `#undef`,
`#if`/`#ifdef`/`#ifndef`/`#elif`/`#else`/`#endif` with `defined` and integer arithmetic, `#line`, `#error`; `#version`,
`#extension` and `#pragma` ignored; `__VERSION__` 450, `SAMALTAK_FRAGMENT` and `SAMALTAK_CUDA` predefined),
`GlslShader` (a recursive-descent parser that types every expression as it goes, `GlslType`, `GlslNode`,
`GlslVariable`, `GlslFunction`, `GlslBuiltins`), and `GlslCudaWriter`, its one back end so far.

What it takes: `float int uint bool`, their vectors (`vec2`..`bvec4`), `mat2`..`mat4` and `matCxR`, structures and
arrays of them (sized, or sized by their initializer); swizzles (read and written, `.xyzw` `.rgba` `.stpq`, on scalars
too); GLSL's operators with its implicit conversions (int → uint → float, component-wise) and its linear algebra; every
constructor form (splat, components, diagonal and resized matrices, structures, arrays); functions, overloaded, with
`in`/`out`/`inout` parameters and prototypes; `if for while do switch break continue return discard`; constants,
global variables; one uniform block (`layout(set = 3, binding = 0) uniform U { ... } [name];`, laid out as std140); the
inputs `uv` and `size`, `gl_FragCoord`, `gl_FrontFacing`, one `vec4` output (FragmentShader's prelude); the
built-in functions of GLSL 4.50 chapter 8 but textures, images, atomics, packing and noise, including `dFdx`, `dFdy` and
`fwidth` (a warp is 8 x 4 pixels, so they are shuffles between neighbours, fine and coarse alike). What is outside the
subset (samplers, doubles, recursion, `==` on structures, a swizzle of several components as an `out` argument) is a
`ShaderError` saying so.

Errors are the first one, as a compiler reports it: `ShaderError` (line, column, detail; messageText `12:7: error:
no function noise(vec3); there is noise(vec2)`). FragmentShader's `glslPrelude` ends with `#line 1`, so the lines are
the source's (shaderc's messages on Vulkan too). CUDA errors the front end lets through (it should not) come back from
NVRTC's log at the shader's line, thanks to the `#line` directives the writer puts in, marked `(CUDA)`.

## The CUDA

`GlslCudaWriter header` is GLSL in CUDA C++ (namespace `gl`): `vec_<T, N>` (`vec3` is `vec_<float, 3>`, 8- and
16-byte aligned like float2/float4), `mat_<C, R>` (columns), `arr<T, N>` (arrays are values in GLSL), the operators as
templates on exact types (the front end has made the conversions explicit, so C++'s overload resolution never chooses),
the built-ins component-wise on CUDA's precise math (`sinf`, `powf`, ...; no fast math), swizzles as `gl::sw<0, 2>(v)`
and, for writing, `gl::swz<0, 2>(v) = ...` (a proxy), constructors as `gl::mk<gl::vec3>(a, b)`, `gl::splat`,
`gl::diag`, `gl::mconv`, `gl::mkm`, uniform loads as `gl::uload<T>(base, offset)` at std140 offsets (structures and arrays
through loaders the writer adds). The shader is namespace `gl_s`: each function takes the pixel's context `gl_Ctx&`
first (the uniforms' address, `gl_FragCoord`, `uv`, `size`, the output, discarded, the global variables), constants are
inline functions, `in` structures, arrays and matrices a function does not write are passed by `const&`, names C++ or
CUDA has get `__u` appended (GLSL names have no `__`).

The kernel: `extern "C" __global__ void __launch_bounds__(256) gl_fragment(gl_Params p)`, parameters (bank 0 at 0x380)
pixels@0 (the RGBA8 target's GPU address), width@8, height@12 (int32), the uniform block's GPU address@16 (std140,
`uniformSize` bytes). A block of 256 threads covers 16 x 16 pixels, each warp 8 x 4; grid ceil(w/16) x ceil(h/16). It
writes round(clamp(colour, 0, 1) * 255) per channel, nothing where the shader discarded (the pass cleared the texture).
The uniforms are not in the parameters: a pointer to a `__grid_constant__` parameter is a generic address into
parameter space that the CUDA driver sets up, and without it the kernel faulted (Xid 31); NvComputeGPU copies them into
its arena (uncached GPU memory, a ring) instead.

The writer keeps the shader's functions functions (`__noinline__`, `GlslCudaWriter keepsCalls`): for the Robot's
shader that is a third of ptxas's time and 40 % less per frame than inlining everything (169 registers instead of 208,
NVRTC at -O3; 128 for the precompiled cubin). Their frames and calls use the local memory NvCompute sizes per kernel.

## Compiling: NVRTC behind dlopen

`vm/native/nvrtc.c` (`nvrtc.h`) loads NVRTC with `dlopen` on first use (`SAMALTAK_NVRTC`, else `libnvrtc.so.13`,
`.12`, `libnvrtc.so`, and the same in `/usr/local/cuda/lib64`), its prototypes declared there, so building needs no
toolkit and a VM where there is none answers `-1`; on UEFI it is stubs. A compile runs on a thread of its own (at most 8
at once): `core_nvrtc_start(source, options)` → job, `core_nvrtc_poll(job)` (-2 running, 0 compiled, NVRTC's error),
`core_nvrtc_output(job, 0 log | 1 cubin, buffer)`, `core_nvrtc_free(job)`, `core_nvrtc_version()` (1300 for 13.0):
approved FFI exports 740-744 (VM-Jit `FFIPrimitives-nvrtc`, `NvrtcBackend`). `NvRtc` (System-NV) wraps them;
`NvRtc compile: cuda options: #('-arch=sm_121' ...)` waits by polling every 4 ms, so the image's other Processes run.
`-arch=sm_121` makes NVRTC produce the cubin itself (`nvrtcGetCUBIN`): nvPTXCompiler, a static library only (80 MB), is
not needed; `libnvJitLink.so` would be the shared way to turn PTX into a cubin if a back end ever writes PTX.

Options: `-arch=sm_121 -std=c++17 -Xptxas=-O1` at run time, NVRTC's defaults (ptxas -O3) for the precompiled ones.
NVRTC 13 keeps its own cache in `~/.nv/ComputeCache` (`CUDA_CACHE_PATH`, `CUDA_CACHE_DISABLE`): a source it compiled
before comes back in about 0.17 s even in a new image.

## Precompiled, cached, live

`NvShaderCompiler cubinFor: glsl` answers the cubin of a shader, keyed by the SHA-256 of its CUDA, so a precompiled cubin
is used only for exactly the CUDA it was made from (an edited shader, or a changed front end, has another key):

1. this session's cubins (`Cubins`), and the errors of sources that failed (`Failed`: reported again, not compiled again);
2. `NvPrecompiledShaders` (Graphics-NV, generated by `make nv-shaders` = `tools/nv-shaders.sh`): every ShaderView's
   shader (`NvShaderCompiler shippedSources`) compiled by NVRTC through the image's front end, each cubin compressed
   (ZLib) in Base64 under its key; the Robot's: 367 KB of cubin, 128 KB of source. They render without a compiler.
   `make test-nv` (`NvFragmentShaderTest>>testTheShippedShadersArePrecompiled`) fails while one is stale: run
   `make nv-shaders` after changing a shipped shader or Graphics-Shaders, build the image, commit the class;
3. NVRTC, if there is one: else a ShaderError (`this shader is not precompiled ...`).

`GPUDevice>>runsFragmentShaders` (true on SDL_GPU, on an NvComputeGPU when NVRTC is there or a shader is precompiled,
false on a SoftwareGPU), `runsFragmentShader: source` (where only precompiled ones run: is this one?) and
`fragmentShaderLanguage` (`#glsl` on an NvComputeGPU, whose `shaderLanguage` stays `#raster`: the Renderer still
runs on the raster kernels and never rebuilds there, `buildsShaders` is false) decide what a ShaderView does: where its
shader cannot run it draws `drawWithoutShaderOn:` (the Robot's flat act), as before on a SoftwareGPU.

**Live edits.** A FragmentShader given a new source (an edited `glslShaderSource` method, a ShaderView's or a Workspace's
string) asks `GPUDevice>>fragmentShaderReady:`; on an NvComputeGPU, NvShaderCompiler starts NVRTC in a background Process
if the source needs compiling, and the FragmentShader keeps drawing with its old pipeline until the kernel is there, then
builds the new one; the World keeps its frame rate meanwhile. A source that does not compile (front end or NVRTC) goes
to `Renderer reportShaderError:` (the toast of UI-Windows: `Shader not rebuilt ...: 866:1: error: expected ; before
'}'`) and the old pipeline stays. The first source of a FragmentShader compiles at once (there is nothing to draw
before it). A kernel's GPU memory (code, banks, data) goes when the last pipeline using it is released
(`NvCompute>>forget:`).

## GPU side

`NvComputeGPU` takes a fragment shader with entry `main` as GLSL (`createShader:...`: the kernel made now, or a
ShaderError), its pipeline (one triangle over an RGBA8 target, unblended, no vertices), fragment uniforms pushed to slot
0, and a draw with that pipeline launches `gl_fragment` over the pass's target after the batched draws before it. Other
shaders and pipelines are the Renderer's, as before.

NVRTC's code calls `sinf` and friends, whose large-argument paths read libdevice's tables (`__cudart_i2opi_f`) in
`.nv.global.init` through a 64-bit address in constant bank 4 (`.rela.nv.constant4`, R_CUDA_64). NvCubin now reads a
kernel's constant-bank relocations and its data sections (`NvKernel>>bankRelocations`, `globals`); NvCompute puts the
data in GPU memory of the kernel's own and writes the addresses into the bank before uploading it.
Relocations in the code itself (`.rela.text.<kernel>`) are still refused; none of these kernels has any.

## Numbers

On the GB10 (DGX Spark, shared with other work: loads of 5 to 10), Claude's Robot (`JugglerStage`, 870 lines of
GLSL, 50 functions):

| | |
| --- | --- |
| front end (parse, check, write 86 KB of CUDA) | 40-80 ms |
| NVRTC, cold, run-time options (ptxas -O1) | 1.7-3 s (2.5 s for a live edit in the World, 2.7 s to the new picture) |
| NVRTC, inlining every function instead | 9-17 s |
| NVRTC, its disk cache hit | 0.17 s |
| precompiled: first frame (translate, decompress 11 ms, upload) | 105 ms |
| a frame at 960 x 720, FragmentShader to texture, waited for | 4.6-5.2 ms (inlined: 7.7-8.5 ms) |
| the World on NvComputeGPU with the Robot's window (720 x 600) animating | 60 fps, frames of 4.45 ms on average |

The picture is the SDL_GPU one: the stage on NvComputeGPU (`SAMALTAK_GPU=nv SAMALTAK_SCREEN=memory:1920x1080`) against
hosted SDL_GPU on lavapipe under Xvfb, the act halted at the same frame: mean difference 0.9 of 255 per channel, 98.5 % of
the pixels within 2 levels, 0.01 % more than 32 apart (float rounding in a raymarcher, film grain from `sin` hashes).

## Tests

- test-core: `GlslShaderTest` (the preprocessor, types and conversions, swizzles, overloads and parameters, std140,
  constants and loops, error positions, the shipped shaders translating, the precompiled cubin's bank relocations,
  NVRTC log lines as ShaderErrors). No GPU, no compiler.
- `make test-nv`: `NvFragmentShaderTest` on the GB10 (pixel centres and uv, uniforms, derivatives and discards, `sin`
  of large arguments, a live edit compiling in the background while the old shader draws and a broken one reported with
  the old kept, a released pipeline freeing its kernel, the shipped shaders precompiled and current, the Robot rendering);
  `NvComputeGPUTest` (its pipeline rules).

## Licensing (CUDA Toolkit EULA, 13.0)

Attachment A lists as distributable with an application: NVRTC (`nvrtc.h`, `libnvrtc.so`, `libnvrtc-builtins.so`,
their static versions), `libnvJitLink.so`, `libnvptxcompiler_static.a` (with the driver libraries), `libdevice.10.bc`.
The conditions (1.1.2): the application adds material functionality to them, only the application uses them, it is
distributed on terms consistent with the EULA (its restrictions and NVIDIA's IP); the Linux files unmodified (2.3); the
SDK is licensed for systems with NVIDIA GPUs (2.1). So the appliance's image (docs/linux-appliance.md) may carry
`libnvrtc.so.13` and `libnvrtc-builtins.so.13.0` (104 MB; 33 MB with zstd -19, 43 MB gzip) for live shaders on the Spark,
unmodified, with the EULA beside them and the appliance's terms not contradicting it; whether Samaltak's own license
terms for the appliance meet "consistent with this Agreement" is a question for whoever distributes it. Until that is
settled the appliance does not ship them: it renders the precompiled shaders (everything the image ships) and uses NVRTC
only where the CUDA toolkit is installed (`SAMALTAK_NVRTC` names a copy). The cubins in `NvPrecompiledShaders` are
output of NVRTC compiling our own code, not part of the SDK.

## Not done

- One uniform block and no textures (samplers): the image's fragment shaders have none. Another back end (PTX directly,
  SPIR-V, the SoftwareGPU on the CPU) can take the same `GlslShader`.
- A ShaderView's own error marking in its source: errors go to the toast (as on SDL_GPU).
- The appliance's question above.
