Magnitude subclass: #Date
	instanceVariableNames: 'year month day'
	classVariableNames: ''
	package: 'System-Support'!

Date comment: 'I am a calendar date (proleptic Gregorian). Date today is the current UTC date.'!

!Date methodsFor: 'accessing'!
year
	^year
!
month
	^month
!
monthIndex
	^month
!
day
	^day
!
dayOfMonth
	^day
!
dayOfWeek
	"Answer 1 (Sunday) to 7 (Saturday)."
	^self daysSinceEpoch + 4 \\ 7 + 1
!
dayOfWeekName
	^#('Sunday' 'Monday' 'Tuesday' 'Wednesday' 'Thursday' 'Friday' 'Saturday') at: self dayOfWeek
!
monthName
	^#('January' 'February' 'March' 'April' 'May' 'June' 'July' 'August' 'September' 'October' 'November' 'December') at: month
!
daysInMonth
	^self class daysInMonth: month forYear: year
!
isLeapYear
	^self class isLeapYear: year
!
daysSinceEpoch
	"Answer the days since 1970-01-01 (negative before)."
	| y m era yoe doy doe |
	y := month <= 2 ifTrue: [year - 1] ifFalse: [year].
	m := month.
	era := y // 400.
	yoe := y - (era * 400).
	doy := (153 * (m > 2 ifTrue: [m - 3] ifFalse: [m + 9]) + 2) // 5 + day - 1.
	doe := yoe * 365 + (yoe // 4) - (yoe // 100) + doy.
	^era * 146097 + doe - 719468
!
setYear: y month: m day: d
	year := y.
	month := m.
	day := d
! !

!Date methodsFor: 'arithmetic'!
addDays: n
	^self class fromDays: self daysSinceEpoch + n
!
subtractDays: n
	^self addDays: n negated
!
subtractDate: aDate
	"Answer the days between aDate and the receiver."
	^self daysSinceEpoch - aDate daysSinceEpoch
! !

!Date methodsFor: 'comparing'!
< aDate
	^self daysSinceEpoch < aDate daysSinceEpoch
!
= aDate
	^self class == aDate class and: [year = aDate year and: [month = aDate month and: [day = aDate day]]]
!
hash
	^self daysSinceEpoch hash
! !

!Date methodsFor: 'printing'!
printOn: aStream
	"Print in ISO 8601 form: 2026-10-22."
	aStream
		nextPutAll: (year printPaddedWith: $0 to: 4); nextPut: $-;
		nextPutAll: (month printPaddedWith: $0 to: 2); nextPut: $-;
		nextPutAll: (day printPaddedWith: $0 to: 2)
! !

!Date class methodsFor: 'instance creation'!
today
	"Answer the current UTC date."
	^self fromDays: Time utcMicroseconds // 86400000000
!
year: y month: m day: d
	^self basicNew setYear: y month: m day: d
!
fromDays: daysSinceEpoch
	"Answer the date daysSinceEpoch days after 1970-01-01 (civil-from-days algorithm)."
	| z era doe yoe y doy mp d m |
	z := daysSinceEpoch + 719468.
	era := z // 146097.
	doe := z - (era * 146097).
	yoe := doe - (doe // 1460) + (doe // 36524) - (doe // 146096) // 365.
	y := yoe + (era * 400).
	doy := doe - (365 * yoe + (yoe // 4) - (yoe // 100)).
	mp := 5 * doy + 2 // 153.
	d := doy - (153 * mp + 2 // 5) + 1.
	m := mp < 10 ifTrue: [mp + 3] ifFalse: [mp - 9].
	^self year: (m <= 2 ifTrue: [y + 1] ifFalse: [y]) month: m day: d
! !

!Date class methodsFor: 'calendar'!
isLeapYear: y
	^(y \\ 4 = 0 and: [y \\ 100 ~= 0]) or: [y \\ 400 = 0]
!
daysInMonth: m forYear: y
	m = 2 ifTrue: [^(self isLeapYear: y) ifTrue: [29] ifFalse: [28]].
	^#(31 28 31 30 31 30 31 31 30 31 30 31) at: m
! !
