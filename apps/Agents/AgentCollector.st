Object subclass: #AgentCollector
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Agents'!

AgentCollector comment: 'I collect the agents'' rate limits where omarchy-agent-usage-update does not (macOS), as AgentUsages of the records it writes:

- Codex: through the image''s ChatGPT sign-in (the Agent''s OpenAIAccount) from ChatGPT''s usage endpoint, else through the codex CLI (codex app-server, account/rateLimits/read).
- Claude Code: through the claude CLI''s sign-in (~/.claude/.credentials.json, or its macOS keychain item) from Anthropic''s OAuth usage endpoint; when it expired, claude -p /usage (no model call) has the CLI refresh it first.

	AgentCollector usages'!

!AgentCollector class methodsFor: 'collecting'!
usages
	"The AgentUsages of the agents I can reach now."
	^(Array with: self codex with: self claude) reject: [:each | each isNil]
!
codex
	"Codex's limits through the image's sign-in, else the codex CLI; nil if neither answers."
	^[(self codexFromAccount ifNil: [self codexFromCLI]) ifNotNil: [:record | AgentUsage fromRecord: record]]
		on: Error do: [:e | e return: nil]
!
claude
	"Claude Code's limits through the claude CLI's sign-in; nil without one."
	^[self claudeFromCLI ifNotNil: [:record | AgentUsage fromRecord: record]]
		on: Error do: [:e | e return: nil]
! !

!AgentCollector class methodsFor: 'codex'!
codexFromAccount
	| account headers |
	account := AgentWindow account.
	account == OpenAIAccount default ifTrue: [account keepIn: AgentWindow accountPath].
	account isSignedIn ifFalse: [^nil].
	headers := Dictionary new
		at: 'Authorization' put: 'Bearer ', account accessToken;
		at: 'User-Agent' put: 'samaltak';
		yourself.
	account accountId ifNotNil: [:id | headers at: 'chatgpt-account-id' put: id].
	^self codexRecordFrom: (self getJSON: 'https://chatgpt.com/backend-api/wham/usage' headers: headers)
!
codexFromCLI
	"Ask codex app-server (JSON-RPC over stdio) for the account's rate limits."
	| lines command reply |
	lines := #('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"samaltak","version":"1"}}}'
		'{"jsonrpc":"2.0","method":"initialized"}'
		'{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read"}').
	command := 'command -v codex >/dev/null || exit 1; { printf ''%s\n'' ',
		((lines collect: [:each | OSProcess quote: each]) inject: '' into: [:a :b | a, ' ', b]),
		'; sleep 15; } | codex app-server 2>/dev/null | awk ''/"id":2[,}]/ { print; exit }'''.
	reply := [JSON parse: (OSProcess run: command) output] on: Error do: [:e | e return: nil].
	(reply isKindOf: Dictionary) ifFalse: [^nil].
	^self codexRecordFromCLI: (reply at: 'result' ifAbsent: [nil])
!
codexRecordFrom: json
	"A record of ChatGPT's usage (backend-api/wham/usage): its plan and rate-limit windows."
	| limits rate |
	(json isKindOf: Dictionary) ifFalse: [^nil].
	limits := OrderedCollection new.
	rate := json at: 'rate_limit' ifAbsent: [nil].
	(rate isKindOf: Dictionary) ifTrue: [
		#('primary_window' 'secondary_window') do: [:key |
			| w |
			w := rate at: key ifAbsent: [nil].
			(w isKindOf: Dictionary) ifTrue: [
				limits add: (self limit: (self labelForSeconds: (w at: 'limit_window_seconds' ifAbsent: [nil]))
					percent: (w at: 'used_percent' ifAbsent: [nil]) resetsAt: (w at: 'reset_at' ifAbsent: [nil]))]]].
	^self record: 'codex' name: 'Codex' tier: (json at: 'plan_type' ifAbsent: [nil]) limits: limits
