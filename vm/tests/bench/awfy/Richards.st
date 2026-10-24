"
This benchmark is derived from richards.st, which is
part of Mario Wolczko's DeltaBlue and Richards collection.

License details:
  http://web.archive.org/web/20050825101121/http://www.sunlabs.com/people/mario/java_benchmarking/index.html
"!

Object subclass: #RBObject
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RBObject subclass: #DeviceTaskDataRecord
	instanceVariableNames: 'pending'
	classVariableNames: ''
	package: 'AWFY'!

RBObject subclass: #HandlerTaskDataRecord
	instanceVariableNames: 'workIn deviceIn'
	classVariableNames: ''
	package: 'AWFY'!

RBObject subclass: #IdleTaskDataRecord
	instanceVariableNames: 'control count'
	classVariableNames: ''
	package: 'AWFY'!

RBObject subclass: #Packet
	instanceVariableNames: 'link identity kind datum data'
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #Richards
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

RBObject subclass: #RBScheduler
	instanceVariableNames: 'taskList currentTask currentTaskIdentity taskTable tracing layout queuePacketCount holdCount'
	classVariableNames: ''
	package: 'AWFY'!

RBObject subclass: #TaskState
	instanceVariableNames: 'packetPending taskWaiting taskHolding'
	classVariableNames: ''
	package: 'AWFY'!

TaskState subclass: #TaskControlBlock
	instanceVariableNames: 'link identity priority input function handle'
	classVariableNames: ''
	package: 'AWFY'!

RBObject subclass: #WorkerTaskDataRecord
	instanceVariableNames: 'destination count'
	classVariableNames: ''
	package: 'AWFY'!

!RBObject methodsFor: 'benchmarking'!
append: packet head: queueHead
	| mouse link |
	packet link: RBObject NoWork.
	RBObject NoWork == queueHead ifTrue: [ ^ packet ].
	mouse := queueHead.
	[RBObject NoWork == (link := mouse link)]
	        whileFalse: [mouse := link].
	mouse link: packet.
	^ queueHead
! !

!RBObject class methodsFor: 'benchmarking'!
NoTask
	^ nil
!
Idler
	^ 1
!
NoWork
	^ nil
!
Worker
	^ 2
!
WorkPacketKind
	^ 2
!
HandlerA
	^ 3
!
HandlerB
	^ 4
!
DeviceA
	^ 5
!
DeviceB
	^ 6
!
DevicePacketKind
	^ 1
! !

!DeviceTaskDataRecord methodsFor: 'benchmarking'!
pending
	^ pending
!
pending: packet
	pending := packet
!
create
	pending := RBObject NoWork
! !

!DeviceTaskDataRecord class methodsFor: 'benchmarking'!
create
	^ super new create
! !

!HandlerTaskDataRecord methodsFor: 'benchmarking'!
deviceIn
	^ deviceIn
!
deviceIn: aPacket
	deviceIn := aPacket
!
deviceInAdd: packet
	deviceIn := self append: packet head: deviceIn
!
workIn
	^ workIn
!
workIn: aWorkQueue
	workIn := aWorkQueue
!
workInAdd: packet
	workIn := self append: packet head: workIn
!
create
	workIn := deviceIn := RBObject NoWork
!
asString
	^ 'HandlerTaskDataRecord(', workIn asString, ', ', deviceIn asString, ')'
! !

!HandlerTaskDataRecord class methodsFor: 'benchmarking'!
create
	^ super new create
! !

!IdleTaskDataRecord methodsFor: 'benchmarking'!
control
	^ control
!
control: aNumber
	control := aNumber
!
count
	^ count
!
count: aCount
	count := aCount
!
create
	control := 1.
	count := 10000
! !

!IdleTaskDataRecord class methodsFor: 'benchmarking'!
create
	^ super new create
! !

!Packet methodsFor: 'benchmarking'!
data
	^ data
!
datum
	^ datum
!
datum: someData
	datum := someData
!
identity
	^ identity
!
identity: anIdentity
	identity := anIdentity
!
kind
	^ kind
