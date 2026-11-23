Column subclass: #AgentLoginCard
	instanceVariableNames: 'titleLabel signInButton urlLabel codeRow codeLabel messageLabel urlCopyButton keyHelp accountsButton apiKeyButton noAccounts'
	classVariableNames: ''
	package: 'UI-Agent'!

AgentLoginCard comment: 'I am what an AgentWindow shows instead of its transcript while signed out: a "Sign in with ChatGPT" button, then the device login''s URL and code (large, with a Copy button), and a line of news (waiting, why the last attempt failed). The window runs the login; I only show its state. For an ApiKeyAccount without its key (showKeyHelp:) I say instead how to set it: in the Accounts window (my Accounts… button, AccountsPanel) or from the host (samaltak-ctl agent-config --from-pi). Beside Sign in with ChatGPT, "Use an API key…" opens the Accounts window too; the window sets both buttons'' action (onAccounts:), or hides them where there is no Accounts window (withoutAccounts: an application''s runtime image).'!

!AgentLoginCard methodsFor: 'initialization'!
initialize
	super initialize.
	titleLabel := Label text: '' font: #uiBold.
	titleLabel name: 'title'.
	signInButton := Button label: 'Sign in with ChatGPT'.
	signInButton name: 'sign-in'; beDefault.
	apiKeyButton := Button label: 'Use an API key…'.
	apiKeyButton name: 'use-api-key'; sizeToContent.
	accountsButton := Button label: 'Accounts…'.
	accountsButton name: 'accounts'; sizeToContent.
	urlLabel := Label text: '' font: #ui.
	urlLabel name: 'url'.
	urlCopyButton := Button label: 'Copy URL'.
	urlCopyButton name: 'copy-url'; sizeToContent.
	codeLabel := Label text: '' font: (Font faceNamed: 'JetBrainsMono-Bold' size: 28).
	codeLabel name: 'code'.
	codeRow := Row with: (Array
		with: (codeLabel sizeToContent; yourself)
		with: ((Button label: 'Copy' action: [self clipboardText: codeLabel text]) name: 'copy'; sizeToContent; yourself)
		with: Widget new).
	codeRow spacing: 14; fixed: 44; padding: (0 @ 10 corner: 0 @ 10).
	messageLabel := Label text: '' font: #uiItalic.
	messageLabel name: 'message'; color: #ink3.
	self addAll: (Array
		with: (titleLabel fixed: 28; yourself)
		with: ((Row with: (Array with: (signInButton sizeToContent; yourself) with: apiKeyButton with: Widget new)) spacing: 14; fixed: 30; padding: (0 @ 4 corner: 0 @ 4); yourself)
		with: ((Row with: (Array with: accountsButton with: (urlLabel sizeToContent; yourself) with: urlCopyButton with: Widget new)) spacing: 14; fixed: 30; yourself)
		with: codeRow
		with: (messageLabel fixed: 24; yourself)
		with: Widget new).
	self padding: (self gutter @ 30 corner: 20 @ 20).
	self showButton: nil
!
gutter
	^62
! !

!AgentLoginCard methodsFor: 'accessing'!
signInButton
	^signInButton
!
accountsButton
	^accountsButton
!
apiKeyButton
	^apiKeyButton
!
onAccounts: aBlock
	"What Accounts… and Use an API key… do (the window opens the Accounts window)."
	accountsButton action: aBlock.
	apiKeyButton action: aBlock
!
withoutAccounts
	"No Accounts window here (an application's runtime image): only the host sets a key."
	noAccounts := true.
	apiKeyButton visible: false
!
code
	^codeLabel text
!
message
	^messageLabel text
!
title
	^titleLabel text
!
isShowingKeyHelp
	^keyHelp == true
! !

!AgentLoginCard methodsFor: 'showing'!
showMessage: aString
	signInButton owner visible: false.
	messageLabel text: aString
!
showURL: aURL code: aCode
	urlLabel text: 'Open ', aURL, ' and enter this code:'.
	urlCopyButton label: 'Copy URL'; action: [self clipboardText: aURL]; sizeToContent.
	accountsButton visible: false.
	urlLabel owner visible: true.
	codeLabel text: aCode.
	codeRow visible: true; layout.
	messageLabel text: 'Waiting for you to approve the sign-in…'
!
showButton: aStringOrNil
	"Signed out: the button, and why the last attempt failed."
	keyHelp := false.
	titleLabel text: 'The agent needs your ChatGPT account.'.
	signInButton owner visible: true.
	urlLabel owner visible: false.
	accountsButton visible: false.
	codeRow visible: false.
	messageLabel text: (aStringOrNil ifNil: [''])
!
showKeyHelp: anApiKeyAccount
	"An API-key account without its key: how to set it, here or from the host."
	keyHelp := true.
	titleLabel text: 'The agent needs the API key for ', anApiKeyAccount model, ' at ', (anApiKeyAccount providerName ifNil: [anApiKeyAccount baseURL]), '.'.
	signInButton owner visible: false.
	urlLabel text: 'or on the host: samaltak-ctl agent-config --from-pi'.
	urlCopyButton label: 'Copy'; action: [self clipboardText: 'samaltak-ctl agent-config --from-pi']; sizeToContent.
	urlLabel owner visible: true.
	accountsButton visible: noAccounts ~~ true.
	codeRow visible: false.
	messageLabel text: 'The key stays in memory: set it again after Save image or a restart.'
! !

!AgentLoginCard methodsFor: 'remote control'!
remoteRole
	^#group
!
remoteIsTransparent
	^false
! !
