Object subclass: #FFI
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Support'!

FFI comment: 'I bind descriptors for registered native exports. A downcall descriptor is #(call library symbol argumentTypes resultType). The library and symbol are Strings of 1 to 127 non-NUL ASCII characters. argumentTypes is an Array of up to six type Symbols, and resultType is a type Symbol. A literal or a computed Array works the same way.

	(FFI bind: #(call ''libm'' ''sqrt'' (f64) f64)) invoke: #(9.0).

Scalar types are i32, u32, i64, u64 and f64. Use void only for a result (answers nil). For a launcher grant, bytesWithLength takes one read-only slice {aByteArray. oneBasedOffset. length} and passes a pointer and the validated length in two of at most six C slots. For memcmp, use (byteSlice byteSlice u64); the comparison count may not exceed either slice length. No argument or result is a native address. Unknown exports, mismatched signatures and rejected arguments signal FFIError. Notification descriptors start with #notification; FFINotification handles their schema.'!

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
	| library symbol types result tags resultTag id slots |
	aDescriptor size = 5 ifFalse: [
		^FFIError signal: 'Expected #(call library symbol argumentTypes resultType)'].
	library := self copyName: (aDescriptor at: 2).
	symbol := self copyName: (aDescriptor at: 3).
	types := aDescriptor at: 4.
	result := aDescriptor at: 5.
	(types class == Array and: [types size <= 6]) ifFalse: [
		^FFIError signal: 'FFI argument types must be an Array of up to six Symbols'].
	tags := ByteArray new: types size.
	slots := types size.
	1 to: types size do: [:i |
		| tag |
		tag := self typeTag: (types at: i).
		tag = 7 ifTrue: [^FFIError signal: '#void is only an FFI result type'].
		tag = 8 ifTrue: [slots := slots + 1].
		tags at: i put: tag].
	slots > 6 ifTrue: [^FFIError signal: 'FFI argument types occupy more than six C slots'].
	resultTag := self typeTag: result.
	(resultTag = 5 or: [resultTag = 8]) ifTrue: [^FFIError signal: 'Byte slices are only FFI argument types'].
	tags beReadOnlyObject.
	id := self primBind: library symbol: symbol types: tags result: resultTag.
	^FFIBinding new initializeID: id library: library symbol: symbol types: tags result: resultTag
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
	tag := #(i32 u32 i64 u64 byteSlice f64 void bytesWithLength) identityIndexOf: aSymbol.
	tag = 0 ifTrue: [^FFIError signal: 'Unknown FFI type; expected an FFI type Symbol'].
	^tag
!
primBind: library symbol: symbol types: tags result: resultTag
	<primitive: 'ffiBind'>
	^FFIError signal: 'No matching FFI export: ', library, ' / ', symbol
! !
