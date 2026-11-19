TestCase subclass: #UefiLibMTest
	instanceVariableNames: 'sim lib'
	classVariableNames: ''
	package: 'Tests-VM'!

UefiLibMTest comment: 'UefiLibM, the C math library of the VM on UEFI, run as Smalltalk (VMSimulation) against what the host''s C library answers (this image''s Floats compute sin, exp ... with it, the tables are glibc''s printf and strtod): sin, cos and atan within an ulp, exp and log within an ulp (glibc''s own algorithms: nearly always the same), the others bit for bit; strtod and formatDouble byte for byte. The C translation is held to glibc over millions of arguments outside the image.'!

!UefiLibMTest methodsFor: 'running'!
setUp
	sim := VMSimulation modules: {UefiLibM}.
	lib := sim module: UefiLibM
!
timeLimitMilliseconds
	^120000
! !

!UefiLibMTest methodsFor: 'helpers'!
ulpsFrom: a to: b
	"The number of doubles between a and b; 0 if both are NaN."
	| ord |
	(a isNaN and: [b isNaN]) ifTrue: [^0].
	(a isNaN or: [b isNaN]) ifTrue: [^SmallInteger maxVal].
	ord := [:f | | i | i := f asIEEEBits. i >= 16r8000000000000000 ifTrue: [16r8000000000000000 - i] ifFalse: [i]].
	^((ord value: a) - (ord value: b)) abs
!
randomDoubles: n
	"n finite doubles of every magnitude and n between -10 and 10, from a fixed seed."
	| random all |
	random := Random seed: 12345.
	all := OrderedCollection new.
	n timesRepeat: [
		| b f |
		b := 0.
		4 timesRepeat: [b := b * 16r10000 + (random nextInt: 16r10000) - 1].
		f := Float fromIEEEBits: b.
		f isFinite ifTrue: [all add: f].
		all add: random next * 20.0 - 10.0].
	^all
!
cString: aString
	| a |
	a := sim memory allocate: aString size + 1.
	sim memory bytesAt: a put: aString asByteArray , #[0].
	^sim memory pointerTo: (CTypeRegistry default at: 'char') at: a
!
format: x conversion: aCharacter precision: p
	| a n |
	a := sim memory allocate: 2000.
	n := lib formatDouble: x precision: p conversion: aCharacter value into: (sim memory pointerTo: (CTypeRegistry default at: 'char') at: a) size: 2000.
	self assert: (sim memory cStringLengthAt: a) equals: n.
	^sim memory stringAt: a
!
strtod: aString do: aBlock
	"aBlock value: the bits strtod answers value: the number of chars it read."
	| s end r |
	s := self cString: aString.
	end := sim memory pointerTo: (CTypeRegistry default parse: 'char *') at: (sim memory allocate: 8).
	r := lib strtod: s end: end.
	aBlock value: r asIEEEBits value: (sim memory addressOf: end value) - (sim memory addressOf: s)
! !

!UefiLibMTest methodsFor: 'tests'!
testTranscendentalsAreWithinAnUlpOfTheHost
	| same |
	same := 0.
	(self randomDoubles: 300) do: [:x |
		self assert: (self ulpsFrom: (lib sin: x) to: x sin) <= 1.
		self assert: (self ulpsFrom: (lib cos: x) to: x cos) <= 1.
		self assert: (self ulpsFrom: (lib atan: x) to: x arcTan) <= 1.
		x abs < 700.0 ifTrue: [
			self assert: (self ulpsFrom: (lib exp: x) to: x exp) <= 1.
			(lib exp: x) = x exp ifTrue: [same := same + 1]].
		x > 0.0 ifTrue: [
			self assert: (self ulpsFrom: (lib log: x) to: x ln) <= 1.
			(lib log: x) = x ln ifTrue: [same := same + 1]]].
	self assert: same >= 550
!
testLargeArgumentsAreReducedExactly
	"sin(10^22) needs 2/pi to some 1100 bits (__rem_pio2_large)."
	self assert: (lib sin: 1.0e22) equals: -0.8522008497671888.
	self assert: (lib cos: 1.0e22) equals: 0.523214785395139.
	#(1.0e300 -1.7976931348623157e308 1.2345e100 6.283185307179586e15 1.0e6 -3.0e9) do: [:x |
		self assert: (self ulpsFrom: (lib sin: x) to: x sin) <= 1.
		self assert: (self ulpsFrom: (lib cos: x) to: x cos) <= 1]