!
link
	^ link
!
link: aWorkQueue
	link := aWorkQueue
!
link: aLink identity: anIdentity kind: aKind
	link := aLink.
	kind := aKind.
	identity := anIdentity.
	datum := 1.
	data  := Array new: 4 withAll: 0
!
asString
	^ 'Packet(',
	    link asString, ', ',
	    identity asString, ', ',
	    kind asString, ', ',
	    datum asString, ', ',
	    data asString,
	  ')'
! !

!Packet class methodsFor: 'benchmarking'!
create: link identity: identity kind: kind
	^ super new
	    link: link
	    identity: identity
	    kind: kind
! !

!Richards methodsFor: 'benchmarking'!
benchmark
	^ RBScheduler new start.
!
verifyResult: result
	^ result
! !

!RBScheduler methodsFor: 'benchmarking'!
initialize
	taskList    := RBObject NoTask.
	currentTask := RBObject NoTask.
	currentTaskIdentity := 0.
	taskTable   := Array new: 6 withAll: RBObject NoTask.
	layout      := 0.
	queuePacketCount := 0.
	holdCount   := 0.
!
tracing
	^ false
!
createDevice: identity priority: priority work: work state: state
	| data |
	data := DeviceTaskDataRecord create.
	self
	  createTask: identity
	  priority: priority
	  work: work
	  state: state
	  function:
	    [:thework :word |
	    | thedata functionWork |
	    thedata := word.
	    functionWork := thework.
	    RBObject NoWork == functionWork ifTrue: [
	      RBObject NoWork == (functionWork := thedata pending)
	        ifTrue: [ self wait ]
	        ifFalse: [
	          thedata pending: RBObject NoWork.
	          self queuePacket: functionWork]]
	      ifFalse: [
	        thedata pending: functionWork.
	        self tracing ifTrue: [
	          self trace: functionWork datum].
	        self holdSelf]]
	  data: data
!
createHandler: identity priority: priority work: work state: state
	| data |
	data := HandlerTaskDataRecord create.
	self createTask: identity
	     priority:   priority
	     work:       work
	     state:      state
	     function:   [:thework :word |
	       | thedata workPacket |
	       thedata := word.
	       RBObject NoWork == thework ifFalse: [
	         RBObject WorkPacketKind == thework kind
	           ifTrue:  [ thedata workInAdd: thework ]
	           ifFalse: [ thedata deviceInAdd: thework ]].

	       RBObject NoWork == (workPacket := thedata workIn)
	         ifTrue: [ self wait ]
	         ifFalse: [
	           | count |
	           count := workPacket datum.
	           count > 4
	             ifTrue: [
	               thedata workIn: workPacket link.
	               self queuePacket: workPacket]
	             ifFalse: [
	               | devicePacket |
	               RBObject NoWork == (devicePacket := thedata deviceIn)
	                 ifTrue: [ self wait ]
	                 ifFalse: [
	                   thedata deviceIn: devicePacket link.
	                   devicePacket datum: (workPacket data at: count).
	                   workPacket datum: count + 1.
	                   self queuePacket: devicePacket]]]]
	     data: data
