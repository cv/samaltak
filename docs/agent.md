# Agent

A coding agent inside the image, written in Smalltalk, driving the image it lives in. ⌘J in a tool opens a conversation window on that tool's context. Model: OpenAI `gpt-6.2-sol` ("Codex 6.2 Sol"; the Codex catalog's slug) through a ChatGPT device-code login, or any model behind the Anthropic Messages API with an API key the host sends in (API-key accounts, below). Design: `prototypes/5-agent/6-chosen.html` (the target; version 1 is a subset).

No persistence code: the account and its tokens (but no API key), conversations and their objects are ordinary objects, saved with the image.

## Version 1

The smallest agent that works end to end. Each item names the seam later work extends.

### Platform (Lowtalk, `src/VM-Platform`, `make translate`)
1. **TLS** (`PlatformTLS`, OpenSSL 3 on macOS and Linux): `tlsStart` (a connected socket → handle in the socket table), `tlsHandshake` (certificate verification against the OS trust store), `tlsRecv`, `tlsSend`, `tlsClose`, `tlsSemaphore`; host names through `socketResolve` (a lookup thread), TCP through `socketConnect`/`socketConnected`. Nothing blocks: each primitive completes or arms a semaphore with the sockets' convention, and Smalltalk waits with one timeout for the whole connect (docs/platform.md), so neither connecting nor a minute-long stream stops the VM.

### System-Net (new, layer 0)
2. `HTTPClient`: HTTP/1.1 over TLS or plain TCP, keep-alive, `Content-Length` and chunked bodies, no compression; `post:json:headers:`, `post:form:headers:`, and a streaming variant handing body chunks to a block. Cancelled by closing from another Process.
3. `SSEReader`: `text/event-stream` chunks → `{event. data}`.
4. `Base64` (decoding, URL alphabet: JWT claims).

JSON: System-Remote's `JSON` (already layer 0).