!
testSpecialValues
	| inf nan |
	inf := Float infinity.
	nan := Float nan.
	self assert: (lib sin: -0.0) asIEEEBits equals: 16r8000000000000000.
	self assert: (lib atan: -0.0) asIEEEBits equals: 16r8000000000000000.
	self assert: (lib sin: inf) isNaN.
	self assert: (lib cos: inf negated) isNaN.
	self assert: (lib sin: nan) isNaN.
	self assert: (lib cos: 0.0) equals: 1.0.
	self assert: (lib atan: inf) equals: 1.5707963267948966.
	self assert: (lib atan: inf negated) equals: -1.5707963267948966.
	self assert: (lib exp: 0.0) equals: 1.0.
	self assert: (lib exp: inf negated) equals: 0.0.
	self assert: (lib exp: inf) equals: inf.
	self assert: (lib exp: 710.0) equals: inf.
	self assert: (lib exp: -746.0) equals: 0.0.
	self assert: (lib exp: -745.0) equals: 5.0e-324.
	self assert: (lib exp: 709.782712893384) equals: 1.7976931348622732e308.
	self assert: (lib log: 1.0) asIEEEBits equals: 0.
	self assert: (lib log: 0.0) equals: inf negated.
	self assert: (lib log: -0.0) equals: inf negated.
	self assert: (lib log: inf) equals: inf.
	self assert: (lib log: -1.0) isNaN.
	self assert: (lib log: 5.0e-324) equals: -744.4400719213812.
	self assert: (lib sqrt: -0.0) asIEEEBits equals: 16r8000000000000000.
	self assert: (lib sqrt: -1.0) isNaN.
	self assert: (lib sqrt: 2.0) equals: 2.0 sqrt
!
testFunctionsOfTheBits
	| ip e |
	ip := sim memory pointerTo: (CTypeRegistry default at: 'double') at: (sim memory allocate: 8).
	e := sim memory pointerTo: (CTypeRegistry default at: 'int') at: (sim memory allocate: 8).
	self assert: (lib trunc: -2.75) equals: -2.0.
	self assert: (lib trunc: -0.5) asIEEEBits equals: 16r8000000000000000.
	self assert: (lib trunc: 4503599627370495.5) equals: 4503599627370495.0.
	self assert: (lib trunc: 1.0e300) equals: 1.0e300.
	self assert: (lib fabs: -0.0) asIEEEBits equals: 0.
	self assert: (lib modf: -3.25 integralPart: ip) equals: -0.25.
	self assert: ip value equals: -3.0.
	self assert: (lib modf: Float infinity integralPart: ip) equals: 0.0.
	self assert: ip value equals: Float infinity.
	self assert: (lib frexp: 8.0 exponent: e) equals: 0.5.
	self assert: e value equals: 4.
	self assert: (lib frexp: -5.0e-324 exponent: e) equals: -0.5.
	self assert: e value equals: -1073.
	self assert: (lib ilogb: 5.0e-324) equals: -1074.
	self assert: (lib ilogb: 1.0e300) equals: 996.
	self assert: (lib ilogb: 0.0) equals: -16r80000000.
	self assert: (lib ilogb: Float infinity) equals: 16r7FFFFFFF.
	"ldexp rounds a subnormal result once, half to even"
	self assert: (lib ldexp: 1.5 exponent: -1074) asIEEEBits equals: 2.
	self assert: (lib ldexp: 2.5 exponent: -1074) asIEEEBits equals: 2.
	self assert: (lib ldexp: 3.5 exponent: -1074) asIEEEBits equals: 4.
	self assert: (lib ldexp: 1.0 exponent: 1024) equals: Float infinity.
	self assert: (lib ldexp: 5.0e-324 exponent: 2097) equals: 8.98846567431158e307.
	(self randomDoubles: 200) do: [:x |
		| m |
		x = 0.0 ifFalse: [
			m := lib frexp: x exponent: e.
			self assert: (m abs >= 0.5 and: [m abs < 1.0]).
			self assert: (lib ldexp: m exponent: e value) equals: x.
			self assert: (lib ilogb: x) equals: e value - 1].
		self assert: (lib modf: x integralPart: ip) + ip value equals: x.
		self assert: ip value equals: (lib trunc: x).
		self assert: (lib sqrt: x abs) equals: x abs sqrt]
!
testFormatDoubleAsGlibc
	"snprintf(buf, n, ""%.*<c>"", p, x) answered these (p -1: ""%<c>"")."
	#(
