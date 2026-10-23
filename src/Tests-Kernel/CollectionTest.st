TestCase subclass: #CollectionTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

CollectionTest comment: 'Tests the enumeration, conversion, copying and printing protocol shared by the collection classes, mostly on Arrays, Intervals and OrderedCollections.'!

!CollectionTest methodsFor: 'tests'!
testEnumeration
	| a sum |
	a := #(1 2 3 4 5).
	self assert: (a collect: [:x | x * x]) = #(1 4 9 16 25).
	self assert: (a select: [:x | x even]) = #(2 4).
	self assert: (a reject: [:x | x even]) = #(1 3 5).
	self assert: (a detect: [:x | x > 3]) = 4.
	self assert: (a detect: [:x | x > 10] ifNone: [0]) = 0.
	self should: [a detect: [:x | x > 10]] raise: NotFound.
	self assert: (a inject: 0 into: [:acc :x | acc + x]) = 15.
	self assert: (a with: a collect: [:x :y | x + y]) = #(2 4 6 8 10).
	sum := 0.
	a doWithIndex: [:x :i | sum := sum + (x * i)].
	self assert: sum = 55.
	sum := 0.
	a keysAndValuesDo: [:i :x | sum := sum + i].
	self assert: sum = 15.
	sum := OrderedCollection new.
	a reverseDo: [:x | sum add: x].
	self assert: sum asArray = #(5 4 3 2 1).
	sum := WriteStream on: String new.
	a do: [:x | sum print: x] separatedBy: [sum nextPutAll: ', '].
	self assert: sum contents = '1, 2, 3, 4, 5'.
	self assert: (a allSatisfy: [:x | x > 0]).
	self assert: (a anySatisfy: [:x | x > 4]).
	self deny: (a anySatisfy: [:x | x > 5]).
	self assert: (a noneSatisfy: [:x | x > 5]).
	self assert: (a count: [:x | x odd]) = 3.
	self assert: (a includes: 3).
	self deny: (a includes: 7).
	self assert: (a detectMax: [:x | x \\ 4]) = 3.
	self assert: (#(#(1 2) #(3)) flatCollect: [:x | x]) asArray = #(1 2 3)
!
testTesting
	self assert: #() isEmpty.
	self assert: #(1) notEmpty.
	self assert: (#() ifEmpty: ['empty']) = 'empty'.
	self assert: (#(1) ifEmpty: ['empty']) = #(1).
	self assert: (#(1 2) ifNotEmpty: [:c | c size]) = 2.
	self assert: (#() ifEmpty: [0] ifNotEmpty: [:c | c size]) = 0.
	self assert: (#(1 2 2 3) occurrencesOf: 2) = 2
!
testAggregates
	self assert: #(3 1 4 1 5) max = 5.
	self assert: #(3 1 4 1 5) min = 1.
	self assert: #(1 2 3) sum = 6.
	self assert: #() sum = 0.
	self assert: (#(1 2 3) sum: [:x | x * 10]) = 60.
	self assert: #(1 2 3 4) average = (5 / 2).
	self should: [#() average] raise: CollectionIsEmpty.
	self should: [#() max] raise: CollectionIsEmpty
!
testConversion
	| a |
	a := #(3 1 2 3).
	self assert: a asOrderedCollection class == OrderedCollection.
	self assert: a asSet size = 3.
	self assert: (a asBag occurrencesOf: 3) = 2.
	self assert: a asSortedCollection asArray = #(1 2 3 3).
	self assert: (a asSortedCollection: [:x :y | x >= y]) asArray = #(3 3 2 1).
	self assert: a sorted = #(1 2 3 3).
	self assert: (a sorted: [:x :y | x > y]) = #(3 3 2 1).
	self assert: a = #(3 1 2 3).
	self assert: (1 to: 3) asArray = #(1 2 3).
	self assert: (Set withAll: #(1 2)) asArray size = 2.
	self assert: #(1 $a) asOrderedCollection asArray = #(1 $a)
!
testSequenceableAccess
	| a |
	a := #(10 20 30 40 50).
	self assert: a first = 10.
	self assert: a last = 50.
	self assert: (a first: 2) = #(10 20).
	self assert: (a last: 2) = #(40 50).
	self assert: a allButFirst = #(20 30 40 50).
	self assert: a allButLast = #(10 20 30 40).
	self assert: (a indexOf: 30) = 3.
	self assert: (a indexOf: 31) = 0.
	self assert: (a copyFrom: 2 to: 4) = #(20 30 40).
	self assert: (a copyWith: 60) = #(10 20 30 40 50 60).
	self assert: (a copyWithout: 30) = #(10 20 40 50).
	self assert: a reversed = #(50 40 30 20 10).
	self assert: a , #(60) = #(10 20 30 40 50 60).
	self assert: (a copyReplaceAll: #(20 30) with: #(1)) = #(10 1 40 50).
	self assert: (#(1 2 3) beginsWith: #(1 2)).
	self assert: (#(1 2 3) endsWith: #(2 3)).
	self assert: (#(1 2 3 2 1) lastIndexOf: 2) = 4.
	self should: [#() first] raise: CollectionIsEmpty
!
testSorting
	| a random sorted |
	a := #(5 3 9 1 7) copy.
	a sort.
	self assert: a = #(1 3 5 7 9).
	a sort: [:x :y | x > y].
	self assert: a = #(9 7 5 3 1).
	random := Random seed: 7.
	a := (1 to: 500) collect: [:i | random nextInt: 100].
	sorted := a sorted.
	self assert: sorted isSorted.
	self assert: sorted size = 500.
	self assert: sorted asBag = a asBag.
	a := #('pear' 'fig' 'apple' 'kiwi') asSortedCollection: [:x :y | x size <= y size].
	self assert: a asArray = #('fig' 'pear' 'kiwi' 'apple')
!
testArrayPrinting
	self assert: #(1 2 3) printString = '#(1 2 3)'.
	self assert: #(1 $a 'str' #sym #(1 2) nil true) printString = '#(1 $a ''str'' #sym #(1 2) nil true)'.
	self assert: (Array with: 3 @ 4 with: 5) printString = '#(3@4 5)'.
	self assert: #() printString = '#()'.
	self assert: (Array new: 2) printString = '#(nil nil)'
!
testOtherPrinting
	self assert: (OrderedCollection with: 1 with: 2) printString = 'an OrderedCollection(1 2)'.
	self assert: (Set with: 1) printString = 'a Set(1)'.
	self assert: (1 to: 5) printString = '(1 to: 5)'.
	self assert: (1 to: 9 by: 2) printString = '(1 to: 9 by: 2)'.
	self assert: (Bag with: 1 with: 1) printString = 'a Bag(1 1)'.
	self assert: #[1 2 255] printString = '#[1 2 255]'.
	self assert: (ByteArray with: 1 with: 2) printString = '#[1 2]'
!
testArrayCreation
	self assert: (Array new: 3) size = 3.
	self assert: (Array new: 2 withAll: 7) = #(7 7).
	self assert: (Array with: 1 with: 2 with: 3) = #(1 2 3).
	self assert: {1 + 1. 2 * 3} = #(2 6).
	self assert: (Array withAll: (OrderedCollection with: 4 with: 5)) = #(4 5).
	self assert: (Array new: 0) isEmpty
!
testEquality
	self assert: #(1 2) = #(1 2).
	self deny: #(1 2) = #(2 1).
	self deny: #(1 2) = (OrderedCollection with: 1 with: 2).
	self assert: (1 to: 3) = #(1 2 3).
	self assert: #(1 2 3) = (1 to: 3).
	self assert: #(1 2) hash = #(1 2) hash.
	self assert: (OrderedCollection with: 1) = (OrderedCollection with: 1)
!
testInterval
	| i |
	i := 1 to: 10 by: 3.
	self assert: i asArray = #(1 4 7 10).
	self assert: i size = 4.
	self assert: i last = 10.
	self assert: (10 to: 1 by: -3) asArray = #(10 7 4 1).
	self assert: (1 to: 0) isEmpty.
	self assert: (i includes: 7).
	self deny: (i includes: 8).
	self assert: (i collect: [:x | x * 2]) = #(2 8 14 20).
	self assert: (i select: [:x | x odd]) = #(1 7).
	self assert: (i inject: 0 into: [:a :b | a + b]) = 22.
	self assert: (1 to: 5) reversed asArray = #(5 4 3 2 1).
	self assert: ((1 to: 2 by: 1/2) collect: [:x | x]) = {1. 3/2. 2}
!
testOrderedCollection
	| oc |
	oc := OrderedCollection new.
	oc add: 2; add: 3; addFirst: 1.
	self assert: oc asArray = #(1 2 3).
	self assert: oc removeFirst = 1.
	self assert: oc removeLast = 3.
	self assert: oc asArray = #(2).
	1 to: 100 do: [:i | oc addLast: i].
	1 to: 100 do: [:i | oc addFirst: i negated].
	self assert: oc size = 201.
	self assert: oc first = -100.
	self assert: oc last = 100.
	self assert: (oc at: 101) = 2.
	oc at: 101 put: 99.
	self assert: (oc at: 101) = 99.
	oc remove: 99.
	self assert: oc size = 200.
	self should: [oc remove: 1000] raise: NotFound.
	self assert: (oc remove: 1000 ifAbsent: [#none]) = #none.
	oc := OrderedCollection withAll: #(1 2 3 4).
	oc add: 10 beforeIndex: 2.
	self assert: oc asArray = #(1 10 2 3 4).
	self assert: (oc removeIndex: 2) = 10.
	oc removeAllSuchThat: [:x | x even].
	self assert: oc asArray = #(1 3).
	self assert: (oc collect: [:x | x * 2]) class == OrderedCollection.
	self assert: (oc select: [:x | x > 1]) asArray = #(3).
	self assert: (oc , #(5)) asArray = #(1 3 5).
	self assert: (oc copyWith: 9) asArray = #(1 3 9).
	self assert: oc reversed asArray = #(3 1).
	self assert: (oc indexOf: 3) = 2.
	self should: [OrderedCollection new removeFirst] raise: CollectionIsEmpty.
	self should: [oc at: 5] raise: SubscriptOutOfBounds
!
testSortedCollection
	| sc |
	sc := SortedCollection new.
	#(5 3 8 1) do: [:x | sc add: x].
	self assert: sc asArray = #(1 3 5 8).
	self assert: sc first = 1.
	self assert: sc last = 8.
	sc add: 4.
	self assert: sc asArray = #(1 3 4 5 8).
	self assert: sc removeFirst = 1.
	self assert: (sc collect: [:x | x * 2]) class == OrderedCollection.
	self assert: (sc select: [:x | x > 4]) class == SortedCollection.
	sc := SortedCollection sortBlock: [:a :b | a > b].
	sc addAll: #(1 5 3).
	self assert: sc asArray = #(5 3 1).
	self assert: sc median = 3.
	self should: [sc addFirst: 1] raise: Error
!
testBag
	| b |
	b := Bag new.
	b add: #a; add: #b; add: #a.
	self assert: b size = 3.
	self assert: (b occurrencesOf: #a) = 2.
	self assert: (b includes: #b).
	b remove: #a.
	self assert: (b occurrencesOf: #a) = 1.
	b add: #c withOccurrences: 3.
	self assert: b size = 5.
	self assert: b asSet size = 3
!
testLinkedList
	| list a b c |
	list := LinkedList new.
	a := Link new.
	b := Link new.
	c := Link new.
	list add: a; add: b; addFirst: c.
	self assert: list size = 3.
	self assert: list first == c.
	self assert: list last == b.
	list remove: a.
	self assert: list size = 2.
	self assert: list removeFirst == c.
	self assert: list removeLast == b.
	self assert: list isEmpty
!
testByteArray
	| b |
	b := ByteArray new: 8.
	b at: 1 put: 255.
	self assert: (b at: 1) = 255.
	self should: [b at: 1 put: 256] raise: Error.
	b uint32At: 1 put: 16r12345678.
	self assert: (b uint32At: 1) = 16r12345678.
	self assert: (b at: 1) = 16r78.
	self assert: (b uint16At: 1) = 16r5678.
	self assert: (b uint16BigEndianAt: 1) = 16r7856.
	b float64At: 1 put: 1.5.
	self assert: (b float64At: 1) = 1.5.
	b float32At: 1 put: 0.25.
	self assert: (b float32At: 1) = 0.25.
	b at: 1 put: 16rFF; at: 2 put: 16rFF.
	self assert: (b int16At: 1) = -1.
	self assert: 'héllo' utf8Encoded utf8Decoded = 'héllo'.
	self assert: 'abc' asByteArray = #[97 98 99].
	self assert: #[97 98] asString = 'ab'
! !
