Object subclass: #GlslCudaWriter
	instanceVariableNames: 'shader out indent lastLine loaders loaderOut function'
	classVariableNames: 'Calls'
	package: 'Graphics-Shaders'!

GlslCudaWriter comment: 'I write a GlslShader as CUDA C++ for NVRTC: my header (GLSL''s types and built-in functions, namespace gl), then the shader in namespace gl_s (its structures; gl_Ctx, a pixel''s context: the uniforms'' address, gl_FragCoord, uv, size, the output, discarded, the global variables; constants as functions gl_k_<name>(); loaders of uniform structures and arrays; the functions, each taking the context first), then the kernel gl_fragment: a thread a pixel, 16 x 16 pixels a block of 256 threads (a warp 8 x 4 of them, so dFdx and dFdy are shuffles), its parameters a gl_Params (pixels: the RGBA8 target''s GPU address at 0, width at 8, height at 12, the uniform block''s GPU address at 16: std140, uniformSize bytes), writing round(clamp(colour, 0, 1) * 255) unless the shader discarded the pixel. #line directives keep the shader''s lines in NVRTC''s messages. GlslCudaWriter cudaFor: aGlslShader answers the source.'!

!GlslCudaWriter methodsFor: 'writing'!
write: aShader
	| body prototypes |
	shader := aShader.
	loaders := Dictionary new.
	loaderOut := WriteStream on: String new.
	indent := 0.
	lastLine := nil.
	body := WriteStream on: String new.
	out := body.
	shader definedFunctions do: [:f | self function: f].
	self globalInits.
	prototypes := String streamContents: [:s |
		shader definedFunctions do: [:f | s nextPutAll: (self signatureOf: f); nextPutAll: ';'; nextPut: Character lf]].
	^String streamContents: [:s |
		s nextPutAll: self class header.
		s nextPutAll: '#line 1 "shader"'; nextPut: Character lf.
		s nextPutAll: 'namespace gl_s {'; nextPut: Character lf.
		shader structs do: [:t | s nextPutAll: (self structDefinition: t)].
		s nextPutAll: self context.
		s nextPutAll: self constants.
		s nextPutAll: loaderOut contents.
		s nextPutAll: prototypes.
		s nextPutAll: body contents.
		s nextPutAll: '}'; nextPut: Character lf.
		s nextPutAll: self kernel]
!
structDefinition: aType
	^String streamContents: [:s |
		s nextPutAll: 'struct '; nextPutAll: aType cuda; nextPutAll: ' {'.
		aType fields do: [:f | s space; nextPutAll: f value cuda; space; nextPutAll: (GlslShader cudaName: f key); nextPut: $;].
		s nextPutAll: ' };'; nextPut: Character lf]