(0.0 $f 1 '0.0')
		(0.0 $f 3 '0.000')
		(0.0 $g 1 '0')
		(0.0 $E 0 '0E+00')
		(0.0 $G -1 '0')
		(-0.0 $f 0 '-0')
		(-0.0 $g -1 '-0')
		(-0.0 $g 1 '-0')
		(0.5 $e -1 '5.000000e-01')
		(0.5 $f 1 '0.5')
		(0.5 $f 3 '0.500')
		(0.5 $G 1 '0.5')
		(0.5 $G 3 '0.5')
		(2.5 $e -1 '2.500000e+00')
		(2.5 $e 1 '2.5e+00')
		(2.5 $f 0 '2')
		(2.5 $f 1 '2.5')
		(2.5 $f 3 '2.500')
		(2.5 $g 3 '2.5')
		(2.5 $G -1 '2.5')
		(2.5 $G 1 '2')
		(1.0e-5 $e 1 '1.0e-05')
		(1.0e-5 $e 17 '1.00000000000000008e-05')
		(1.0e-5 $g 3 '1e-05')
		(1.0e-5 $E 17 '1.00000000000000008E-05')
		(123.456 $g 1 '1e+02')
		(123.456 $E 1 '1.2E+02')
		(123.456 $E 17 '1.23456000000000003E+02')
		(123.456 $G -1 '123.456')
		(1.0e300 $f 17 '1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.00000000000000000')
		(1.0e300 $g 3 '1e+300')
		(1.0e300 $E 0 '1E+300')
		(5.0e-324 $e 3 '4.941e-324')
		(5.0e-324 $f 1 '0.0')
		(5.0e-324 $E -1 '4.940656E-324')
		(5.0e-324 $E 3 '4.941E-324')
		(5.0e-324 $E 17 '4.94065645841246544E-324')
		(5.0e-324 $G -1 '4.94066E-324')
		(5.0e-324 $G 0 '5E-324')
		(1.7976931348623157e308 $e 0 '2e+308')
		(1.7976931348623157e308 $e 3 '1.798e+308')
		(1.7976931348623157e308 $e 17 '1.79769313486231571e+308')
		(1.7976931348623157e308 $f 0 '179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368')
		(1.7976931348623157e308 $g 3 '1.8e+308')
		(1.7976931348623157e308 $E -1 '1.797693E+308')
		(1.7976931348623157e308 $E 17 '1.79769313486231571E+308')
		(1.7976931348623157e308 $G 3 '1.8E+308')
		(1.7976931348623157e308 $G 17 '1.7976931348623157E+308')
		(0.1 $E -1 '1.000000E-01')
		(-1.5 $e 1 '-1.5e+00')
		(-1.5 $g -1 '-1.5')
		(-1.5 $E -1 '-1.500000E+00')
		(-1.5 $E 3 '-1.500E+00')
		(-1.5 $E 17 '-1.50000000000000000E+00')
		(9.9999995 $e 0 '1e+01')
		(9.9999995 $f -1 '9.999999')
		(9.9999995 $f 0 '10')
		(9.9999995 $f 3 '10.000')
		(9.9999995 $g 3 '10')
		(9.9999995 $E 1 '1.0E+01')
		(9.9999995 $G 0 '1E+01')
		(1.0e22 $e 0 '1e+22')
		(1.0e22 $e 1 '1.0e+22')
		(1.0e22 $e 17 '1.00000000000000000e+22')
		(1.0e22 $f 17 '10000000000000000000000.00000000000000000')
		(1.0e22 $g 0 '1e+22')
		(1.0e22 $E 3 '1.000E+22')
		(1.0e22 $G -1 '1E+22')
		(1.23456e-4 $e 1 '1.2e-04')
		(1.23456e-4 $e 3 '1.235e-04')
		(1.23456e-4 $e 17 '1.23456000000000005e-04')
		(1.23456e-4 $f -1 '0.000123')
		(1.23456e-4 $f 3 '0.000')
		(1.23456e-4 $g -1 '0.000123456')
		(1.23456e-4 $E 0 '1E-04')
		(1.23456e-4 $E 3 '1.235E-04')
		(1.23456e-4 $G 3 '0.000123')
		(1.23456e-4 $G 17 '0.00012345600000000001')
		(999999.5 $f 3 '999999.500')
		(999999.5 $g 1 '1e+06')
		(999999.5 $g 17 '999999.5')
		(999999.5 $E 0 '1E+06')
		(999999.5 $G 3 '1E+06')
		(999999.5 $G 17 '999999.5')
		(0.3333333333333333 $e 0 '3e-01')
		(0.3333333333333333 $e 1 '3.3e-01')
		(0.3333333333333333 $G -1 '0.333333')
		(1.0e300 $f 0 '1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160')
		(5.0e-324 $e 760 '4.9406564584124654417656879286822137236505980261432476442558568250067550727020875186529983636163599237979656469544571773092665671035593979639877479601078187812630071319031140452784581716784898210368871863605699873072305000638740915356498438731247339727316961514003171538539807412623856559117102665855668676818703956031062493194527159149245532930545654440112748012970999954193198940908041656332452475714786901472678015935523861155013480352649347201937902681071074917033322268447533357208324319360923828934583680601060115061698097530783422773183292479049825247307763759272478746560847782037344696995336470179726777175851256605511991315048911014510378627381672509558373897335989936648099411642057026370902792427675445652290875386825064197182655334472656250000000000e-324')
		(-1.5 $f 0 '-2')
		(0.5 $f 0 '0')
		(0.125 $f 2 '0.12')
		(0.375 $f 2 '0.38')
		(1.0e100 $g -1 '1e+100')
		(1.0e-100 $E 3 '1.000E-100'))
	do: [:each |
		self assert: (self format: each first conversion: (each at: 2) precision: (each at: 3)) equals: (each at: 4)].
	self assert: (self format: Float infinity conversion: $f precision: 2) equals: 'inf'.
	self assert: (self format: Float infinity negated conversion: $G precision: 2) equals: '-INF'.
	self assert: (self format: (Float fromIEEEBits: 16r7FF8000000000000) conversion: $e precision: 2) equals: 'nan'.
	self assert: (self format: (Float fromIEEEBits: 16rFFF8000000000000) conversion: $E precision: 2) equals: '-NAN'
