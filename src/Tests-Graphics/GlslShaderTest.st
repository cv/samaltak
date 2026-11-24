TestCase subclass: #GlslShaderTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

GlslShaderTest comment: 'Tests the GLSL front end (Graphics-Shaders: GlslLexer, GlslShader, GlslCudaWriter) without a GPU or a compiler: the preprocessor, types and conversions, swizzles, overloads, uniform blocks laid out as std140, the errors (ShaderErrors at the line and column, the prelude''s #line 1 making them the source''s), and the CUDA written for the shipped shaders; and NvCubin reading the constant-bank relocations of a precompiled one.'!

!GlslShaderTest methodsFor: 'support'!
parse: aString
	^GlslShader parse: FragmentShader glslPrelude, aString
!
cuda: aString
	^GlslCudaWriter cudaFor: (self parse: aString)
!
errorOf: aString
	"The ShaderError aString gives: (line column detail)."
	[self parse: aString] on: ShaderError do: [:e | ^Array with: e line with: e column with: e detail].
	^nil
!
main: aBody
	^'void main() { ', aBody, ' }'
! !

!GlslShaderTest methodsFor: 'tests'!
testAMinimalShader
	| s cuda |
	s := self parse: (self main: 'fragColor = vec4(uv, 0.0, 1.0);').
	self assert: s main notNil.
	self assert: s output name equals: 'fragColor'.
	self assert: (s inputs collect: [:v | v name]) asArray equals: #('uv' 'size').
	cuda := GlslCudaWriter cudaFor: s.
	self assert: (cuda includesSubstring: 'extern "C" __global__ void __launch_bounds__(256) gl_fragment(gl_Params p)').
	self assert: (cuda includesSubstring: 'gl_c.gl_out = gl::mk<gl::vec4>(gl_c.uv, 0.0f, 1.0f)')
