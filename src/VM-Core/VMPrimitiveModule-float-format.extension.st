!VMPrimitiveModule methodsFor: 'float formatting'!
finiteFloatDecimal: a in: out
	"Shortest-round-trip ASCII for a finite nonzero double. out has at least 64 bytes. Inline into both native paths."
	<var: #lo type: 'int'>
	<var: #hi type: 'int'>
	<var: #mid type: 'int'>
	<var: #nd type: 'int'>
	| buf digits lo hi mid neg s nd exp o |
	buf := self local: 'char[40]'.
	digits := self local: 'char[24]'.
	"the fewest significant digits that read back as a (17 always do), by bisection"
	lo := 1.
	hi := 17.
	[lo < hi] whileTrue: [
		mid := lo + hi quo: 2.
		libc snprintf: buf size: 40 format: '%.*e' with: mid - 1 with: a.
		(libm strtod: buf end: self null) = a ifTrue: [hi := mid] ifFalse: [lo := mid + 1]].
	libc snprintf: buf size: 40 format: '%.*e' with: lo - 1 with: a.
	neg := (buf at: 0) = $- value.
	s := neg ifTrue: [buf + 1] ifFalse: [buf].
	nd := 0.
	[(s at: 0) ~= 0 and: [(s at: 0) ~= $e value]] whileTrue: [
		(s at: 0) ~= $. value ifTrue: [
			digits at: nd put: (s at: 0).
			nd := nd + 1].
		s := s + 1].
	[nd > 1 and: [(digits at: nd - 1) = $0 value]] whileTrue: [nd := nd - 1].
	digits at: nd put: 0.
	exp := libc atoi: s + 1.
	o := out.
	neg ifTrue: [
		o at: 0 put: $- value.
		o := o + 1].
	(exp >= -5 and: [exp < 16])
		ifTrue: [
			exp < 0
				ifTrue: [
					o at: 0 put: $0 value.
					o at: 1 put: $. value.
					o := o + 2.
					1 to: exp negated - 1 do: [:i |
						o at: 0 put: $0 value.
						o := o + 1].
					0 to: nd - 1 do: [:i |
						o at: 0 put: (digits at: i).
						o := o + 1]]
				ifFalse: [
					0 to: exp do: [:i |
						o at: 0 put: (i < nd ifTrue: [digits at: i] ifFalse: [$0 value asInt8]).
						o := o + 1].
					o at: 0 put: $. value.
					o := o + 1.
					nd > (exp + 1)
						ifTrue: [
							exp + 1 to: nd - 1 do: [:i |
								o at: 0 put: (digits at: i).
								o := o + 1]]
						ifFalse: [
							o at: 0 put: $0 value.
							o := o + 1]].
			o at: 0 put: 0]
		ifFalse: [
			o at: 0 put: (digits at: 0).
			o at: 1 put: $. value.
			o := o + 2.
			nd > 1
				ifTrue: [
					1 to: nd - 1 do: [:i |
						o at: 0 put: (digits at: i).
						o := o + 1]]
				ifFalse: [
					o at: 0 put: $0 value.
					o := o + 1].
			libc snprintf: o size: 16 format: 'e%d' with: exp].
! !
