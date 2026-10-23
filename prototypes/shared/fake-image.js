// Fake class library + process table for UI prototypes. Mirrors the intended layering:
//   Kernel → Graphics-GPU (3D) → Graphics-Canvas (2D) → UI-Windows → UI-Widgets → Tools
// API: FakeImage.packages: [{name, layer, comment, classes: [{name, superclass, ivars, comment, protocols: {proto: {selector: source}}, classSide: {...}}]}]
//      FakeImage.findClass(name), FakeImage.allClasses(), FakeImage.processes (initial process table)
(function (global) {
  'use strict';
  const m = s => s.replace(/^\n/, '').replace(/\n\s*$/, '');

  const packages = [
    {
      name: 'Kernel-Objects', layer: 0,
      comment: 'Root of the class hierarchy and core protocols.',
      classes: [
        {
          name: 'Object', superclass: 'ProtoObject', ivars: [],
          comment: 'I am the root of most classes. I define printing, comparing, copying and reflection.',
          protocols: {
            comparing: {
              '= anObject': m(`
= anObject
	"Answer whether the receiver and anObject represent the same object.
	 Subclasses override for value equality."

	^self == anObject`),
              hash: m(`
hash
	"Identity hash lives in the object header, never derived from the address:
	 the GC is free to move objects at any time."

	^self identityHash`),
            },
            printing: {
              printString: m(`
printString
	"Answer a String whose characters describe the receiver."

	^String new: 16 streamContents: [:stream | self printOn: stream]`),
              'printOn: aStream': m(`
printOn: aStream
	| title |
	title := self class name.
	aStream
		nextPutAll: (title first isVowel ifTrue: ['an '] ifFalse: ['a ']);
		nextPutAll: title`),
            },
            'error handling': {
              'doesNotUnderstand: aMessage': m(`
doesNotUnderstand: aMessage
	"Signal MessageNotUnderstood. The debugger opens on the sender, the
	 method can be written there and the send resumed."

	^(MessageNotUnderstood new)
		message: aMessage;
		receiver: self;
		signal`),
            },
            reflection: {
              inspect: m(`
inspect
	"Open an Inspector on the receiver in its own window process."

	Inspector openOn: self`),
            },
          },
        },
        {
          name: 'BlockClosure', superclass: 'Object', ivars: ['outerContext', 'startpc', 'numArgs'],
          comment: 'I am a closure. My outerContext gives me access to the variables of the method that created me.',
          protocols: {
            evaluating: {
              value: m(`
value
	"Evaluate the receiver with no arguments."

	<primitive: 201>
	^self numArgsError: 0`),
              'on: exceptionClass do: handlerBlock': m(`
on: exceptionClass do: handlerBlock
	"Evaluate the receiver in the scope of an exception handler."

	| handlerActive |
	<primitive: 199>  "marks this context as a handler; never fails"
	handlerActive := true.
	^self value`),
            },
            scheduling: {
              fork: m(`
fork
	"Create and schedule a Process running the code in the receiver."

	^self newProcess resume`),
              'forkNamed: aString': m(`
forkNamed: aString
	^self newProcess
		name: aString;
		resume`),
              newProcess: m(`
newProcess
	"Answer a suspended Process at the active priority."

	^Process
		forContext: [self value. Processor terminateActive] asContext
		priority: Processor activePriority`),
            },
          },
        },
      ],
    },
    {
      name: 'Kernel-Numbers', layer: 0,
      comment: 'Numbers. SmallIntegers and Floats are immediates; LargeIntegers are heap objects.',
      classes: [
        {
          name: 'Integer', superclass: 'Number', ivars: [],
          comment: 'I am the abstract superclass of SmallInteger, LargePositiveInteger and LargeNegativeInteger.',
          protocols: {
            arithmetic: {
              factorial: m(`
factorial
	"Answer the factorial of the receiver."

	self < 0 ifTrue: [^self error: 'Not valid for negative integers'].
	^(1 to: self) inject: 1 into: [:product :each | product * each]`),
              'gcd: anInteger': m(`
gcd: anInteger
	| a b |
	a := self abs.
	b := anInteger abs.
	[b = 0] whileFalse: [| r | r := a \\\\ b. a := b. b := r].
	^a`),
            },
            testing: {
              isPrime: m(`
isPrime
	self < 2 ifTrue: [^false].
	2 to: self sqrtFloor do: [:i | self \\\\ i = 0 ifTrue: [^false]].
	^true`),
            },
          },
        },
        {
          name: 'SmallInteger', superclass: 'Integer', ivars: [],
          comment: 'I am a 61-bit immediate integer. My value lives in the tagged pointer itself.',
          protocols: {
            arithmetic: {
              '+ aNumber': m(`
+ aNumber
	"Primitive. Fails on overflow or non-SmallInteger argument; the fallback
	 code handles LargeIntegers, Fractions and Floats."

	<primitive: 1>
	^super + aNumber`),
              '* aNumber': m(`
* aNumber
	<primitive: 9>
	^super * aNumber`),
            },
          },
        },
      ],
    },
    {
      name: 'Kernel-Processes', layer: 0,
      comment: 'Green threads. All Processes share one OS thread; the VM switches at safepoints (sends, backward jumps).',
      classes: [
        {
          name: 'Process', superclass: 'Link', ivars: ['suspendedContext', 'priority', 'myList', 'name', 'window'],
          comment: 'I am a green thread. Every window runs in its own Process, so a busy window never freezes the others.',
          protocols: {
            changing: {
              resume: m(`
resume
	"Make the receiver runnable."

	<primitive: 87>
	self primitiveFailed`),
              suspend: m(`
suspend
	<primitive: 88>
	self primitiveFailed`),
              terminate: m(`
terminate
	"Unwind ensure: blocks, then remove the receiver from the scheduler."

	self isActiveProcess ifTrue: [^Processor terminateActive].
	suspendedContext ifNotNil: [:ctx | ctx unwindTo: nil].
	self suspend`),
            },
            debugging: {
              debug: m(`
debug
	"Suspend the receiver and open a Debugger on its stack."

	self suspend.
	Debugger openOn: self context: suspendedContext`),
            },
          },
        },
        {
          name: 'ProcessorScheduler', superclass: 'Object', ivars: ['quiescentProcessLists', 'activeProcess'],
          comment: 'I am the scheduler. The single instance is Processor. Preemption happens on timer interrupts at the next safepoint.',
          protocols: {
            'process state change': {
              yield: m(`
yield
	"Give other Processes at the same priority a chance to run."

	<primitive: 167>
	self primitiveFailed`),
            },
            accessing: {
              activeProcess: m(`
activeProcess
	^activeProcess`),
            },
          },
        },
        {
          name: 'Semaphore', superclass: 'LinkedList', ivars: ['excessSignals'],
          comment: 'I synchronize Processes. The VM signals me for external events (vsync, input, I/O).',
          protocols: {
            communication: {
              signal: m(`
signal
	<primitive: 85>
	self primitiveFailed`),
              wait: m(`
wait
	<primitive: 86>
	self primitiveFailed`),
              'critical: aBlock': m(`
critical: aBlock
	self wait.
	^aBlock ensure: [self signal]`),
            },
          },
        },
      ],
    },
    {
      name: 'Graphics-GPU', layer: 1,
      comment: 'LAYER 1 — 3D. Thin WebGPU-shaped API over the platform GPU (Metal/Vulkan/D3D via wgpu). Only Graphics-Canvas talks to me.',
      classes: [
        {
          name: 'GPUDevice', superclass: 'Object', ivars: ['handle', 'queue', 'limits'],
          comment: 'I am a logical GPU device. Buffers and textures I create live outside the moving heap, so the GC never relocates memory the GPU reads.',
          protocols: {
            'creating resources': {
              'createBuffer: size usage: usageFlags': m(`
createBuffer: size usage: usageFlags
	"Answer a GPUBuffer. Its storage is off-heap; the Smalltalk object is a handle."

	^GPUBuffer
		handle: (self primCreateBuffer: size usage: usageFlags)
		size: size
		device: self`),
              'createRenderPipeline: aDescriptor': m(`
createRenderPipeline: aDescriptor
	^GPURenderPipeline
		handle: (self primCreatePipeline: aDescriptor asExternal)
		device: self`),
            },
            submitting: {
              'submit: commandBuffers': m(`
submit: commandBuffers
	<primitive: 'gpuQueueSubmit' module: 'Platform'>
	self primitiveFailed`),
            },
          },
        },
        {
          name: 'GPUCommandEncoder', superclass: 'Object', ivars: ['handle', 'device'],
          comment: 'I record GPU commands into a command buffer.',
          protocols: {
            encoding: {
              'beginRenderPass: aDescriptor': m(`
beginRenderPass: aDescriptor
	^GPURenderPassEncoder on: (self primBeginRenderPass: aDescriptor)`),
              'dispatchWorkgroups: x y: y z: z': m(`
dispatchWorkgroups: x y: y z: z
	<primitive: 'gpuDispatch' module: 'Platform'>
	self primitiveFailed`),
              finish: m(`
finish
	^GPUCommandBuffer handle: self primFinish`),
            },
          },
        },
        {
          name: 'GPUBuffer', superclass: 'Object', ivars: ['handle', 'size', 'device'],
          comment: 'I am an off-heap GPU buffer.',
          protocols: {
            writing: {
              'write: aByteArray at: offset': m(`
write: aByteArray at: offset
	<primitive: 'gpuQueueWriteBuffer' module: 'Platform'>
	self primitiveFailed`),
            },
          },
        },
      ],
    },
    {
      name: 'Graphics-Canvas', layer: 2,
      comment: 'LAYER 2 — 2D. Vector paths, text, images. Records DisplayLists and rasterizes them with compute shaders via Graphics-GPU.',
      classes: [
        {
          name: 'Canvas', superclass: 'Object', ivars: ['displayList', 'transform', 'clip'],
          comment: 'I am what widgets draw on. I never touch the GPU directly; I append to an immutable DisplayList.',
          protocols: {
            drawing: {
              'fillRect: aRectangle color: aColor': m(`
fillRect: aRectangle color: aColor
	displayList add: (FillOp
		path: (Path rect: aRectangle)
		paint: aColor
		transform: transform)`),
              'fillPath: aPath paint: aPaint': m(`
fillPath: aPath paint: aPaint
	displayList add: (FillOp path: aPath paint: aPaint transform: transform)`),
              'drawString: aString at: aPoint font: aFont color: aColor': m(`
drawString: aString at: aPoint font: aFont color: aColor
	"Glyphs come from a shared MSDF atlas; text stays crisp at any zoom."

	displayList add: (GlyphRunOp
		glyphs: (aFont shape: aString)
		origin: aPoint
		color: aColor
		transform: transform)`),
            },
            transforming: {
              'transformBy: aMatrix during: aBlock': m(`
transformBy: aMatrix during: aBlock
	| saved |
	saved := transform.
	transform := transform * aMatrix.
	^aBlock ensure: [transform := saved]`),
            },
          },
        },
        {
          name: 'DisplayList', superclass: 'Object', ivars: ['ops', 'bounds', 'frozen'],
          comment: 'I am a recorded frame of drawing ops. Once frozen I am deeply immutable and can be handed to the compositor without copying.',
          protocols: {
            freezing: {
              freeze: m(`
freeze
	ops := ops asArray beImmutable.
	frozen := true`),
            },
          },
        },
        {
          name: 'VectorRasterizer', superclass: 'Object', ivars: ['device', 'pipelines', 'atlas'],
          comment: 'I turn DisplayLists into pixels: flatten → bin into tiles → coarse → fine, all as compute passes.',
          protocols: {
            rendering: {
              'render: aDisplayList into: aTexture': m(`
render: aDisplayList into: aTexture
	| encoder |
	encoder := device createCommandEncoder.
	self
		encodeFlatten: aDisplayList on: encoder;
		encodeBinning: encoder;
		encodeCoarse: encoder;
		encodeFine: encoder target: aTexture.
	device submit: {encoder finish}`),
            },
          },
        },
      ],
    },
    {
      name: 'UI-Windows', layer: 3,
      comment: 'LAYER 3 — windows and compositing. Each Window owns a Process and a layer texture.',
      classes: [
        {
          name: 'Compositor', superclass: 'Object', ivars: ['layers', 'rasterizer', 'vsync'],
          comment: 'I run at high priority, woken by the vsync Semaphore. I composite the latest frozen DisplayList of every window, so dragging and animation stay smooth even while a window is busy.',
          protocols: {
            running: {
              run: m(`
run
	[vsync wait.
	 self composeFrame] repeat`),
              composeFrame: m(`
composeFrame
	layers do: [:layer |
		layer isDirty ifTrue: [
			rasterizer render: layer latestDisplayList into: layer texture]].
	rasterizer composite: layers to: Display swapchain nextTexture`),
            },
          },
        },
        {
          name: 'Window', superclass: 'Object', ivars: ['title', 'bounds', 'content', 'process', 'eventQueue', 'layer'],
          comment: 'I am a top-level window. I own a Process that handles my events and redraws my content.',
          protocols: {
            opening: {
              open: m(`
open
	process := [self eventLoop] forkNamed: title.
	Compositor default addLayer: layer`),
            },
            'event loop': {
              eventLoop: m(`
eventLoop
	[| event |
	 event := eventQueue next.
	 content handleEvent: event.
	 self needsRedraw ifTrue: [self redraw]] repeat`),
              redraw: m(`
redraw
	| canvas |
	canvas := Canvas extent: bounds extent.
	content drawOn: canvas.
	layer publish: canvas displayList freeze`),
            },
          },
        },
      ],
    },
    {
      name: 'UI-Widgets', layer: 4,
      comment: 'LAYER 4 — what normal UI code uses. Widgets draw on a Canvas; they never see the GPU.',
      classes: [
        {
          name: 'Widget', superclass: 'Object', ivars: ['bounds', 'owner', 'submorphs', 'layout'],
          comment: 'I am the base of all UI objects. Like Morphic: everything visible is a live object you can grab and inspect.',
          protocols: {
            drawing: {
              'drawOn: aCanvas': m(`
drawOn: aCanvas
	self drawSelfOn: aCanvas.
	submorphs do: [:each | each drawOn: aCanvas]`),
            },
            events: {
              'handleEvent: anEvent': m(`
handleEvent: anEvent
	^(submorphs reverse detect: [:each | each containsPoint: anEvent position] ifNone: [nil])
		ifNil: [anEvent sentTo: self]
		ifNotNil: [:child | child handleEvent: anEvent]`),
            },
          },
        },
        {
          name: 'Button', superclass: 'Widget', ivars: ['label', 'action'],
          comment: 'I am a push button.',
          protocols: {
            drawing: {
              'drawSelfOn: aCanvas': m(`
drawSelfOn: aCanvas
	aCanvas
		fillRoundRect: bounds radius: 6 color: self theme buttonColor;
		drawString: label centeredIn: bounds font: self theme font color: self theme textColor`),
            },
            events: {
              'mouseUp: anEvent': m(`
mouseUp: anEvent
	action value`),
            },
          },
        },
        {
          name: 'TextEditor', superclass: 'Widget', ivars: ['text', 'selection', 'undo'],
          comment: 'I edit text. Every TextEditor can evaluate its selection: do it, print it, inspect it.',
          protocols: {
            'do it': {
              printIt: m(`
printIt
	| result |
	result := Compiler evaluate: self selectedText for: self doItReceiver.
	self insertAfterSelection: ' ', result printString`),
              doIt: m(`
doIt
	^Compiler evaluate: self selectedText for: self doItReceiver`),
            },
          },
        },
      ],
    },
    {
      name: 'Tools', layer: 5,
      comment: 'Development tools, built from UI-Widgets like any other application.',
      classes: [
        {
          name: 'Browser', superclass: 'Widget', ivars: ['package', 'class', 'protocol', 'selector'],
          comment: 'I am the system browser: packages, classes, protocols, methods.',
          protocols: {
            accepting: {
              'accept: aString': m(`
accept: aString
	"Compile aString into the selected class. Running processes pick up the
	 new method on their next send."

	class compile: aString classified: protocol`),
            },
          },
        },
        {
          name: 'Workspace', superclass: 'Widget', ivars: ['editor', 'bindings'],
          comment: 'I am a scratchpad for evaluating code. My variables persist between evaluations.',
          protocols: {},
        },
        {
          name: 'ProcessBrowser', superclass: 'Widget', ivars: ['processes', 'selected'],
          comment: 'I list all green threads with their priority and state.',
          protocols: {
            actions: {
              debugSelected: m(`
debugSelected
	selected debug`),
            },
          },
        },
      ],
    },
  ];

  const processes = [
    { name: 'timer interrupt watcher', priority: 80, state: 'waiting', window: null },
    { name: 'compositor (vsync)', priority: 70, state: 'waiting', window: null },
    { name: 'input dispatcher', priority: 60, state: 'waiting', window: null },
    { name: 'finalization', priority: 50, state: 'waiting', window: null },
    { name: 'Browser', priority: 40, state: 'waiting', window: 'browser' },
    { name: 'Workspace', priority: 40, state: 'running', window: 'workspace' },
    { name: 'Transcript', priority: 40, state: 'waiting', window: 'transcript' },
    { name: 'idle', priority: 10, state: 'ready', window: null },
  ];

  const allClasses = () => packages.flatMap(p => p.classes.map(c => ({ ...c, package: p.name })));
  const findClass = name => allClasses().find(c => c.name === name) || null;

  global.FakeImage = { packages, processes, allClasses, findClass };
})(typeof window !== 'undefined' ? window : globalThis);
