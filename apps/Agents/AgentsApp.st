Application subclass: #AgentsApp
	instanceVariableNames: 'card process wakeup collected collector collectNow'
	classVariableNames: ''
	package: 'Agents'!

AgentsApp comment: 'I am the Omarchy desktop''s agents card as a window of its own: an AgentsCard of the records omarchy-agent-usage-update keeps in ~/.local/state/omarchy/agents/usage, read again every minute (the times to reset count down), less the agents the card''s settings hide (~/.config/omarchy/desktop-cards.json, card "agents": {"settings": {"hide": ["kimi"]}}). The window''s height follows the agents shown.

	bin/samaltak run apps/Agents
	AgentsApp run

Without omarchy-agent-usage-update (macOS) the limits come from AgentCollector instead, every 5 minutes.

A click opens the bar''s Agents panel (omarchy-shell), a middle click asks the collectors for fresh limits (omarchy-agent-usage-update --limits-only, or AgentCollector) and reads the records again.'!

!AgentsApp methodsFor: 'accessing'!
title
	^'Agents'
!
card
	^card
!
content
	card isNil ifTrue: [
		card := AgentsCard new.
		card onActivate: [Omarchy togglePanel: 'omarchy.agents'].
		card onRefresh: [self update]].
	^card
!
backgroundColor
	^self content background
! !

!AgentsApp methodsFor: 'records'!
hidden
	| hide |
	hide := (Omarchy cardSettings: 'agents') at: 'hide' ifAbsent: [#()].
	^(hide isKindOf: Array) ifTrue: [hide] ifFalse: [#()]
!
readUsages
	collected isNil ifFalse: [^AgentUsage shown: collected hiding: self hidden].
	^AgentUsage recordsIn: AgentUsage directory hiding: self hidden
!
collectsItself
	"Whether Omarchy's collectors are missing, so that AgentCollector stands in for them."
	^(OSProcess run: 'command -v omarchy-agent-usage-update >/dev/null') exitCode ~= 0
!
now
	^Time utcMicroseconds / 1.0e6
!
reload
	"Read the records again and show them (any Process)."
	| usages t |
	usages := self readUsages.
	t := self now.
	window isNil
		ifTrue: [card usages: usages at: t]
		ifFalse: [window do: [card usages: usages at: t. self fitToContent]]
!
update
	"Ask the collectors for fresh limits, then read them."
	collectNow isNil ifFalse: [^collectNow signal].
	Omarchy launch: #('omarchy-agent-usage-update' '--limits-only') then: [:p | wakeup signal]
! !

!AgentsApp methodsFor: 'hooks'!
prepare
	OmarchyTheme install.
	"the window opens as tall as the agents it shows"
	self content.
	self reload
!
started
	wakeup := Semaphore new.
	process := [[wakeup waitTimeoutMSecs: 60000. self reload] repeat] newProcess.
	process priority: Processor userBackgroundPriority; name: 'Agents reload'.
	process resume.
	self collectsItself ifTrue: [
		collected := #().
		collectNow := Semaphore new.
		collector := [[collected := AgentCollector usages. wakeup signal. collectNow waitTimeoutMSecs: 300000] repeat] newProcess.
		collector priority: Processor userBackgroundPriority; name: 'Agents collector'.
		collector resume]
!
stopped
	process isNil ifFalse: [process terminate. process := nil].
	collector isNil ifFalse: [collector terminate. collector := nil]
! !

!AgentsApp class methodsFor: 'desktop'!
cardId
	^'agents'
! !