!
context
	^String streamContents: [:s |
		s nextPutAll: 'struct gl_Ctx { const char* u; gl::vec4 gl_FragCoord; gl::vec2 uv, size; gl::vec4 gl_out; bool gl_discarded;'.
		(shader globals select: [:v | v storage == #global]) do: [:v |
			s space; nextPutAll: v type cuda; space; nextPutAll: (GlslShader cudaName: v name); nextPut: $;].
		s nextPutAll: ' };'; nextPut: Character lf]
!
constants
	^String streamContents: [:s |
		(shader globals select: [:v | v storage == #const]) do: [:v | | e |
			e := self constantExpression: v init.
			s nextPutAll: 'static __device__ __forceinline__ '; nextPutAll: v type cuda; nextPutAll: ' gl_k_'; nextPutAll: (GlslShader cudaName: v name);
				nextPutAll: '() { return '; nextPutAll: e; nextPutAll: '; }'; nextPut: Character lf]]
!
constantExpression: aNode
	self checkConstant: aNode.
	^self expr: aNode
!
checkConstant: aNode
	"A constant's value refers to nothing but constants."
	aNode isNil ifTrue: [^self].
	(aNode kind == #ident and: [aNode symbol storage ~~ #const]) ifTrue: [
		ShaderError line: aNode line column: aNode column detail: 'a constant''s value must be constant: ', aNode symbol name, ' is not'].
	aNode kind == #call ifTrue: [ShaderError line: aNode line column: aNode column detail: 'a constant''s value cannot call ', aNode symbol name].
	aNode children do: [:c | self checkConstant: c]
!
globalInits
	"gl_init: the global variables' initializers, in order."
	out nextPutAll: 'static __device__ void gl_init(gl_Ctx& gl_c) {'; nextPut: Character lf.
	(shader globals select: [:v | v storage == #global and: [v init notNil]]) do: [:v |
		self line: v init.
		out tab; nextPutAll: v cuda; nextPutAll: ' = '; nextPutAll: (self expr: v init); nextPut: $;; nextPut: Character lf].
	out nextPutAll: '}'; nextPut: Character lf
!
kernel
	^String streamContents: [:s |
		s nextPutAll: 'struct gl_Params { unsigned long long pixels; int width, height; const char* u; };
extern "C" __global__ void __launch_bounds__(256) gl_fragment(gl_Params p) {
	int lane = threadIdx.x & 31, warp = threadIdx.x >> 5;
	int x = blockIdx.x * 16 + (warp & 1) * 8 + (lane & 7), y = blockIdx.y * 16 + (warp >> 1) * 4 + (lane >> 3);
	gl_s::gl_Ctx gl_c;
	gl_c.u = p.u;
	gl_c.gl_FragCoord = gl::vec4{x + 0.5f, y + 0.5f, 0.0f, 1.0f};
	gl_c.size = gl::vec2{(float)p.width, (float)p.height};
	gl_c.uv = gl::vec2{gl_c.gl_FragCoord.x / gl_c.size.x, gl_c.gl_FragCoord.y / gl_c.size.y};
	gl_c.gl_out = gl::vec4{0.0f, 0.0f, 0.0f, 0.0f};
	gl_c.gl_discarded = false;
	gl_s::gl_init(gl_c);
	gl_s::gl_main(gl_c);
	if (x < p.width && y < p.height && !!gl_c.gl_discarded) ((unsigned*)p.pixels)[y * p.width + x] = gl::rgba8(gl_c.gl_out);
}
']
!
signatureOf: f
	^String streamContents: [:s |
		s nextPutAll: 'static __device__ '.
		(self class keepsCalls and: [f name ~= 'main']) ifTrue: [s nextPutAll: '__noinline__ '].
		s nextPutAll: f returnType cuda; space; nextPutAll: f cuda; nextPutAll: '(gl_Ctx& gl_c'.
		f params do: [:p |
			s nextPutAll: ', '.
			((p isConst and: [p mode == #in]) or: [p isPassedByReference]) ifTrue: [s nextPutAll: 'const '].
			s nextPutAll: p type cuda.
			(p mode ~~ #in or: [p isPassedByReference]) ifTrue: [s nextPut: $&].
			s space; nextPutAll: p cuda].
		s nextPut: $)]
!
function: f
	function := f.
	self line: f.
	out nextPutAll: (self signatureOf: f); space.
	self block: f body.
	out nextPut: Character lf
! !

!GlslCudaWriter class methodsFor: 'options'!
keepsCalls
	"Whether the shader's functions stay functions (__noinline__, the default): for the Robot's shader ptxas takes a third of the time it takes when NVRTC inlines them all, and a frame takes 40 % less (fewer registers, more warps; docs/nv-shaders.md)."
	^Calls ifNil: [true]
!
keepsCalls: aBoolean
	Calls := aBoolean
! !

!GlslCudaWriter methodsFor: 'statements'!
line: aNode
	"A #line directive if aNode is on another line than what was written last."
	aNode line = lastLine ifTrue: [^self].
	lastLine := aNode line.
	out nextPutAll: '#line '; print: aNode line; nextPut: Character lf
!
newLine
	out nextPut: Character lf.
	indent timesRepeat: [out tab]
!
block: aNode
	out nextPut: ${.
	indent := indent + 1.
	aNode children do: [:s | self statementOnNewLine: s].
	indent := indent - 1.
	self newLine.
	out nextPut: $}
!
statementOnNewLine: aNode
	aNode line = lastLine
		ifTrue: [self newLine]
		ifFalse: [out nextPut: Character lf. self line: aNode. indent timesRepeat: [out tab]].
	self statement: aNode
!
statement: aNode
	| k |
	k := aNode kind.
	k == #block ifTrue: [^self block: aNode].
	k == #empty ifTrue: [^out nextPut: $;].
	k == #expr ifTrue: [^out nextPutAll: (self expr: aNode first); nextPut: $;].
	k == #decl ifTrue: [^aNode children do: [:d | self declarator: d] separatedBy: [out space]].
	k == #if ifTrue: [
		out nextPutAll: 'if ('; nextPutAll: (self expr: aNode first); nextPutAll: ') '.
		self substatement: aNode second.
		(aNode children at: 3) isNil ifFalse: [out nextPutAll: ' else '. self substatement: (aNode children at: 3)].
		^self].
	k == #for ifTrue: [
		out nextPutAll: 'for ('.
		(aNode children at: 1) isNil ifFalse: [self forInit: (aNode children at: 1)].
		out nextPutAll: '; '.
		(aNode children at: 2) isNil ifFalse: [out nextPutAll: (self expr: (aNode children at: 2))].
		out nextPutAll: '; '.
		(aNode children at: 3) isNil ifFalse: [out nextPutAll: (self expr: (aNode children at: 3))].
		out nextPutAll: ') '.
		^self substatement: (aNode children at: 4)].
	k == #while ifTrue: [
		out nextPutAll: 'while ('; nextPutAll: (self expr: aNode first); nextPutAll: ') '.
		^self substatement: aNode second].
	k == #do ifTrue: [
		out nextPutAll: 'do '.
		self substatement: aNode first.
		^out nextPutAll: ' while ('; nextPutAll: (self expr: aNode second); nextPutAll: ');'].
	k == #switch ifTrue: [
		out nextPutAll: 'switch ('; nextPutAll: (self expr: aNode first); nextPutAll: ') '.
		^self block: aNode second].
	k == #case ifTrue: [
		aNode value isNil ifTrue: [^out nextPutAll: 'default:'].
		^out nextPutAll: 'case '; print: aNode value; nextPut: $:].
	k == #return ifTrue: [
		aNode first isNil ifTrue: [^out nextPutAll: 'return;'].
		^out nextPutAll: 'return '; nextPutAll: (self expr: aNode first); nextPut: $;].
	(k == #break or: [k == #continue]) ifTrue: [^out nextPutAll: k; nextPut: $;].
	k == #discard ifTrue: [
		^function name = 'main'
			ifTrue: [out nextPutAll: '{ gl_c.gl_discarded = true; return; }']
			ifFalse: [out nextPutAll: 'gl_c.gl_discarded = true;']].
	self error: 'no statement ', k
!
substatement: aNode
	aNode kind == #block ifTrue: [^self block: aNode].
	out nextPut: ${.
	indent := indent + 1.
	self statementOnNewLine: aNode.
	indent := indent - 1.
	self newLine.
	out nextPut: $}
!
declarator: d
	| v |
	v := d symbol.
	v isConst ifTrue: [out nextPutAll: 'const '].
	out nextPutAll: v type cuda; space; nextPutAll: v cuda.
	d first isNil ifFalse: [out nextPutAll: ' = '; nextPutAll: (self expr: d first)].
	out nextPut: $;
!
forInit: aNode
	aNode kind == #expr ifTrue: [^out nextPutAll: (self expr: aNode first)].
	aNode children doWithIndex: [:d :i | | v |
		v := d symbol.
		i = 1
			ifTrue: [v isConst ifTrue: [out nextPutAll: 'const ']. out nextPutAll: v type cuda; space]
			ifFalse: [out nextPutAll: ', '].
		v type = aNode children first symbol type ifFalse: [
			ShaderError line: d line column: d column detail: 'a for loop''s variables have one type here'].
		out nextPutAll: v cuda.
		d first isNil ifFalse: [out nextPutAll: ' = '; nextPutAll: (self expr: d first)]]
! !
