" The Computer Language Benchmarks Game
  http://benchmarksgame.alioth.debian.org/

  contributed by Mark C. Lewis
  modified slightly by Chad Whipkey
  
  Based on nbody.java ported to SOM by Stefan Marr.
  See LICENSE.md file.
"!

" The Computer Language Benchmarks Game
  http://shootout.alioth.debian.org/

  contributed by Mark C. Lewis
  modified slightly by Chad Whipkey
  
  Based on nbody.java ported to SOM by Stefan Marr.
  See LICENSE.md file.
"!

" The Computer Language Benchmarks Game
  http://shootout.alioth.debian.org/

  contributed by Mark C. Lewis
  modified slightly by Chad Whipkey

  Based on nbody.java ported to SOM by Stefan Marr.
  See LICENSE.md file.
"!

Object subclass: #Body
	instanceVariableNames: 'x y z vx vy vz mass'
	classVariableNames: 'solarMass'
	package: 'AWFY'!

Benchmark subclass: #NBody
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #NBodySystem
	instanceVariableNames: 'bodies'
	classVariableNames: ''
	package: 'AWFY'!

!Body methodsFor: 'benchmarking'!
initX: anX y: aY z: aZ vx: aVX vy: aVY vz: aVZ mass: aMass
	x := anX.
	y := aY.
	z := aZ.
	vx := aVX * Body DaysPerYear.
	vy := aVY * Body DaysPerYear.
	vz := aVZ * Body DaysPerYear.
	mass := aMass * Body SolarMass.
!
x
	^ x
!
y
	^ y
!
z
	^ z
!
vx
	^ vx
!
vy
	^ vy
!
vz
	^ vz
!
mass
	^ mass
!
x: val
	x := val
!
y: val
	y := val
!
z: val
	z := val
!
vx: val
	vx := val
!
vy: val
	vy := val
!
vz: val
	vz := val
!
mass: val
	mass := val
!
offsetMomentumX: px y: py z: pz
	vx := 0.0 - (px / Body SolarMass).
	vy := 0.0 - (py / Body SolarMass).
	vz := 0.0 - (pz / Body SolarMass).
!
print
	'x:  ' print. x println.
	'y:  ' print. y println.
	'z:  ' print. z println.

	'vx: ' print. vx println.
	'vy: ' print. vy println.
	'vz: ' print. vz println.

	'mass: ' print. mass println.
! !

!Body class methodsFor: 'benchmarking'!
Pi
	^ 3.141592653589793
!
SolarMass
	^ solarMass
!
DaysPerYear
	^ 365.24
!
initialize
	solarMass := 4 * self Pi * self Pi.
!
jupiter
	^ super new
	    initX:    4.8414314424647209
	        y:   -1.16032004402742839
	        z:   -0.103622044471123109
	        vx:   0.00166007664274403694
	        vy:   0.00769901118419740425
	        vz:  -0.0000690460016972063023
	        mass: 0.000954791938424326609
!
saturn
	^ super new
	    initX:    8.34336671824457987
	        y:    4.12479856412430479
	        z:   -0.403523417114321381
	        vx:  -0.00276742510726862411
	        vy:   0.00499852801234917238
	        vz:   0.0000230417297573763929
	        mass: 0.000285885980666130812
!
uranus
	^ super new
	    initX:   12.894369562139131
	        y:  -15.1111514016986312
	        z:   -0.223307578892655734
	        vx:   0.00296460137564761618
	        vy:   0.0023784717395948095
	        vz:  -0.0000296589568540237556
	        mass: 0.0000436624404335156298
!
neptune
	^ super new
	    initX:   15.3796971148509165
	        y:  -25.9193146099879641
	        z:    0.179258772950371181
	        vx:   0.00268067772490389322
	        vy:   0.00162824170038242295
	        vz:  -0.000095159225451971587
	        mass: 0.0000515138902046611451
!
sun
	^ super new initX: 0.0 y: 0.0 z: 0.0 vx: 0.0 vy: 0.0 vz: 0.0 mass: 1.0
! !

!NBody methodsFor: 'benchmarking'!
innerBenchmarkLoop: innerIterations
	| system |
	system := NBodySystem new.

	1 to: innerIterations do: [:i |
	  system advance: 0.01.
	].

	^ self verify: system energy for: innerIterations.
!
verify: result for: innerIterations
	innerIterations = 250000 ifTrue: [ ^ result = -0.1690859889909308  ].
	innerIterations =      1 ifTrue: [ ^ result = -0.16907495402506745 ].

	('No verification result for ', innerIterations asString, ' found') println.
	('Result is: ', result asString) println.
	^ false
! !

!NBody class methodsFor: 'benchmarking'!
new
	Body initialize.
	  ^ super new
! !

!NBodySystem methodsFor: 'benchmarking'!
initialize
	bodies := self createBodies
!
createBodies
	| px py pz bodies |

	bodies := Array new: 5.
	bodies at: 1 put: Body sun.
	bodies at: 2 put: Body jupiter.
	bodies at: 3 put: Body saturn.
	bodies at: 4 put: Body uranus.
	bodies at: 5 put: Body neptune.

	"bodies do: [:b | b print. '' println ]."

	px := 0.0.  py := 0.0.  pz := 0.0.

	bodies do: [:b |
	    px := px + (b vx * b mass).
	    py := py + (b vy * b mass).
	    pz := pz + (b vz * b mass).
	].

	(bodies at: 1) offsetMomentumX: px y: py z: pz.

	"bodies do: [:b | b print. '' println ]."
	^ bodies
!
advance: dt
	1 to: bodies size do: [:i |
	  | iBody |
	  iBody := bodies at: i.

	  i + 1 to: bodies size do: [:j |
	    | dx dy dz jBody dSquared distance mag |
	    jBody := bodies at: j.
	    dx := iBody x - jBody x.
	    dy := iBody y - jBody y.
	    dz := iBody z - jBody z.

	    dSquared := (dx * dx) + (dy * dy) + (dz * dz).
	    distance := dSquared sqrt.
	    mag      := dt / (dSquared * distance).

	    iBody vx: iBody vx - (dx * jBody mass * mag).
	    iBody vy: iBody vy - (dy * jBody mass * mag).
	    iBody vz: iBody vz - (dz * jBody mass * mag).

	    jBody vx: jBody vx + (dx * iBody mass * mag).
	    jBody vy: jBody vy + (dy * iBody mass * mag).
	    jBody vz: jBody vz + (dz * iBody mass * mag).
	  ].
	].

	bodies do: [:body |
	   body x: body x + (dt * body vx).
	   body y: body y + (dt * body vy).
	   body z: body z + (dt * body vz).
	].
!
energy
	| e |
	e := 0.0.

	1 to: bodies size do: [:i |
	  | iBody |
	  iBody := bodies at: i.

	  e := e + (0.5 * iBody mass *
	       ((iBody vx * iBody vx) +
	        (iBody vy * iBody vy) +
	        (iBody vz * iBody vz))).

	  i + 1 to: bodies size do: [:j |
	      | jBody dx dy dz distance |
	      jBody := bodies at: j.

	      dx := iBody x - jBody x.
	      dy := iBody y - jBody y.
	      dz := iBody z - jBody z.

	      distance := ((dx*dx) + (dy*dy) + (dz*dz)) sqrt.
	      e := e - ((iBody mass * jBody mass) / distance).
	  ].
	].
	^ e
! !

!NBodySystem class methodsFor: 'benchmarking'!
new
	^ super new initialize
! !