### System-Agent (new, layer 0, no UI)
5. **OpenAIAccount** (`OpenAIAccount default`): device login, refresh before expiry and on a 401, account id and email from the id token, sign out.
6. **CodexProvider**: builds the Responses request, streams it, decodes events into items and deltas. The one place that knows the backend; **AnthropicProvider** is its sibling for API-key accounts.
7. **AgentConversation**: the item list (developer instructions, messages, reasoning items echoed back, tool calls and outputs), its object table (`oN` ↔ object, strong references, an object keeps its ID; pictures excepted, see Images), its context, the turn loop (send, run tool calls, send again until no tool call; Stop cancels), `onChange:` the window redraws from.
8. **AgentContext**: what ⌘J bound — receiver, named bindings, optionally a frame — and how a cell compiles against it: `Compiler evaluate:for:bindings:`, or for a frame `Context>>evaluateInFrame:` (extended with bindings, for `oN` and the context's variables; the frame's temps win on a name clash). Default: receiver nil.
9. **AgentTool** (abstract: Responses spec, `run: aCall in: aConversation`) and three subclasses. New tools are subclasses.
   - **code-mode**: a freeform tool (raw Smalltalk, no JSON; the shape of Codex's own code mode). Runs in a fresh Process `agent code-mode` at the priority of a do-it, with `o1 … oN` and the context's bindings bound. Answers `oN` and the printString; one longer than 10,000 characters is cut with a note saying how to read the rest, and a short sequenceable collection's longest elements are cut each instead (`oN at: i`). A syntax error answers the compiler's message; an error answers the exception, its message and the top 10 frames, and the Process ends. After 60 s the Process is terminated and the result says so.
   - **show-object** (`{"id": "o2"}`): adds a show item for the object to the conversation. A Form is also sent to the model as an image (see Images).
   - **run-tests** (`{"names": ["FooTest", "Tests-Agent"]}`): runs test classes, or the test classes of packages, as `TestCase runNamed:` does, in a fresh Process `agent run-tests`; after 300 s it is terminated and the result says what ran. Answers the TestResult's `oN` and summary, then a line per failure (its message) and error (the exception and the top of its stack), cut at 10,000 characters. An unknown name answers an error. Its item (`#tests`) is drawn as a cell headed Run-tests, the equivalent Smalltalk as its source.
10. **AgentInstructions**: one hand-written developer message — code-mode and `oN`, the context, layering (`src/packages.txt`), that code changes go through `SourceFiler default writeMethod:` so they reach `src/`, and that the agent then runs the affected tests and commits (`SourceFiler default commit:`, a pull request; docs/github.md), plus where changes go in this image (`sourceState`: GitHub, a local checkout, or nowhere, with how the operator sets an account).

### Tools-Agent (new, layer 5)
11. **⌘J** in `ToolPane`, the Debugger, the Breakpoints window and the Profiler: `self agentContext`, then open the Agent window for that tool, or bring it back. `self` is the tool's subject when it is an object in the image; the selection and what is outside the image are named variables (omitted when nothing is selected); `describe` gives the model each variable's name, class and bounded printString. Contexts in version 1:
    - Workspace: its receiver; its variables (shared); the selected text.
    - Inspector: the object; `field` (the selected field's value).
    - Debugger: the selected frame (cells run in it: `self` and temps).
    - Notifier (`ToolsNotifier`): the selected frame, as the Debugger; `session`, `exception`.
    - Process Browser: the selected Process; `context` (the selected frame, an object: cells do not run in it).
    - System Browser: the selected class (the metaclass on the class side); `selector`, `method`, `package`; the selected text.
    - Method Browser: `methods`, `method`; the selected text.
    - Profiler: its `ProfilerData`; `range`, `bar`, `picked`, `process` (the filter).
    - File Browser: `path`, `entry` (the selected file or folder); the text selected in the previewed file.
    - Terminal: `terminal` (`terminal view send: 'ls', (String with: Character cr)` types into it), `text` (the screen); the selected text.
    - Transcript: `text`; the selected text.
    - VM Rebuild, VM Simulator: `output`; the selected text.
    - Breakpoints: the breakpoints and watchpoints listed; `breakpoint` (the selected one).
    - System Monitor: its samples (`SystemMonitorData`).
    - Other tools: the default context (nothing bound).
12. **AgentWindow** (proposal 1's layout): context strip, transcript, ASK prompt with Send and Stop, status bar (model, account, tokens, Sign out). Signed out, the transcript shows the login card (URL, code, Copy).
13. Transcript items: message, code cell (highlighted source, result with its `oN`), error, show-object. Show-object draws a Form as an image, anything else as printString plus an Inspect button that opens the Inspector. Item views are found by `AgentItemView for: anItem`, the seam for richer views.

### Tests
14. **Tests-Net**: HTTP and SSE against a plain-HTTP server in the image.
15. **Tests-Agent**: the conversation against a scripted provider (a turn with two cells and a show-object, an error, Stop); the provider and account against a plain-HTTP server in the image replaying recorded streams (a refresh after a 401).

### Milestones
1. **Spike**: device login and one `/responses` call by hand with `curl`; record the streams as fixtures.
2. **TLS and System-Net** (1–4, 14): `HTTPClient` fetches an `https://` URL from a Workspace while the UI stays live.
3. **Headless agent** (5–10, 15): `(AgentConversation new ask: 'how many classes are in UI-Widgets?') wait` from a Workspace or `samaltak-ctl eval`.
4. **Window and ⌘J** (11–13).

## Later

Each builds on a version 1 seam; none changes its shape.

- **Cells**: keep a failed cell's Process suspended (per-process `DebugSession` opener), its session an object with an ID and a Debug button; yield after 10 s and answer the running cell as an object the model waits on or terminates (`o7 waitFor:`); capture the cell's Transcript output.
- **Show-object kinds**: `anObject agentPresentationKind` (`#bars #table #source #flameGraph` …), declared by each package for its classes.
- **Contexts**: an AGENT tag on the origin tool; top bar Agents ▾.
- **Edits**: proposed edits as diff cells (Accept writes `src/`, Accept & Restart frame through `DebugSession>>recompile:inFrame:`); an approval mode that shows each cell before it runs.
- **Platform**: `openURL` for the login card.
- **Moves**: JSON to System-Support, `SourceFiler`/`ChunkFile` to layer 0, when the core needs them.
- **Provider**: context compaction; generated instructions (image facts, docs excerpts).
- **Remote control**: roles for the window, a `tests/remote` scenario.

## How it fits

**The agent is a layer-0 service; windows are views of it.** System-Agent knows no windows, like `DebugSession` and `Profiler`; the window observes a conversation. The core runs headless (tests, `samaltak-ctl eval`), and Tools-Agent stays thin, as the Debugger is on DebugSession.

**A conversation starts where the user is.** ⌘J hands it the tool's context, so `self`, the frame or the selection are bound rather than described. The core sees the context, never the tool.

**Code-mode is a do-it.** Same compiler path as `CodeEvaluator`, same Process discipline: visible in the Process Browser, profiled, stoppable. No sandbox: the agent has the powers of a user typing in a Workspace.

**Objects cross the model boundary by reference.** The model sees `oN` and a bounded printString; the object stays in the image and is bound in every later cell. Results compose without parsing, prompts stay small, identity is kept.

**Changes go to source.** The image is built from `src/`; the instructions send edits through `SourceFiler`, so they are live and appear in `git diff`.

**The provider is a risk.** `CodexProvider` uses an undocumented backend while presenting itself as the Codex CLI (its `client_id`, `originator`). It can break without notice and may not be allowed for third-party clients; decide before use beyond personal. Everything above it is the standard Responses API.

**Secrets live in the image.** Saving the image saves the refresh token. `build/` is git-ignored, but anyone with the image file has the account. Sign out clears the tokens. An API key is the exception: it is never saved (below).

## API-key accounts (Anthropic Messages)

**ApiKeyAccount** (`ApiKeyAccount default`) holds a provider's name (a label), base URL, model, thinking effort, max_tokens and API key; once it has a base URL and a model (`isConfigured`), new conversations talk to an **AnthropicProvider** and the Agent window uses it instead of the OpenAI account. The host configures it: `samaltak-ctl agent-config --from-pi [--provider p] [--model id] [--thinking level]` reads pi's `~/.pi/agent/models.json` and `settings.json` (`$PI_CODING_AGENT_DIR`; the default provider, model and thinking level unless named; the model's `api`, else the provider's, must be `anthropic-messages`; effort through the model's `thinkingLevelMap`, `maxTokens` from the model), resolves the provider's `apiKey` on the host (`!command` runs under `/bin/sh`, its stdout is the key; `$NAME` and `${NAME}` interpolate the environment) and sends all of it in one `agent-config` request over the control connection. The key is in no argv and no log, and nothing prints it: the image answers its configuration with `hasKey`. `samaltak-ctl agent-config` shows that configuration, `--clear` forgets it. The same works for the VM on UEFI (`samaltak-ctl open --uefi`): the request goes through QEMU's forwarded control port.

**The key is never saved.** It lives in the running image only: the account is on the shutdown list and overwrites and drops every key before a snapshot or quit (the full GC before a snapshot copies only live objects, so no stale copy remains; `ApiKeyAccountTest` uses a key for a request, snapshots, and searches the file). After Save image or Rebuild & reboot the window says how to set it again; Sign out forgets it.

**Requests.** `POST {baseURL}/v1/messages`, headers `x-api-key`, `anthropic-version: 2023-06-01`, `Accept: text/event-stream`. Body: `model`, `max_tokens`, `stream:true`, `system` (the developer message), `messages`, `tools` (code-mode as a tool whose `input_schema` has one string, `input`; show-object with its parameters), `tool_choice:{type:auto, disable_parallel_tool_use:true}`, `thinking:{type:adaptive, display:summarized}` with `output_config:{effort}`, or neither when thinking is off (models with adaptive thinking refuse `thinking:{type:disabled}`). Prompt caching: `cache_control:{type:ephemeral}` on the system prompt and on the last block of the last message, so each request reads its predecessor's prefix. The conversation keeps speaking the Responses API's items; the provider translates both ways: assistant blocks of one response form one assistant message (thinking first), tool outputs and later user content one user message (`tool_result`, `is_error` for an output starting `error:` or `syntax error:`; images as base64 blocks). Each item the provider makes keeps its content block under `anthropic` and the message id under `response`, so thinking blocks go back verbatim with their signatures.

**Stream.** `message_start` (id, input and cache counts), `content_block_start/delta/stop` (`text_delta` streamed to the window, `thinking_delta`, `signature_delta`, `input_json_delta`), `message_delta` (stop reason, output count), `message_stop`, `ping`, `error`. An item is handed over at its block's stop: text → `message`, thinking and redacted_thinking → `reasoning`, tool_use → `custom_tool_call` or `function_call`. Usage is reported as the Responses API counts it (input includes cache reads and writes; `cached_tokens` the reads). Errors: HTTP errors with the body's message (401/403 say how to set the key again), error events, a stream without `message_stop`, stop reasons `max_tokens`, `refusal` and `model_context_window_exceeded`. HTTP 408, 409, 429 and 5xx (529: overloaded), and overloaded, rate-limit and api error events before any output, are retried up to 4 times after `retry-after` (at most 60 s) or 1, 2, 4, 8 s; Stop ends the wait.

Verified by hand (2026-11-21) against `azure/anthropic/claude-opus-5-5` at `https://inference-api.nvidia.com` (pi's `nvidia-internal`), HTTP/1.1 over OpenSSL: `samaltak-ctl agent-config --from-pi` into a hosted image, then a conversation that ran a code-mode cell and answered; thinking echoed with its signature in the next turn; cache reads from the second request on. The recorded streams are the fixtures of `AnthropicProviderTest`. Under UEFI (2026-11-21, QEMU arm64 KVM, `samaltak-ctl open --uefi` then `agent-config --from-pi` through the forwarded control port) over the Smalltalk TLS client: the handshake with `inference-api.nvidia.com` takes 53–114 ms, the first text delta comes 1.0–3.6 s after the request (the model's thinking; the same on a kept connection), and a turn of five requests with four code-mode cells took 6.9 s, 7,973 of its 10,699 input tokens read from the cache.

## Images

What the model gets of a picture is bounded; the Form itself (the object `oN`, the Show view) is never changed.

- **Sending.** show-object of a Form adds a user message "Image shown from object oN" with an `input_image` part made by `AgentImage partFor:`: the Form scaled down (`Form>>scaledToFit:pixels:`, an area-averaging box filter, aspect kept) to at most 1568 px on the longer side (Anthropic's recommendation; it downscales larger ones anyway) and 1.15 megapixels, encoded as PNG. While the data URL is over 3.5 MB of base64 the edge shrinks to 70 % and the area halves. Images attached in the Agent window go through `AgentImage fit:`.
- **Encoding.** `PNGWriter` picks the smallest exact color type: indexed when there are at most 256 colors (typical UI screenshots), else RGB when opaque, else RGBA, each RGB/RGBA row with its best filter; the data goes through `ZLib` (System-Support: deflate with LZ77 and dynamic/fixed Huffman or stored blocks, whichever is shortest, and inflate). `PNGReader` reads PNGs back. Measured hosted on a 1920x1080 screen-like Form: full size 88 KB in 0.29 s; scaled to 1429x804 in 0.11 s, then 375 KB in 0.21 s (500 KB of base64); 1920x1080 noise (the worst case) 1.65 MB in 0.5 s. Before, the same frame was 8.3 MB of stored RGBA (11 MB of base64), over the API's 10 MB limit.
- **Every request** (`AgentConversation>>input`): an image over 3.5 MB of base64 already in the history (a conversation from before) is decoded and encoded again within the limits, or, if it cannot be decoded (not PNG), replaced by the text `[image omitted: too large to send (N bytes)]`, in its item for good. Only the newest 10 images, at most 10 MB of base64 together, are sent; older ones go as `[image omitted: an older image, no longer sent; show it again to see it]`, and that placeholder replaces them in their items for good (once beyond the newest an image stays so; the cache prefix changes once when one drops out).
- **Memory.** A 1920x1080 screenshot is an 8 MB Form: a session that showed some 25 of them filled a 256 MB heap. The object table keeps only the newest 4 pictures (`AgentConversation keptPictures`; objects that are `isAgentPicture`: Forms over 480 px on the longer side) strongly; older ones it holds weakly (`AgentReleasedObject`: still `oN` while something else keeps them), and the items that showed them keep a thumbnail of at most 480 px (`agentThumbnail`, 0.5 MB) instead. show-object of a released, collected one answers that it is gone: capture it again.
- **Refusals.** When the API still answers HTTP 400/413 that an image or the request is too large, the provider signals `AgentImageRefused` with the images it names (Anthropic `messages.N.content.M`, the Responses API `input[N].content[M]`; else all of them); the conversation replaces those by `[image omitted: the model's API refused it as too large]` and sends once more. A second refusal ends the turn with the error (Retry is available).

## Context editing

The agent shrinks its own context with messages to the conversation, which every cell binds as `thisConversation` (after pit's `session` API, github.com/cv/pit). Each AgentItem sends its `wire`; an edit replaces the wire and keeps the `original`, so the window still shows the original and `restore` undoes it.

- `outline` (`outlineFrom:to:`): a line per item: index, kind, estimated tokens (four characters of JSON a token, an image 1,600), edit, the start of its text and result.
- `elide: indexes reason: aString`: a finished tool call keeps its call and output, with code-mode's source and the output replaced by stubs saying where the originals are (`(thisConversation items at: 4) text` and `result`; its `oN` stays bound). Anthropic's stored tool_use block is dropped so the stub is sent. A show-object's picture goes with it. Not the response being run, nor an item no larger than its stub.
- `summarize: first to: last as: aString`: the agent's items of a finished turn (no user message, note or notice; reasoning just before the range joins it) become one assistant message carrying the summary, which must be smaller. AnthropicProvider joins consecutive assistant blocks into one message.
- `note: key put: aStringOrNil`, `notes`: a keyed working note appended as a user message `<note key="…" by="you, not the user">` (a note, like a notice, travels as a user message and says it is not the user's); a new version supersedes the old ones, which are still sent (the cached prefix stays) until an elide or summarize rewrites the context or the notes exceed `noteBudget` (4,096 tokens or a tenth of the window).
- Edits are staged and applied when the turn ends (Stop discards them), or before the next request after `applyNow`; with no turn running they apply at once. `discardEdits` forgets them.
- When the last request first reaches 50% or 75% of `contextWindow` (default 200,000), a `#notice` item tells the agent (`[Notice from Samaltak, not the user: Context: …]`); after the context falls below half, the thresholds notice again.

## Commits and pull requests

The agent's changes reach `src/` through the SourceFiler: in a local checkout they are files `git diff` shows; where there is none (UEFI) and the operator has sent a GitHub account (`samaltak-ctl github-config --from-gh`, docs/github.md), they collect in the image. Its instructions say: after changing code, run the affected tests in the image, then `SourceFiler default commit: 'Area: one sentence.'`, which makes a commit on a new `agent/…` branch and opens a pull request into `main`; report the pull request's URL; never push to the base branch. Without an account and without a writable source directory the agent says so and how the operator sets one. The token, like an API key, lives in memory only.

## Protocol (from `openai/codex` at `b7056f3`, 2026-11-15)

Device login, issuer `https://auth.openai.com`, client id `app_EMoamEEZ73f0CkXaXp7hrann`:
1. `POST /api/accounts/deviceauth/usercode` `{"client_id"}` → `device_auth_id`, `user_code`, `interval` (a string). Show `https://auth.openai.com/codex/device` and the code; it expires after 15 min.
2. Poll `POST /api/accounts/deviceauth/token` `{"device_auth_id","user_code"}` every `interval` s: 403/404 = pending; 2xx → `authorization_code`, `code_verifier` (the server makes the PKCE pair).
3. `POST /oauth/token`, form-encoded: `grant_type=authorization_code`, `client_id`, `code`, `redirect_uri=https://auth.openai.com/deviceauth/callback`, `code_verifier` → `id_token`, `access_token`, `refresh_token`.
4. Account id: id-token claim `"https://api.openai.com/auth".chatgpt_account_id`; email: `email`.
5. Refresh: `POST /oauth/token`, JSON `{"client_id","grant_type":"refresh_token","refresh_token","refresh_reason"}` when `exp` is under 5 min away, and on a 401. Refresh tokens rotate (keep every token returned); `refresh_token_reused/expired/invalidated` or `invalid_grant` → signed out.

Model call: `POST https://chatgpt.com/backend-api/codex/responses`, `Accept: text/event-stream`; headers `Authorization: Bearer`, `chatgpt-account-id`, `originator`, `version: 1.0.0` (older versions are refused the model), `session-id`, `User-Agent`. Body: `model:"gpt-6.2-sol"`, `stream:true`, `store:false`, `input` (first item a `developer` message with our instructions; there is no `instructions` field), `tools`, `tool_choice:"auto"`, `parallel_tool_calls:false`, `reasoning:{effort}`, `include:["reasoning.encrypted_content"]`. Events: `response.output_text.delta`, `response.output_item.done` (complete items, tool calls), `response.completed` (usage), `response.incomplete`, `response.failed`, `error`; others ignored.

Verified by hand (2026-11-15): HTTP/1.1 with a chunked event stream works; plain `tools` and our own developer message are accepted (Codex itself sends this model its tools in an `additional_tools` input item and a 63 KB instruction template). A code-mode call arrives as a `custom_tool_call` item (`input`: the source) and is answered with `custom_tool_call_output`; show-object as `function_call` / `function_call_output`. Output items are echoed back verbatim in the next request.

Code-mode results as the model sees them:

    o2 an Array(TextEditor->157 Widget->89 ListView->86 TextLayout->48 MenuView->38)

    error: MessageNotUnderstood: TextEditor class>>keyBindings
      TextEditor class(Object)>>doesNotUnderstand: #keyBindings
      UndefinedObject>>DoIt
