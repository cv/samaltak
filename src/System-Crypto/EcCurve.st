Object subclass: #EcCurve
	instanceVariableNames: 'name p b n gx gy byteLength'
	classVariableNames: 'Curves'
	package: 'System-Crypto'!

EcCurve comment: 'I am a short Weierstrass curve y^2 = x^3 - 3x + b over a prime field, with a base point of prime order n: NIST P-256 (secp256r1) or P-384 (secp384r1), from SEC 2 / FIPS 186-4. EcCurve named: #p256 (or #p384). I hold the parameters and decode and encode points (checking they are on me) for EcPublicKey, whose verification is the VM''s (CryptoExports).'!

!EcCurve methodsFor: 'accessing'!
name
	^name
!
prime
	^p
!
b
	^b
!
order
	^n
!
generator
	"The base point, Jacobian."
	^{gx. gy. 1}
!
byteLength
	"The length of a field element or a scalar, in bytes."
	^byteLength
! !

!EcCurve methodsFor: 'points'!
isOnCurveX: x y: y
	"Whether the affine point (x, y) has coordinates in the field and is on me."
	(x >= 0 and: [x < p and: [y >= 0 and: [y < p]]]) ifFalse: [^false].
	^(y * y - (x * x * x) + (3 * x) - b) \\ p = 0
!
decodePoint: bytes
	"The affine point {x. y} of an uncompressed encoding (SEC 1: 04 || X || Y), nil unless it is one on me (not infinity)."
	| x y |
	(bytes size = (2 * byteLength + 1) and: [(bytes at: 1) = 4]) ifFalse: [^nil].
	x := 0.
	2 to: byteLength + 1 do: [:i | x := (x bitShift: 8) + (bytes at: i)].
	y := 0.
	byteLength + 2 to: bytes size do: [:i | y := (y bitShift: 8) + (bytes at: i)].
	(self isOnCurveX: x y: y) ifFalse: [^nil].
	^{x. y}
!
encodeX: x y: y
	"The uncompressed encoding of the affine point (x, y)."
	| out |
	out := ByteArray new: 2 * byteLength + 1.
	out at: 1 put: 4.
	1 to: byteLength do: [:i |
		out at: byteLength + 2 - i put: (x digitAt: i).
		out at: 2 * byteLength + 2 - i put: (y digitAt: i)].
	^out
! !

!EcCurve methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'EcCurve '; print: name
! !

!EcCurve methodsFor: 'private'!
setName: aSymbol p: prime b: coefficient n: order gx: x gy: y
	name := aSymbol.
	p := prime.
	b := coefficient.
	n := order.
	gx := x.
	gy := y.
	byteLength := p highBit + 7 // 8
! !

!EcCurve class methodsFor: 'instance creation'!
named: aSymbol
	"The curve #p256 or #p384 (also #secp256r1, #secp384r1); CryptoError for another."
	| key |
	key := aSymbol asSymbol.
	key == #secp256r1 ifTrue: [key := #p256].
	key == #secp384r1 ifTrue: [key := #p384].
	Curves isNil ifTrue: [Curves := IdentityDictionary new].
	^Curves at: key ifAbsent: [
		(#(#p256 #p384) includes: key) ifFalse: [^CryptoError signal: 'EC: unsupported curve ', aSymbol printString].
		Curves at: key put: (self perform: key)]
!
p256
	^self new
		setName: #p256
		p: 16rFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
		b: 16r5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
		n: 16rFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
		gx: 16r6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296
		gy: 16r4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5
!
p384
	^self new
		setName: #p384
		p: 16rFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFF0000000000000000FFFFFFFF
		b: 16rB3312FA7E23EE7E4988E056BE3F82D19181D9C6EFE8141120314088F5013875AC656398D8A2ED19D2A85C8EDD3EC2AEF
		n: 16rFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC7634D81F4372DDF581A0DB248B0A77AECEC196ACCC52973
		gx: 16rAA87CA22BE8B05378EB1C71EF320AD746E1D3B628BA79B9859F741E082542A385502F25DBF55296C3A545E3872760AB7
		gy: 16r3617DE4A96262C6F5D9E98BF9292DC29F8F41DBD289A147CE9DA3113B5F0B8C00A60B1CE1D7E819D7A431D7C90EA0E5F
! !