!
createIdler: identity priority: priority work: work state: state
	| data |
	data := IdleTaskDataRecord create.
	self createTask: identity
	     priority:   priority
	     work:       work
	     state:      state
	     function:  [:thework :word |
	       | thedata |
	       thedata := word.
	       thedata count: thedata count - 1.
	       0 = thedata count
	         ifTrue:  [ self holdSelf ]
	         ifFalse: [
	           0 = (thedata control & 1 )
	           ifTrue: [
	             thedata control: thedata control // 2.
	             self release: RBObject DeviceA]
	           ifFalse: [
	             thedata control: (thedata control // 2 bitXor: 53256).
	             self release: RBObject DeviceB]]]
	     data: data
!
createPacket: link identity: identity kind: kind
	^ Packet create:   link
	         identity: identity
	         kind:     kind
!
createTask: identity priority: priority work: work state: state function: aBlock data: data
	| t |
	t := TaskControlBlock   link:             taskList
	                        create:           identity
	                        priority:         priority
	                        initialWorkQueue: work
	                        initialState:     state
	                        function:         aBlock
	                        privateData:      data.
	taskList := t.
	taskTable at: identity put: t
!
createWorker: identity priority: priority work: work state: state
	| data |
	data := WorkerTaskDataRecord create.
	self createTask: identity
	     priority:   priority
	     work:       work
	     state:      state
	     function: [:thework :word |
	       | thedata |
	       thedata := word.
	       RBObject NoWork == thework
	         ifTrue: [ self wait ]
	         ifFalse: [
	           thedata destination: (RBObject HandlerA = thedata destination
	                                 ifTrue:  [RBObject HandlerB]
	                                 ifFalse: [RBObject HandlerA]).
	           thework identity: thedata destination.
	           thework datum: 1.
	           1 to: 4 do: [:i |
	             thedata count: thedata count + 1.
	             thedata count > 26 ifTrue: [thedata count: 1].
	             "thework data at: i put: $A asInteger + thedata count - 1]."
	             thework data at: i put: 65 + thedata count - 1].
	           self queuePacket: thework]]
	    data: data
!
start
	| workQ |
	self
	        createIdler: RBObject Idler
	        priority: 0
	        work: RBObject NoWork
	        state: TaskState running.
	workQ := self
	                        createPacket: RBObject NoWork
	                        identity: RBObject Worker
	                        kind: RBObject WorkPacketKind.
	workQ := self
	                        createPacket: workQ
	                        identity: RBObject Worker
	                        kind: RBObject WorkPacketKind.
	self
	        createWorker: RBObject Worker
	        priority: 1000
	        work: workQ
	        state: TaskState waitingWithPacket.
	workQ := self
	                        createPacket: RBObject NoWork
	                        identity: RBObject DeviceA
	                        kind: RBObject DevicePacketKind.
	workQ := self
	                        createPacket: workQ
	                        identity: RBObject DeviceA
	                        kind: RBObject DevicePacketKind.
	workQ := self
	                        createPacket: workQ
	                        identity: RBObject DeviceA
	                        kind: RBObject DevicePacketKind.
	self
	        createHandler: RBObject HandlerA
	        priority: 2000
	        work: workQ
	        state: TaskState waitingWithPacket.
	workQ := self
	                        createPacket: RBObject NoWork
	                        identity: RBObject DeviceB
	                        kind: RBObject DevicePacketKind.
	workQ := self
	                        createPacket: workQ
	                        identity: RBObject DeviceB
	                        kind: RBObject DevicePacketKind.
	workQ := self
	                        createPacket: workQ
	                        identity: RBObject DeviceB
	                        kind: RBObject DevicePacketKind.
	self
	        createHandler: RBObject HandlerB
	        priority: 3000
	        work: workQ
	        state: TaskState waitingWithPacket.
	self
	        createDevice: RBObject DeviceA
	        priority: 4000
	        work: RBObject NoWork
	        state: TaskState waiting.
	self
	        createDevice: RBObject DeviceB
	        priority: 5000
	        work: RBObject NoWork
	        state: TaskState waiting.

	self schedule.

	^ queuePacketCount = 23246 and: holdCount = 9297
!
findTask: identity
	| t |
	t := taskTable at: identity.
	RBObject NoTask == t ifTrue: [self error: 'findTask failed'].
	^ t
!
holdSelf
	holdCount := holdCount + 1.
	currentTask taskHolding: true.
	^ currentTask link
!
queuePacket: packet
	| t |
	t := self findTask: packet identity.
	RBObject NoTask == t ifTrue: [ ^ RBObject NoTask ].
	queuePacketCount := queuePacketCount + 1.
	packet link: RBObject NoWork.
	packet identity: currentTaskIdentity.
	^ t addInput: packet checkPriority: currentTask
!
release: identity
	| t |
	t := self findTask: identity.
	RBObject NoTask == t ifTrue: [ ^ RBObject NoTask ].
	t taskHolding: false.
	t priority > currentTask priority
	  ifTrue:  [ ^ t ]
	  ifFalse: [ ^ currentTask ]
!
trace: id
	layout := layout - 1.
	0 >= layout ifTrue: [
	  '' println.
	  layout := 50 ].
	id print
!
wait
	currentTask taskWaiting: true.
	^currentTask
!
schedule
	currentTask := taskList.
	[ RBObject NoTask == currentTask ] whileFalse: [
	  currentTask isTaskHoldingOrWaiting
	    ifTrue:  [ currentTask := currentTask link ]
	    ifFalse: [
	      currentTaskIdentity := currentTask identity.
	      self tracing ifTrue: [ self trace: currentTaskIdentity ].
	      currentTask := currentTask runTask ] ]
! !

!RBScheduler class methodsFor: 'benchmarking'!
new
	^ super new initialize
! !

!TaskState methodsFor: 'benchmarking'!
isPacketPending
	^ packetPending
!
isTaskHolding
	^ taskHolding
!
isTaskWaiting
	^ taskWaiting
!
taskHolding: aBoolean
	taskHolding   := aBoolean
!
taskWaiting: aBoolean
	taskWaiting   := aBoolean
!
packetPending: aBoolean
	packetPending := aBoolean
!
packetPending
	packetPending := true.
	taskWaiting := false.
	taskHolding := false
!
running
	packetPending := taskWaiting := taskHolding := false
!
waiting
	packetPending := taskHolding := false.
	taskWaiting := true
!
waitingWithPacket
	taskHolding := false.
	taskWaiting := packetPending := true
!
isTaskHoldingOrWaiting
	^ taskHolding or: [packetPending not and: [taskWaiting]]
!
isWaitingWithPacket
	^ packetPending and: [taskWaiting and: [taskHolding not]]
! !

!TaskState class methodsFor: 'benchmarking'!
running
	^ super new running
!
waiting
	^ super new waiting
!
waitingWithPacket
	^ super new waitingWithPacket
! !

!TaskControlBlock methodsFor: 'benchmarking'!
identity
	^ identity
!
link
	^ link
!
priority
	^ priority
!
link: aLink identity: anIdentity priority: aPriority initialWorkQueue: anInitialWorkQueue initialState: anInitialState function: aBlock privateData: aPrivateData
	link     := aLink.
	identity := anIdentity.
	function := aBlock.
	priority := aPriority.
	input    := anInitialWorkQueue.
	handle   := aPrivateData.
	self packetPending: anInitialState isPacketPending.
	self taskWaiting: anInitialState isTaskWaiting.
	self taskHolding: anInitialState isTaskHolding.
!
addInput: packet checkPriority: oldTask
	RBObject NoWork == input
	  ifTrue: [
	    input := packet.
	    self packetPending: true.
	    priority > oldTask priority ifTrue: [ ^ self ] ]
	  ifFalse: [
	    input := self append: packet head: input ].
	^ oldTask
!
runTask
	| message |
	self isWaitingWithPacket
	  ifTrue: [
	    message := input.
	    input := message link.
	    RBObject NoWork == input
	      ifTrue: [self running]
	      ifFalse: [self packetPending]]
	  ifFalse: [message := RBObject NoWork].
	^ function value: message value: handle
! !

!TaskControlBlock class methodsFor: 'benchmarking'!
link: link create: identity priority: priority initialWorkQueue: initialWorkQueue initialState: initialState function: aBlock privateData: privateData
	^super new
	        link: link
	        identity: identity
	        priority: priority
	        initialWorkQueue: initialWorkQueue
	        initialState: initialState
	        function: aBlock
	        privateData: privateData
! !

!WorkerTaskDataRecord methodsFor: 'benchmarking'!
count
	^ count
!
count: aCount
	count := aCount
!
destination
	^ destination
!
destination: aHandler
	destination := aHandler
!
create
	destination := RBObject HandlerA.
	count := 0
! !

!WorkerTaskDataRecord class methodsFor: 'benchmarking'!
create
	^ super new create
! !