!
codexRecordFromCLI: result
	"A record of codex app-server's account/rateLimits/read result."
	| limits rate |
	(result isKindOf: Dictionary) ifFalse: [^nil].
	rate := result at: 'rateLimits' ifAbsent: [nil].
	(rate isKindOf: Dictionary) ifFalse: [^nil].
	limits := OrderedCollection new.
	#('primary' 'secondary') do: [:key |
		| w minutes |
		w := rate at: key ifAbsent: [nil].
		(w isKindOf: Dictionary) ifTrue: [
			minutes := w at: 'windowDurationMins' ifAbsent: [nil].
			limits add: (self limit: (self labelForSeconds: (minutes isNumber ifTrue: [minutes * 60]))
				percent: (w at: 'usedPercent' ifAbsent: [nil]) resetsAt: (w at: 'resetsAt' ifAbsent: [nil]))]].
	^self record: 'codex' name: 'Codex' tier: (rate at: 'planType' ifAbsent: [nil]) limits: limits
! !

!AgentCollector class methodsFor: 'claude'!
claudeFromCLI
	| credentials headers |
	(self hasCommand: 'claude') ifFalse: [^nil].
	credentials := self claudeCredentials.
	(credentials isNil or: [self hasExpired: credentials]) ifTrue: [
		"asking for its usage, the CLI refreshes its sign-in (no model call)"
		OSProcess run: 'claude -p /usage >/dev/null 2>&1 </dev/null'.
		credentials := self claudeCredentials].
	(credentials isNil or: [self hasExpired: credentials]) ifTrue: [^nil].
	headers := Dictionary new
		at: 'Authorization' put: 'Bearer ', (credentials at: 'accessToken');
		at: 'anthropic-beta' put: 'oauth-2025-04-20';
		at: 'User-Agent' put: 'samaltak';
		yourself.
	^self claudeRecordFrom: (self getJSON: 'https://api.anthropic.com/api/oauth/usage' headers: headers) credentials: credentials
!
claudeCredentials
	"The claude CLI's OAuth sign-in (claudeAiOauth), nil without one: ~/.claude/.credentials.json, else its macOS keychain item."
	| text json |
	text := [File readText: XDG home / '.claude/.credentials.json'] on: Error do: [:e | e return: nil].
	text isNil ifTrue: [
		text := (OSProcess run: 'command -v security >/dev/null && security find-generic-password -s ''Claude Code-credentials'' -w 2>/dev/null') output].
	json := [JSON parse: text] on: Error do: [:e | e return: nil].
	(json isKindOf: Dictionary) ifFalse: [^nil].
	json := json at: 'claudeAiOauth' ifAbsent: [nil].
	((json isKindOf: Dictionary) and: [(json at: 'accessToken' ifAbsent: [nil]) isString]) ifFalse: [^nil].
	^json
!
hasExpired: credentials
	"Whether the access token expires within a minute (expiresAt: milliseconds since 1970)."
	| expires |
	expires := credentials at: 'expiresAt' ifAbsent: [nil].
	^expires isNumber and: [expires / 1000 < (Time utcMicroseconds / 1000000 + 60)]
!
claudeRecordFrom: json credentials: credentials
	"A record of Anthropic's OAuth usage: its limits (weekly, a model's weekly, the session), else its five_hour and seven_day windows; the plan from the sign-in (Max 20x)."
	| limits scoped |
	(json isKindOf: Dictionary) ifFalse: [^nil].
	limits := OrderedCollection new.
	scoped := json at: 'limits' ifAbsent: [nil].
	((scoped isKindOf: Array) and: [scoped notEmpty])
		ifTrue: [
			scoped do: [:l |
				(l isKindOf: Dictionary) ifTrue: [
					| label limit |
					label := self claudeLabelOf: l.
					limit := self limit: label percent: (l at: 'percent' ifAbsent: [nil]) resetsAt: (l at: 'resets_at' ifAbsent: [nil]).
					"a model's window is titled by its label (Fable Weekly)"
					(#('Weekly (7-day)' '5-hour session') includes: label) ifFalse: [limit at: 'title' put: label].
					limits add: limit]]]
		ifFalse: [
			#(#('five_hour' '5-hour session') #('seven_day' 'Weekly (7-day)')) do: [:pair |
				| w |
				w := json at: pair first ifAbsent: [nil].
				(w isKindOf: Dictionary) ifTrue: [
					limits add: (self limit: pair last percent: (w at: 'utilization' ifAbsent: [nil]) resetsAt: (w at: 'resets_at' ifAbsent: [nil]))]]].
	^self record: 'claude' name: 'Claude Code' tier: (self claudeTierOf: credentials) limits: limits
