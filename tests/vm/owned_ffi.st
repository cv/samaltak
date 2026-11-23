Object subclass: #OwnedFFIProof
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

!OwnedFFIProof class methodsFor: 'testing'!
require: condition
	condition ifFalse: [self error: 'Owned FFI check failed']
!
wire
	| bytes raised |
	bytes := #[255 255 255 255 255 255 255 255 128].
	self require: (FFIWire uint32At: 2 in: bytes) = 16rFFFFFFFF.
	self require: (FFIWire int32At: 3 in: bytes) = -1.
	self require: (FFIWire uint64At: 1 in: bytes) = 16rFFFFFFFFFFFFFFFF.
	self require: (FFIWire int64At: 1 in: bytes) = -1.
	self require: (FFIWire int64At: 2 in: bytes) = -9151314442816847873.
	self require: (FFIWire uint32VectorFrom: #[1 0 0 0 0 1 0 0] maxCount: 2) = #(1 256).
	self require: (FFIWire uint32VectorFrom: #[] maxCount: 0) isEmpty.
	raised := false.
	[FFIWire uint64At: 3 in: bytes] on: FFIError do: [:e | raised := true].
	self require: raised.
	raised := false.
	[FFIWire uint32VectorFrom: #[1 0 0 0] maxCount: 0] on: FFIError do: [:e | raised := true].
	self require: raised.
	^true
!
capture
	| binding result saved calls failed gcFlag |
	binding := FFI bind: #(call 'vm:core' 'ffi_test_owned_octets' (u64 i32) i32).
	calls := 0.
	1 to: 64 do: [:i |
		result := FFIOwnedOutput captureUpTo: 5 do: [:ticket |
			calls := calls + 1.
			saved := ticket.
			binding tryInvoke2: ticket with: 1].
		self require: result = #[0 255 65 128 0].
		self require: (binding tryInvoke2: saved with: 1) = -29].
	self require: calls = 64.
	self require: (FFIOwnedOutput captureUpTo: 0 do: [:ticket | binding tryInvoke2: ticket with: 0]) isNil.
	result := FFIOwnedOutput captureUpTo: 0 do: [:ticket | binding tryInvoke2: ticket with: 2].
	self require: result class == ByteArray.
	self require: result isEmpty.
	self require: (FFIOwnedOutput captureUpTo: 4 do: [:ticket | binding tryInvoke2: ticket with: 1]) = -23.
	self require: (FFIOwnedOutput captureUpTo: 5 do: [:ticket | binding tryInvoke2: ticket with: -1]) = -17.
	self require: (FFIOwnedOutput captureUpTo: 5 do: [:ticket | binding tryInvoke2: ticket with: nil]) == false.
	gcFlag := false.
	result := FFIOwnedOutput captureUpTo: 5 do: [:ticket |
		| status unrelated |
		status := binding tryInvoke2: ticket with: 3.
		Smalltalk vm garbageCollect.
		unrelated := ByteArray new: 1.
		unrelated beReadOnlyObject; beWritableObject.
		gcFlag := true.
		status].
	self require: gcFlag.
	self require: result = #[0 255 65 128 0].
	failed := false.
	[FFIOwnedOutput captureUpTo: 5 do: [:ticket |
		saved := ticket.
		binding tryInvoke2: ticket with: 4]] on: FFIError do: [:e | failed := true].
	self require: failed.
	self require: (binding tryInvoke2: saved with: 1) = -29.
	^true
! !
