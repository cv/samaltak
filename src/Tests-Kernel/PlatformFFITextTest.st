TestCase subclass: #PlatformFFITextTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

!PlatformFFITextTest methodsFor: 'tests'!
testInputRepresentations
	| raw wide |
	raw := #[255 128 195 169].
	self assert: (PlatformFFI textBytes: raw) == raw.
	self assert: (PlatformFFI cTextBytes: raw) == raw.
	self assert: (PlatformFFI cTextBytes: 'ascii') equals: #[97 115 99 105 105].
	self assert: (PlatformFFI cTextBytes: #ascii) equals: #[97 115 99 105 105].
	self assert: (PlatformFFI cTextBytes: (String with: (Character value: 233))) equals: #[195 169].
	wide := String with: (Character value: 16r1F642).
	self assert: (PlatformFFI cTextBytes: wide) equals: #[240 159 153 130].
	self assert: (PlatformFFI cTextBytes: wide asSymbol) equals: #[240 159 153 130].
	self assert: (PlatformFFI cTextBytes: 0) isNil.
	self assert: (PlatformFFI cTextBytes: #(65 66)) isNil
!
testNulPolicies
	| raw text |
	raw := #[97 0 98].
	text := String with: $a with: Character null with: $b.
	self assert: (PlatformFFI textBytes: raw) == raw.
	self assert: (PlatformFFI textBytes: text) equals: raw.
	self assert: (PlatformFFI cTextBytes: raw) isNil.
	self assert: (PlatformFFI cTextBytes: text) isNil.
	self assert: (PlatformFFI textFromBytes: raw) equals: text.
	self assert: (PlatformFFI textFromBytes: nil) isNil.
	self assert: (PlatformFFI textFromBytes: #[]) equals: ''.
	self assert: (PlatformFFI cTextBytes: '') equals: #[].
	self assert: (PlatformFFI cTextBytes: nil) isNil.
	self should: [PlatformFFI textFromBytes: #(0)] raise: Error
!
testInvalidCodePoints
	| wide |
	wide := WideString new: 9.
	#(16rD7FF 16rD800 16rDC7F 16rDC80 16rDCFF 16rDD00 16rDFFF 16r110000 16rFFFFFFFF)
		doWithIndex: [:cp :i | wide basicAt: i put: cp].
	self assert: (PlatformFFI textBytes: wide) equals:
		#[237 159 191 239 191 189 239 191 189 128 255 239 191 189 239 191 189 239 191 189 239 191 189]
!
testDecodeSurrogateescape
	| data decoded values all |
	"Stray byte, overlong, surrogate, out of range, embedded NUL, Latin-1, valid wide, truncated prefix."
	data := #[128 192 175 237 160 128 244 144 128 128 0 195 169 240 159 153 130 226 130].
	decoded := PlatformFFI textFromBytes: data.
	values := Array new: decoded size.
	decoded doWithIndex: [:ch :i | values at: i put: ch value].
	self assert: values equals:
		#(16rDC80 16rDCC0 16rDCAF 16rDCED 16rDCA0 16rDC80 16rDCF4 16rDC90 16rDC80 16rDC80 0 233 16r1F642 16rDCE2 16rDC82).
	self assert: (PlatformFFI textBytes: decoded) equals: data.
	self assert: (PlatformFFI textFromBytes: #[195 169]) class == ByteString.
	all := (0 to: 255) asByteArray.
	self assert: (PlatformFFI textBytes: (PlatformFFI textFromBytes: all)) equals: all
! !
