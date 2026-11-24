!PlatformGPU methodsFor: 'FFI validation'!
ffiCanBeginPass: cmd target: tex
	<function>
	<var: #cmd type: 'int32_t'>
	<var: #tex type: 'int32_t'>
	<returns: 'bool'>
	| c t |
	c := self get: cmd kind: K_CMD what: 'command buffer'.
	t := self target: tex.
	(c isNull or: [t isNull]) ifTrue: [^false].
	(c dev ~= t dev or: [t kind = K_SWAP and: [t i ~= cmd]]) ifTrue: [
		common setError: 'render target does not belong to this command buffer'.
		^false].
	(t kind = K_TEX and: [(t i bitAnd: PF_TEXUSE_COLOR_TARGET) = 0]) ifTrue: [
		common setError: 'texture cannot be a color target'.
		^false].
	^self ffiCommandOutsidePass: cmd
!
ffiCommandOutsidePass: cmd
	<function>
	<var: #cmd type: 'int32_t'>
	<returns: 'bool'>
	1 to: objs n - 1 do: [:i |
		((objs v + i) kind = K_PASS and: [(objs v + i) i = cmd]) ifTrue: [
			common setError: 'command buffer has an active render pass'.
			^false]].
	^true
! !

!PlatformGPU methodsFor: 'FFI binding validation'!
ffiResource: handle kind: kind forPass: pass
	<function>
	<var: #handle type: 'int32_t'>
	<var: #pass type: 'int32_t'>
	<returns: 'pf_obj *'>
	| p resource |
	p := self get: pass kind: K_PASS what: 'render pass'.
	p isNull ifTrue: [^self null].
	resource := self get: handle kind: kind what: 'GPU resource'.
	resource isNull ifTrue: [^self null].
	p dev ~= resource dev ifTrue: [
		common setError: 'GPU resource and render pass belong to different devices'.
		^self null].
	^resource
!
ffiCanBindPipeline: pipeline to: pass
	<function>
	<var: #pipeline type: 'int32_t'>
	<var: #pass type: 'int32_t'>
	<returns: 'bool'>
	^(self ffiResource: pipeline kind: K_PIPE forPass: pass) notNull
!
ffiCanBindBuffer: buffer to: pass offset: off
	<function>
	<var: #buffer type: 'int32_t'>
	<var: #pass type: 'int32_t'>
	<var: #off type: 'uint32_t'>
	<returns: 'bool'>
	| b |
	b := self ffiResource: buffer kind: K_BUF forPass: pass.
	b isNull ifTrue: [^false].
	off asUInt64 >= b i asUInt64 ifTrue: [
		common setError: 'vertex buffer offset out of bounds'.
		^false].
	^true
!
ffiCanBindTexture: texture sampler: sampler to: pass
	<function>
	<var: #texture type: 'int32_t'>
	<var: #sampler type: 'int32_t'>
	<var: #pass type: 'int32_t'>
	<returns: 'bool'>
	| t |
	t := self ffiResource: texture kind: K_TEX forPass: pass.
	t isNull ifTrue: [^false].
	(t i bitAnd: PF_TEXUSE_SAMPLER) = 0 ifTrue: [
		common setError: 'texture cannot be sampled'.
		^false].
	^(self ffiResource: sampler kind: K_SAMPLER forPass: pass) notNull
! !

!PlatformGPU methodsFor: 'FFI blit validation'!
ffiRect: rect liesInside: tex
	<function>
	<var: #rect type: 'int32_t *'>
	<var: #tex type: 'pf_obj *'>
	<returns: 'bool'>
	^((rect at: 0) >= 0 and: [(rect at: 1) >= 0 and: [
		(rect at: 2) > 0 and: [(rect at: 3) > 0 and: [
			(rect at: 0) asInt64 + (rect at: 2) <= tex w and: [
				(rect at: 1) asInt64 + (rect at: 3) <= tex h]]]]])
!
ffiCanBlit: cmd source: src rect: sr destination: dst rect: dr
	<function>
	<var: #cmd type: 'int32_t'>
	<var: #src type: 'int32_t'>
	<var: #dst type: 'int32_t'>
	<var: #sr type: 'int32_t *'>
	<var: #dr type: 'int32_t *'>
	<returns: 'bool'>
	| c s t |
	c := self get: cmd kind: K_CMD what: 'command buffer'.
	s := self get: src kind: K_TEX what: 'texture'.
	t := self target: dst.
	(c isNull or: [s isNull or: [t isNull]]) ifTrue: [^false].
	(c dev ~= s dev or: [c dev ~= t dev or: [t kind = K_SWAP and: [t i ~= cmd]]]) ifTrue: [
		common setError: 'blit textures do not belong to this command buffer'.
		^false].
	(src = dst or: [(s i bitAnd: PF_TEXUSE_SAMPLER) = 0 or: [
		t kind = K_TEX and: [(t i bitAnd: PF_TEXUSE_COLOR_TARGET) = 0]]]) ifTrue: [
		common setError: 'invalid GPU blit texture usage'.
		^false].
	((self ffiRect: sr liesInside: s) and: [self ffiRect: dr liesInside: t]) ifFalse: [
		common setError: 'invalid GPU blit rectangle'.
		^false].
	^self ffiCommandOutsidePass: cmd