!
testFormatDoubleTruncates
	| a n |
	a := sim memory allocate: 16.
	sim memory bytesAt: a put: #[120 120 120 120 120 120 120 120].
	n := lib formatDouble: 3.25 precision: 4 conversion: $f value into: (sim memory pointerTo: (CTypeRegistry default at: 'char') at: a) size: 4.
	self assert: n equals: 6.
	self assert: (sim memory stringAt: a) equals: '3.2'.
	self assert: (sim memory uint8At: a + 4) equals: 120.
	n := lib formatDouble: 3.25 precision: 4 conversion: $f value into: (sim memory pointerTo: (CTypeRegistry default at: 'char') at: a) size: 0.
	self assert: n equals: 6.
	self assert: (sim memory uint8At: a) equals: 51
!
testStrtodAsGlibc
	"strtod(s, &end) answered these bits and end - s."
	#(
		('0.1' 16r3FB999999999999A 3)
		('  -12.5e-3xyz' 16rBF8999999999999A 10)
		('1e400' 16r7FF0000000000000 5)
		('-1e-400' 16r8000000000000000 7)
		('2.4703282292062327e-324' 16r0 23)
		('2.4703282292062328e-324' 16r1 23)
		('1.7976931348623158e308' 16r7FEFFFFFFFFFFFFF 22)
		('1.7976931348623159e308' 16r7FF0000000000000 22)
		('2.2250738585072011e-308' 16rFFFFFFFFFFFFF 23)
		('9007199254740993' 16r4340000000000000 16)
		('9007199254740993.000000000000000000000000000001' 16r4340000000000001 47)
		('123456789012345678901234567890e-30' 16r3FBF9ADD3746F65F 34)
		('infinity' 16r7FF0000000000000 8)
		('-INF' 16rFFF0000000000000 4)
		('nan' 16r7FF8000000000000 3)
		('-nan(0x12)' 16rFFF8000000000012 10)
		('nan(' 16r7FF8000000000000 3)
		('.e1' 16r0 0)
		('1e' 16r3FF0000000000000 1)
		('+.5' 16r3FE0000000000000 3)
		('1.e5' 16r40F86A0000000000 4))
	do: [:each |
		self strtod: each first do: [:bits :n |
			self assert: bits equals: (each at: 2).
			self assert: n equals: (each at: 3)]]
!
testStrtodReadsWhatFormatDoubleWrites
	(self randomDoubles: 150) do: [:x |
		self strtod: (self format: x conversion: $g precision: 17) do: [:bits :n | self assert: bits equals: x asIEEEBits].
		self strtod: (self format: x conversion: $e precision: 30) do: [:bits :n | self assert: bits equals: x asIEEEBits].
		self strtod: x printString do: [:bits :n | self assert: bits equals: x asIEEEBits]]
!
testStrtodRoundsHalfToEven
	"Exactly halfway between two doubles: the even one; any digit beyond, however far, decides."
	self strtod: '9007199254740993' do: [:bits :n | self assert: bits equals: 16r4340000000000000].
	self strtod: '9007199254740995' do: [:bits :n | self assert: bits equals: 16r4340000000000002].
	self strtod: '9007199254740993.' , (String new: 900 withAll: $0) , '1' do: [:bits :n |
		self assert: bits equals: 16r4340000000000001.
		self assert: n equals: 918].
	self strtod: '0.' , (String new: 1000 withAll: $0) , '1e1001' do: [:bits :n | self assert: bits equals: 1.0 asIEEEBits]
! !
