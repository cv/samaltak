!ProfilerView methodsFor: '*Tools-Agent'!
agentContext
	"The profile data shown as self; the selected range ({start. end} µs), frame bar, picked frame (or Process) and the Process filtered on."
	^AgentContext new
		label: self window title;
		receiver: data;
		bind: #range to: selection;
		bind: #bar to: selectedBar;
		bind: #picked to: picked;
		bind: #process to: (filter == #all ifFalse: [filter]);
		yourself
! !
