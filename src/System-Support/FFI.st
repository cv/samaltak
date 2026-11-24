Object subclass: #FFI
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Support'!

FFI comment: 'I bind descriptors for registered native exports. A downcall descriptor is #(call library symbol argumentTypes resultType). The library and symbol are Strings of 1 to 127 non-NUL ASCII characters. argumentTypes is an Array of up to six type Symbols, and resultType is a type Symbol. A literal or a computed Array works the same way.

	(FFI bind: #(call ''libm'' ''sqrt'' (f64) f64)) invoke: #(9.0).

Scalar types are i32, u32, i64, u64, f64 and f32 (a Float rounded to the nearest float; a float result answers a Float). Use void only for a result (answers nil). For an approved export, nonNegativeI64 returns nil for a negative int64_t result or the exact Integer otherwise. For a launcher grant, bytesWithLength takes one read-only slice {aByteArray. oneBasedOffset. length} and passes a pointer and the validated length in two of at most sixteen C slots. For vetted built-in exports only, writableBytesWithLength takes the same slice shape but requires a mutable ByteArray and lets the target write inside the slice until return. For memcmp, use (byteSlice byteSlice u64); the comparison count may not exceed either slice length. No argument or result is a native address. Unknown exports, mismatched signatures and rejected arguments signal FFIError. Notification descriptors start with #notification; FFINotification handles their schema.'!

!FFI class methodsFor: 'binding'!
bind: aDescriptor
	"Bind a literal or computed descriptor. For downcalls, answer an FFIBinding."
	(aDescriptor class == Array and: [aDescriptor notEmpty])
		ifFalse: [^FFIError signal: 'An FFI descriptor must be a nonempty Array'].
	aDescriptor first == #notification ifTrue: [
		^(Smalltalk at: #FFINotification ifAbsent: [^FFIError signal: 'FFI notifications are unavailable'])
			bind: aDescriptor].
	aDescriptor first == #call ifTrue: [^self bindCall: aDescriptor].
	^FFIError signal: 'An FFI descriptor must start with #call or #notification'
! !

!FFI class methodsFor: 'private'!
bindCall: aDescriptor
	^self bindCall: aDescriptor signalIfUnavailable: true
!
tryBindCall: aDescriptor
	"Private to PlatformFFI. A valid call descriptor with no available export answers nil."
	^self bindCall: aDescriptor signalIfUnavailable: false
!
bindCall: aDescriptor signalIfUnavailable: signalIfUnavailable
	| binding descriptor |
	binding := self newCallBinding: aDescriptor.
	binding prepare ifTrue: [^binding].
	signalIfUnavailable ifTrue: [
		descriptor := binding descriptor.
		^FFIError signal: 'No matching FFI export: ', descriptor first, ' / ', descriptor second].
	^nil
!
newCallBinding: aDescriptor
	"Create an immutable symbolic binding without preparing any native code."
	| library symbol types result tags resultTag slots descriptor |
	(aDescriptor class == Array and: [aDescriptor size = 5 and: [aDescriptor first == #call]]) ifFalse: [
		^FFIError signal: 'Expected #(call library symbol argumentTypes resultType)'].
	library := self copyName: (aDescriptor at: 2).
	symbol := self copyName: (aDescriptor at: 3).
	types := aDescriptor at: 4.
	result := aDescriptor at: 5.
	(types class == Array and: [types size <= 16]) ifFalse: [
		^FFIError signal: 'FFI argument types must be an Array of up to sixteen Symbols'].
	tags := ByteArray new: types size.
	slots := types size.
	1 to: types size do: [:i |
		| tag |
		tag := self typeTag: (types at: i).
		(#(7 11 12 15) includes: tag) ifTrue: [^FFIError signal: 'Result-only FFI type used as an argument'].
		(tag between: 8 and: 14) ifTrue: [slots := slots + 1].
		tags at: i put: tag].
	slots > 16 ifTrue: [^FFIError signal: 'FFI argument types occupy more than sixteen C slots'].
	resultTag := self typeTag: result.
	(#(5 8 9 10 13 14) includes: resultTag) ifTrue: [^FFIError signal: 'Borrowed types are only FFI argument types'].
	(resultTag = 11 and: [types ~= #(integerMagnitude integerMagnitude) or: [library ~= 'vm:core']]) ifTrue: [
		^FFIError signal: 'Owned integer result requires two magnitudes and a trusted core export'].
	((tags includes: 13) or: [(tags includes: 14) or: [resultTag = 15]]) ifTrue: [
		(library = 'vm:core' and: [
			(types = #(countedText) and: [resultTag = 7]) or: [types = #(cText) and: [resultTag = 15]]])
			ifFalse: [^FFIError signal: 'Synchronous text requires a trusted core signature']].
	tags beReadOnlyObject.
	descriptor := {library. symbol. tags. resultTag}.
	descriptor beReadOnlyObject.
	^FFIBinding new initializeDescriptor: descriptor
!
copyName: anObject
	| name size |
	anObject isString ifFalse: [^FFIError signal: 'FFI library and symbol names must be Strings'].
	size := anObject size.
	(size between: 1 and: 127) ifFalse: [
		^FFIError signal: 'FFI library and symbol names must have 1 to 127 characters'].
	name := ByteString new: size.
	1 to: size do: [:i |
		| ch |
		ch := anObject at: i.
		(ch value between: 1 and: 127) ifFalse: [
			^FFIError signal: 'FFI library and symbol names must be non-NUL ASCII'].
		name at: i put: ch].
	name beReadOnlyObject.
	^name
!
typeTag: aSymbol
	| tag |
	tag := #(i32 u32 i64 u64 byteSlice f64 void bytesWithLength writableBytesWithLength integerMagnitude ownedIntegerMagnitude nonNegativeI64 countedText cText ownedText f32) identityIndexOf: aSymbol.
	tag = 0 ifTrue: [^FFIError signal: 'Unknown FFI type; expected an FFI type Symbol'].
	^tag
! !