! !

!PlatformGPU methodsFor: 'FFI pipeline validation'!
ffiAttributeWidth: format
	<function>
	<var: #format type: 'int32_t'>
	<returns: 'int32_t'>
	^format caseOf: {
		[PF_VA_FLOAT2] -> [8].
		[PF_VA_FLOAT3] -> [12].
		[PF_VA_FLOAT4] -> [16].
		[PF_VA_FLOAT] -> [4].
		[PF_VA_UBYTE4_NORM] -> [4].
		[PF_VA_UBYTE4] -> [4].
		[PF_VA_UINT] -> [4].
		[PF_VA_INT] -> [4]}
		otherwise: [0]
!
ffiCanCreatePipeline: dev vertex: vs fragment: fs stride: stride attributes: attrs count: count
	<function>
	<var: #dev type: 'int32_t'>
	<var: #vs type: 'int32_t'>
	<var: #fs type: 'int32_t'>
	<var: #stride type: 'int32_t'>
	<var: #attrs type: 'pf_vattr *'>
	<var: #count type: 'int32_t'>
	<returns: 'bool'>
	| v f attr bytes |
	v := self get: vs kind: K_SHADER what: 'vertex shader'.
	f := self get: fs kind: K_SHADER what: 'fragment shader'.
	(v isNull or: [f isNull]) ifTrue: [^false].
	(v dev ~= dev or: [f dev ~= dev or: [v i ~= PF_STAGE_VERTEX or: [f i ~= PF_STAGE_FRAGMENT]]]) ifTrue: [
		common setError: 'pipeline shaders have the wrong owner or stage'.
		^false].
	0 to: count - 1 do: [:i |
		attr := attrs + i.
		bytes := self ffiAttributeWidth: attr format.
		(bytes = 0 or: [attr offset < 0 or: [attr offset asInt64 + bytes > stride]]) ifTrue: [
			common setError: 'vertex attribute exceeds pipeline stride or has invalid type'.
			^false]].
	^true
! !

!PlatformGPU methodsFor: 'FFI draw validation'!
invalidateDrawBindings
	"Any pipeline/texture release invalidates procedural certification. No handle scan
	and no stale positives when the underlying table recycles an integer."
	<function>
	drawBindingEpoch = 0 ifTrue: [^self].
	drawBindingEpoch := (drawBindingEpoch = 16r7FFFFFFF ifTrue: [0] ifFalse: [drawBindingEpoch + 1]) asInt32
!
ffiBoundDrawPass: pass
	"Require a compatible recorded pipeline on the command buffer's active pass.
	Do not use the live pipeline table to reject an SDL-encoded retained pipeline."
	<function>
	<var: #pass type: 'int32_t'>
	<returns: 'pf_obj *'>
	| p c |
	p := self get: pass kind: K_PASS what: 'render pass'.
	p isNull ifTrue: [^self null].
	c := common table: objs at: p i asInt32 kind: K_CMD.
	(c isNull or: [c w ~= pass or: [p w <= 0]]) ifTrue: [
		common setError: 'no compatible graphics pipeline bound to the active pass'.
		^self null].
	^p
!
ffiDrawEligibility: pass count: n first: first
	"1 certified procedural draw, 0 valid pass but uncertified, -1 invalid required state."
	<function>
	<var: #pass type: 'int32_t'>
	<var: #n type: 'int32_t'>
	<var: #first type: 'int32_t'>
	<returns: 'int32_t'>
	| p pipeline |
	p := self ffiBoundDrawPass: pass.
	p isNull ifTrue: [^-1].
	"SDL may retain already-encoded resources even after the image releases its handle.
	Do not certify that state, swapchains or pipelines with resource bindings."
	(p h = 0 or: [p h ~= drawBindingEpoch or: [n < 0 or: [first < 0 or: [
		n asInt64 + first > 16r7FFFFFFF]]]]) ifTrue: [^0].
	pipeline := common table: objs at: p w kind: K_PIPE.
	pipeline isNull ifTrue: [^0].
	^pipeline w = 1 ifTrue: [1] ifFalse: [0]
! !