!
testErrorsAreAtTheSourcesLineAndColumn
	self assert: (self errorOf: 'void main() {
	fragColor = vec4(1.0)
}') equals: #(3 1 'expected ; before ''}''').
	self assert: (self errorOf: 'void main() { fragColor = noise(uv); }') equals: #(1 27 'no function noise').
	self assert: (self errorOf: 'void main() { fragColor = vec4(normalize(uv, 1.0), 0.0, 1.0); }') first equals: 1.
	self assert: ((self errorOf: 'void main() { fragColor = vec4(normalize(uv, 1.0), 0.0, 1.0); }') last beginsWith: 'no function normalize(vec2, float)').
	self assert: (self errorOf: 'void main() { vec3 v = uv; fragColor = vec4(v, 1.0); }') equals: #(1 24 'cannot convert vec2 to vec3').
	self assert: (self errorOf: 'void main() { uv = vec2(0.0); fragColor = vec4(1.0); }') equals: #(1 15 'cannot assign to uv, an input').
	self assert: (self errorOf: 'void main() { fragColor = vec4(uv.xq, 0.0, 1.0); }') equals: #(1 35 'xq is not a swizzle of vec2').
	self assert: (self errorOf: 'void main() { fragColor = vec4(1.0); ') last equals: 'expected } before the end'.
	self assert: (self errorOf: 'float f() { return 1.0; }') last equals: 'no function void main()'.
	self assert: (self errorOf: 'void main() { fragColor = texture(t, uv); }') last equals: 'texture: textures are not supported here'.
	self assert: (self errorOf: 'void main() { fragColor = vec4(1.0) # 2; }') equals: #(1 37 'unexpected character $#')
!
testThePreprocessor
	| cuda |
	cuda := self cuda: '#define K 2.0
#define TWICE(x) ((x) * K)
#ifdef SAMALTAK_CUDA
#define COLOR vec4(TWICE(uv.x), 0.0, 0.0, 1.0)
#else
#error not here
#endif
#if __VERSION__ >= 450 && !!defined(NOPE)
void main() { fragColor = COLOR; }
#endif
'.
	self assert: (cuda includesSubstring: 'gl_c.gl_out = gl::mk<gl::vec4>(((gl_c.uv).x * 2.0f), 0.0f, 0.0f, 1.0f)').
	self assert: (self errorOf: '#if 0
garbage $ here
#endif
#error stop
') equals: #(4 1 '#error stop')
!
testTypesAndImplicitConversions
	| cuda |
	cuda := self cuda: 'void main() {
	int i = 3;
	float f = i;
	uint u = 7u + uint(i);
	vec3 v = vec3(1, 2, 3) * 2;
	mat3 m = mat3(1.0);
	v = m * v + v * m;
	ivec2 q = ivec2(gl_FragCoord.xy);
	bvec2 b = lessThan(uv, vec2(0.5));
	fragColor = vec4(v, f) * float(u) + vec4(any(b) ? 1.0 : 0.0) + vec4(q, 0, 1);
}'.
	self assert: (cuda includesSubstring: 'float f = ((float)(i));').
	self assert: (cuda includesSubstring: 'gl::vec3 v = (gl::mk<gl::vec3>(1, 2, 3) * 2.0f);').
	self assert: (cuda includesSubstring: 'gl::mat3 m = gl::diag<gl::mat3>(1.0f);').
	self assert: (cuda includesSubstring: 'gl::mk<gl::vec4>(q, 0, 1)')
!
testSwizzles
	| cuda |
	cuda := self cuda: 'void main() {
	vec4 c = vec4(uv, 0.0, 1.0);
	c.zx = c.yx;
	c.xy *= 2.0;
	c.w = c.wzyx.w;
	c.y++;
	fragColor = c.rgba.bgra.bgra;
}'.
	self assert: (cuda includesSubstring: '(gl::swz<2, 0>(c) = gl::sw<1, 0>(c))').
	self assert: (cuda includesSubstring: '(gl::swz<0, 1>(c) *= 2.0f)').
	self assert: (cuda includesSubstring: '(c.w = (c).x)').
	self assert: (cuda includesSubstring: '(c.y++)').
	self assert: (cuda includesSubstring: 'gl_c.gl_out = gl::sw<0, 1, 2, 3>(c)').
	self assert: (self errorOf: 'void main() { vec4 c; c.xx = uv; fragColor = c; }') last equals: 'a swizzle with a component twice cannot be assigned to'
!
testFunctionsOverloadsAndParameters
	| s cuda |
	s := self parse: 'struct S { vec3 p[2]; float k; };
float f(float x) { return x; }
float f(vec2 v) { return v.x; }
void g(in S s, out float a, inout vec2 b) { a = s.k; b += s.p[1].xy; }
void main() { S s = S(vec3[2](vec3(1.0), vec3(2.0)), 3.0); float a; vec2 b = uv; g(s, a, b); fragColor = vec4(f(a), f(b), 0.0, 1.0); }'.
	self assert: (s functions collect: [:each | each signature]) asSortedCollection asArray equals: #('f(float)' 'f(vec2)' 'g(S, out float, inout vec2)' 'main()').
	cuda := GlslCudaWriter cudaFor: s.
	self assert: (cuda includesSubstring: 'static __device__ __noinline__ void g(gl_Ctx& gl_c, const S& s, float& a, gl::vec2& b)').
	self assert: (cuda includesSubstring: 'S s = S{gl::arr<gl::vec3, 2>{{gl::splat<gl::vec3>(1.0f), gl::splat<gl::vec3>(2.0f)}}, 3.0f};').
	self assert: (self errorOf: 'void h(out float a) { a = 1.0; } void main() { h(uv.x + 1.0); fragColor = vec4(1.0); }') last equals: 'cannot assign to this expression'
!
testUniformBlocksAreStd140
	| s cuda |
	s := self parse: 'struct L { vec3 dir; float k; };
layout(set = 3, binding = 0) uniform U { float a; vec2 b; vec3 c; float d; L l; float e[2]; mat2 m; } u;
void main() { fragColor = vec4(u.a + u.b.y + u.c.z + u.d + u.l.k + u.e[1] + u.m[1].y); }'.
	self assert: (#('a' 'b' 'c' 'd' 'l' 'e' 'm') collect: [:n | s block std140OffsetOf: n]) equals: #(0 8 16 28 32 48 80).
	self assert: s uniformSize equals: 112.
	cuda := GlslCudaWriter cudaFor: s.
	self assert: (cuda includesSubstring: 'gl::uload<float>(gl_c.u, 28)').
	self assert: (cuda includesSubstring: '(gl::uload<gl::vec2>(gl_c.u, 8)).y').
	self assert: (cuda includesSubstring: 'gl::uload<float>(gl_c.u, 48 + (1) * 16)').
	self assert: (cuda includesSubstring: 'gl::uloadm<gl::mat2>(gl_c.u, 80)[1]').
	self assert: (self errorOf: 'layout(set = 3, binding = 0) uniform U { vec4 t; } u; void main() { u.t = vec4(1.0); fragColor = u.t; }') last equals: 'cannot assign to u, a uniform'
!
testConstantsGlobalsAndLoops
	| cuda |
	cuda := self cuda: 'const int N = 4;
const vec3 K = normalize(vec3(1.0, 2.0, 2.0));
float acc[N];
float total = 0.0;
void main() {
	for (int i = 0; i < N; i++) { acc[i] = float(i); total += acc[i]; }
	int k = 0;
	while (true) { if (++k > 3) break; }
	do { k--; } while (k > 0);
	switch (k) { case 0: total += 1.0; break; default: discard; }
	fragColor = vec4(K * total, acc.length());
}'.
	self assert: (cuda includesSubstring: 'static __device__ __forceinline__ gl::vec3 gl_k_K() { return gl::normalize(gl::mk<gl::vec3>(1.0f, 2.0f, 2.0f)); }').
	self assert: (cuda includesSubstring: 'gl::arr<float, 4> acc;').
	self assert: (cuda includesSubstring: '{ gl_c.gl_discarded = true; return; }').
	self assert: (cuda includesSubstring: 'gl_c.total = 0.0f;')
!
testTheShippedShadersTranslate
	"Every ShaderView's GLSL is in the subset: Claude's Robot's, 50 functions."
	| sources |
	sources := NvShaderCompiler shippedSources.
	self assert: sources notEmpty.
	sources do: [:each | | s |
		s := GlslShader parse: each value.
		self assert: (GlslCudaWriter cudaFor: s) size > 10000.
		each key = #JugglerStage ifTrue: [
			self assert: s definedFunctions size equals: 50.
			self assert: s uniformSize equals: 176]]
!
testTheCubinsBankRelocations
	"The Robot's precompiled kernel calls sinf, whose large arguments need libdevice's table: constant bank 4 holds its address (R_CUDA_64), the table is .nv.global.init."
	| key cubin kernel |
	key := NvShaderCompiler keyFor: FragmentShader glslPrelude, (Smalltalk at: #JugglerStage) new glslShaderSource.
	cubin := NvShaderCompiler precompiledAt: key.
	cubin isNil ifTrue: [^self].
	kernel := (NvCubin on: cubin) kernelNamed: 'gl_fragment'.
	self assert: kernel bankRelocations equals: #(#(4 0 '.nv.global.init' 0 2)).
	self assert: (kernel globals at: '.nv.global.init') size equals: 24.
	self assert: kernel relocations isEmpty.
	self assert: kernel maxThreads equals: 256
!
testNvrtcErrorsBecomeShaderErrors
	| e |
	e := [NvShaderCompiler signalErrorIn: 'shader(12): error: identifier "foo" is undefined
1 error detected'] on: ShaderError do: [:x | x return: x].
	self assert: e line equals: 12.
	self assert: e messageText equals: '12: error: identifier "foo" is undefined (CUDA)'
! !