!
claudeLabelOf: aLimit
	"Weekly (7-day), Fable Weekly (a model's), 5-hour session, or the kind."
	| group kind scope model |
	group := (aLimit at: 'group' ifAbsent: ['']) ifNil: [''].
	kind := (aLimit at: 'kind' ifAbsent: ['']) ifNil: [''].
	scope := aLimit at: 'scope' ifAbsent: [nil].
	model := (scope isKindOf: Dictionary) ifTrue: [scope at: 'model' ifAbsent: [nil]].
	model := (model isKindOf: Dictionary) ifTrue: [model at: 'display_name' ifAbsent: [nil]].
	(group = 'weekly' or: [kind beginsWith: 'weekly'])
		ifTrue: [^model isString ifTrue: [model, ' Weekly'] ifFalse: ['Weekly (7-day)']].
	((group includesSubstring: 'session') or: [(kind includesSubstring: 'session') or: [kind includesSubstring: 'five_hour']])
		ifTrue: [^'5-hour session'].
	^kind copyReplaceAll: '_' with: ' '
!
claudeTierOf: credentials
	"Max 20x from subscriptionType max and rateLimitTier default_claude_max_20x."
	| type tier times |
	type := credentials at: 'subscriptionType' ifAbsent: [nil].
	type isString ifFalse: [^nil].
	tier := credentials at: 'rateLimitTier' ifAbsent: [''].
	times := tier isString ifTrue: [tier subStrings: '_'] ifFalse: [#()].
	times := times isEmpty ifTrue: [''] ifFalse: [times last].
	^((times endsWith: 'x') and: [times size > 1 and: [(times allButLast allSatisfy: [:c | c isDigit])]])
		ifTrue: [type capitalized, ' ', times]
		ifFalse: [type capitalized]
! !

!AgentCollector class methodsFor: 'records'!
record: anId name: aName tier: aTier limits: aCollection
	^Dictionary new
		at: 'id' put: anId;
		at: 'name' put: aName;
		at: 'tierLabel' put: (aTier isString ifTrue: [aTier capitalized] ifFalse: ['']);
		at: 'limits' put: aCollection asArray;
		yourself
!
limit: aLabel percent: aPercent resetsAt: aTime
	"A window as the records hold it: its label, how much of it is used (0 to 1) and when it resets (ISO 8601 or seconds since 1970)."
	^Dictionary new
		at: 'label' put: aLabel;
		at: 'percent' put: (aPercent isNumber ifTrue: [aPercent / 100.0] ifFalse: [-1]);
		at: 'resetsAt' put: aTime;
		yourself
!
labelForSeconds: seconds
	"Weekly (7-day) for a week, else n-hour session."
	seconds isNumber ifFalse: [^'Limit'].
	seconds >= (6 * 86400) ifTrue: [^'Weekly (7-day)'].
	^(seconds / 3600) rounded printString, '-hour session'
! !

!AgentCollector class methodsFor: 'private'!
hasCommand: aName
	^(OSProcess run: 'command -v ', (OSProcess quote: aName), ' >/dev/null') exitCode = 0
!
getJSON: aURL headers: aDictionary
	"GET aURL; its JSON, or an Error if it fails, is not 200 or takes longer than 15 s."
	| client done response failure worker |
	client := HTTPClient new.
	done := Semaphore new.
	worker := [[response := client get: aURL headers: aDictionary]
		on: Error do: [:e | failure := e messageText. e return: nil].
		done signal] fork.
	(done waitTimeoutMSecs: 15000) ifTrue: [
		client close.
		worker terminate.
		^self error: aURL, ': timed out'].
	client close.
	failure isNil ifFalse: [^self error: failure asString].
	response status = 200 ifFalse: [^self error: aURL, ': ', response status printString].
	^response json
! !
