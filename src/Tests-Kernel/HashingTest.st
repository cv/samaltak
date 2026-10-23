TestCase subclass: #HashingTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

HashingTest comment: 'Tests hash consistency and the hashed collections (Set, IdentitySet, Dictionary, IdentityDictionary) under growth and removal.'!

!HashingTest methodsFor: 'tests'!
testEqualObjectsHaveEqualHashes
	self assert: 'abc' hash = 'abc' copy hash.
	self assert: 'abc' hash = #abc hash.
	self assert: (String with: (Character value: 955)) hash = (String with: (Character value: 955)) asWideString hash.
	self assert: 3 hash = 3.0 hash.
	self assert: (1 / 2) hash = 0.5 hash.
	self assert: (2 raisedTo: 80) hash = ((2 raisedTo: 80) + 1 - 1) hash.
	self assert: (2 raisedTo: 80) hash = (2 raisedTo: 80) asFloat hash.
	self assert: #(1 2 3) hash = (Array with: 1 with: 2 with: 3) hash.
	self assert: (1 -> 2) hash = (1 -> 2) hash.
	self assert: (3 @ 4) hash = (3 @ 4) hash.
	self assert: (Set withAll: #(1 2)) hash = (Set withAll: #(2 1)) hash
!
testSet
	| s |
	s := Set new.
	1 to: 1000 do: [:i | s add: i printString].
	self assert: s size = 1000.
	self assert: (s includes: '500').
	self assert: (s includes: #'500').
	s add: '500'.
	self assert: s size = 1000.
	1 to: 1000 by: 2 do: [:i | s remove: i printString].
	self assert: s size = 500.
	self deny: (s includes: '1').
	2 to: 1000 by: 2 do: [:i | self assert: (s includes: i printString)].
	self assert: (s collect: [:x | x size]) = (Set withAll: #(1 2 3 4)).
	self should: [s add: nil] raise: Error.
	self assert: (Set withAll: #(1 2 3)) = (Set withAll: #(3 2 1))
!
testIdentitySet
	| s a b |
	a := 'x' copy.
	b := 'x' copy.
	s := IdentitySet new.
	s add: a; add: b.
	self assert: s size = 2.
	self assert: (s includes: a).
	self deny: (s includes: 'x' copy)
!
testDictionary
	| d |
	d := Dictionary new.
	1 to: 500 do: [:i | d at: i put: i * i].
	self assert: d size = 500.
	self assert: (d at: 20) = 400.
	self assert: (d at: 1000 ifAbsent: [#none]) = #none.
	1 to: 500 by: 3 do: [:i | d removeKey: i].
	self assert: d size = 333.
	self assert: (d includesKey: 2).
	self deny: (d includesKey: 1).
	2 to: 500 by: 3 do: [:i | self assert: (d at: i) = (i * i)].
	self assert: (d keyAtValue: 4) = 2.
	self assert: (d includes: 4).
	self should: [d at: 1] raise: KeyNotFound.
	self should: [d removeKey: 1] raise: KeyNotFound
!
testDictionaryProtocol
	| d |
	d := Dictionary new.
	d at: #a put: 1; at: #b put: 2.
	self assert: (d at: #c ifAbsentPut: [3]) = 3.
	self assert: (d at: #c ifAbsentPut: [4]) = 3.
	self assert: (d at: #a ifPresent: [:v | v * 10]) = 10.
	self assert: (d at: #z ifPresent: [:v | v]) isNil.
	self assert: d keys asSortedCollection asArray = #(#a #b #c).
	self assert: d values asSortedCollection asArray = #(1 2 3).
	self assert: (d collect: [:v | v * 2]) = (Dictionary new at: #a put: 2; at: #b put: 4; at: #c put: 6; yourself).
	self assert: (d select: [:v | v > 1]) size = 2.
	self assert: (d inject: 0 into: [:a :v | a + v]) = 6.
	self assert: (d associationAt: #a) key == #a.
	self assert: (d keysAndValuesDo: [:k :v | ]) == d.
	self assert: d copy = d.
	self deny: d copy == d.
	self assert: (Dictionary new at: #a put: 1; yourself) printString = 'a Dictionary(#a->1 )'.
	self assert: (Dictionary newFromPairs: #(1 2 3 4)) size = 2
!
testIdentityDictionary
	| d k1 k2 |
	k1 := 'key' copy.
	k2 := 'key' copy.
	d := IdentityDictionary new.
	d at: k1 put: 1; at: k2 put: 2.
	self assert: d size = 2.
	self assert: (d at: k1) = 1.
	self assert: (d at: k2) = 2.
	self assert: (d at: 'key' ifAbsent: [0]) = 0
!
testMixedKeys
	| d |
	d := Dictionary new.
	d at: 1 put: #int; at: 1.5 put: #float; at: 'one' put: #string; at: #sym put: #symbol; at: (1/3) put: #fraction; at: nil put: #nil.
	self assert: (d at: 1) == #int.
	self assert: (d at: 1.0) == #int.
	self assert: (d at: 3/2) == #float.
	self assert: (d at: #sym) == #symbol.
	self assert: (d at: 'one' copy) == #string.
	self assert: (d at: (2/6)) == #fraction.
	self assert: (d at: nil) == #nil
! !
