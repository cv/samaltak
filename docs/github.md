# GitHub

The image turns its own source changes into a branch, a commit and a pull request on GitHub through the REST API, with no files, processes or git: hosted, and on UEFI over the Smalltalk TLS client (docs/tls.md). The in-image agent (docs/agent.md) uses it: it changes code, runs the tests in the image, commits, and reports the pull request's URL; a person reviews and merges, and nothing in the image updates the base branch. The other way, a running image updates itself to the base branch after merges, without a restart (below: Updating a running image).

## Flow

1. **Configure**, on the host: `samaltak-ctl open` (or `open --uefi`), then `samaltak-ctl github-config --from-gh`. One `github-config` request goes over the control connection (on UEFI through QEMU's forwarded control port): the repository (`owner/name` of the current checkout's `origin` remote unless `--repo`), the base branch (`main` unless `--base`), the branch prefix (`agent/` unless `--prefix`) and the token (`gh auth token`'s stdout, or with `--token-command 'cmd'` the command's, run under `/bin/sh`). The image answers its configuration with `hasToken`, never the token. `samaltak-ctl github-config` shows it, `--clear` forgets it all; `--repo`, `--base` or `--prefix` alone change those and keep the token. Without a host (bare metal), the World's **Accounts** window (World menu › Accounts, `AccountsPanel`, docs/agent.md) does the same: repository, base branch and branch prefix fields, whether a token is set (never the token), a masked field to type or paste one into (⌘V or Paste), **Save** (`configure:`: a bad setting changes nothing and the window says why) and **Forget token** (the repository stays).
2. **Change**: compile, then write with the SourceFiler as always (below: a change set).
3. **Test** in the image: `FooTest run`.
4. **Commit**: `SourceFiler default commit: 'Area: what changed'` (a subject of at most ~72 characters, the pull request's title; optionally a short body after a blank line) answers a GitHubPullRequest; its url goes to the person who reviews it.

## Pieces (System-Net, layer 0; Tools)

- **GitHubAccount** (`GitHubAccount default`): repository (`owner/name`), baseBranch (`main`), branchPrefix (`agent/`), apiURL, and a token held in memory only (below). `isConfigured`: a repository and a token; `ownsBranch:`: under the prefix and not the base branch; `configure:` (the command's JSON names: `repository`, `baseBranch`, `branchPrefix`, `apiUrl`, `token`; a missing one keeps its value, a bad one changes nothing), `clear`. It registers the `github-config` control command: `{"cmd": "github-config", "repository": "cv/samaltak", "baseBranch": "main", "branchPrefix": "agent/", "token": "..."}`, `{"cmd": "github-config"}` (the configuration), `{"cmd": "github-config", "clear": true}`, each answering `{repository, baseBranch, branchPrefix, apiUrl, hasToken}`.
- **GitHubClient** (`GitHubClient on: anAccount`): `get:`, `post:json:`, `patch:json:`, `put:json:`, `delete:` on API paths (`repositoryPath: 'git/blobs'`) → parsed JSON; one kept-alive HTTPClient connection; headers `Authorization: Bearer`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, `User-Agent`. A non-2xx status signals **GitHubError** (status, the API's message and errors, `METHOD /path`; never a header); so do a lost connection and a malformed body (status nil). It refuses, before sending, any write that would create, move or delete a branch outside `branchPrefix` or the base branch (git/refs, contents, merges, merging a pull request).
- **SourceFiler** (Tools) writes single chunks (ChunkFile) through a store: **SourceDirectoryStore** (the local `src/`) or **GitHubSourceStore** (the repository's `src/`). It uses GitHub when the account is configured and there is no writable source directory (UEFI, whose volumes are read-only), or after `useGitHub: true`.
- **GitHubPullRequest**: what a commit made: number, url (nil without a pull request), branch, commitSha.

## A change set

```smalltalk
SourceFiler default writeMethod: Foo >> #bar.      "'src/Pkg/Foo.st'"
SourceFiler default pendingChanges.                "#('src/Pkg/Foo.st')"
SourceFiler default commit: 'Pkg: bar answers 3

Why, in a sentence.'.                              "a GitHubPullRequest"
SourceFiler default commit: '...' pullRequest: false.
SourceFiler default discardChanges
```

The first read starts it: GET `git/ref/heads/<base>` records the base commit, `git/commits/<sha>` its tree, `git/trees/<tree>?recursive=1` lists the tree once; each file is read once from `git/blobs/<sha>` (base64; any size the API serves). Edits stay in memory; a file left without chunks is removed. `commit:` posts a blob per changed file (base64), a tree on the base tree (a removed file as `sha: null`), a commit with the message whose parent is the base commit, the ref `refs/heads/<branchPrefix><yyyymmdd-hhmmss>-<slug>` (UTC; the slug from the first line) and a pull request into the base branch (title: the first line; body: the rest and the methods, definitions and comments written). Success ends the change set; a failure signals GitHubError and keeps it (a branch already made stays; committing again makes another). The change set survives a snapshot; the token does not.

## The token

**Never saved or shown.** It lives in the running image only: GitHubAccount is on the shutdown list and overwrites and drops every token before a snapshot or quit, its `printString` and the command's answer leave it out, GitHubError never carries a header. On the host it is in no argv (gh and the token command write it to samaltak-ctl's stdout pipe) and no log; it travels in the request's JSON only. After Save image or Rebuild & reboot the repository, the branches and a change set stay; the token must be sent (or pasted in Accounts) again. The Accounts window's token field is cleared before a snapshot too, and pasting into it empties the clipboard. The project function `samaltak.ctlSession` redacts what looks like a GitHub token (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`, `github_pat_`) in what it returns.

**Which token.** `gh auth token` is gh's OAuth token: it reaches every repository the gh login can (scopes `repo`, `workflow`, …), so `--from-gh` is for trying things out, and samaltak-ctl says so. For real use make a fine-grained personal access token (github.com → Settings → Developer settings → Fine-grained tokens) for the fork only (Repository access: only select repositories) with Contents: read and write and Pull requests: read and write (Metadata: read comes with them), keep it in a password manager, and send it with the manager's CLI:

    samaltak-ctl github-config --token-command 'op read op://Private/samaltak-github/token'

GitHubClient's ref guard keeps even a broad token off the base branch and every ref outside the prefix; branch protection on `main` is a second guard, GitHub's.

## The agent

AgentInstructions tells the agent: after changing code, run the affected tests in the image, then `SourceFiler default commit: 'Area: what changed'` (AGENTS.md's commit message style) and report the pull request's url; never push to the base branch. Its `sourceState`, a line of every request, says where changes go in this image: to GitHub (repository, prefix, base), to a local checkout (the user commits with git), collected for GitHub without a token, or nowhere; in the last two the agent tells the user to run `samaltak-ctl github-config --from-gh` on the host.

## Updating a running image

A long-lived image (the UEFI World with an agent whose state lives only in memory) takes what was merged to main, by its own pull requests or anyone's, without a restart:

    SourceFiler default previewUpdateFrom: 'main'.   "what it would do"
    SourceFiler default updateFrom: 'main'.          "a SourceUpdate: its summary says what it did"

or from the host, through the control channel (github-config first):

    samaltak-ctl update --dry-run
    samaltak-ctl update [--ref main] [--theirs] [--force] [--json]

**The base commit.** `make image` passes `git rev-parse HEAD` to stage 2 (`--base-commit`, and `--base-dirty` when `git status -- src` shows uncommitted changes), which records it: `SourceFiler baseCommit`, `SourceFiler baseDirty`. Hosted and UEFI images (made from the same image) know it alike; an update moves it to the head it applied, and a saved image keeps it.

**What it does** (SourceUpdate, Tools): the head of the branch (`git/ref/heads/main`), `compare/<base>...<head>` (the commit count, and a note when the image's commit is not an ancestor of the branch), both commits' trees (the changed paths, all of them: no 300-file limit), the old and new blobs of each changed source file. Each file is cut into chunks (ChunkFile) and the chunks matched across files by class and selector: class definitions, class-side instance variables, comments, methods added, changed and removed (a method moving to an extension file is a category change). Then:

1. **Compile first.** Every new or changed method compiles against shadow classes (unregistered copies with the new definitions); when a class's instance variables or superclass change, its other methods and its subclasses' methods compile on the new shape too, and a removed class must have no subclass left. One failure and nothing is installed: the summary says what failed (`nothing applied: Foo>>bar: Undeclared variable zork`).
2. **Install**, at user-interrupt priority so no other Process runs half-updated code: new packages (packages.txt order), class definitions (superclass first; ClassBuilder reshapes the class and migrates its instances, as the browser does), class-side instance variables, comments, methods added and changed, methods removed, removed classes last; then the instance variables existing instances gained (below); then each new class's class-side `initialize`. A changed `initialize` of an existing class is not run (a note says so): run it by hand if its state needs it.
3. **Base commit** := the head.

**Conflicts.** A change applies where the image has the base's version and is skipped where it already has the head's. Where the image has neither (a method changed here, or in the SourceFiler's pending change set, and upstream), it is kept as it is and listed under conflicts; `updateFrom: 'main' takeTheirs: true` (`--theirs`) overwrites. A conflicting class definition holds back all of its class's changes. Methods changed here and not upstream stay as they are.

**New instance variables.** ClassBuilder gives the instances a class already has nil in the instance variables it gains. With the update's methods installed (still at user-interrupt priority), SourceUpdate asks each reshaped class, and each subclass for its own instances, to set them: `Behavior>>initializeAddedInstanceVariables: names in: instances`. By default that does nothing unless the class answers true to `initializesAddedInstanceVariables` (class side): then each instance gets, where it is still nil, the value `initialize` gives a new instance (`self new`, a fresh one per instance, so no two share a collection). Answer true where `new` only sets fields (AgentTool does: a tool's `limit` added later is set in the conversations' tools); override `initializeAddedInstanceVariables:in:` where the value must come from elsewhere. A note says which instances got which variables, or that they stayed nil. So a class whose `initialize` sets a variable needs no `ifNil:` in its accessor for instances made before the variable existed; a variable nil by design (unset, lazily made) still needs one. Class-side instance variables a class gains start nil: set them in a class-side method run by hand, as for a changed `initialize`.

**Image changes that need the new VM.** An image updated live keeps running the VM it was started with, so image changes made together with VM changes may not work on it (99cfe6d changed `String>>hash` and the VM's `stringHash` primitive together, with an image-header flag: the new `String>>hash` with the old VM would hash long Strings two ways). When the range changes `src/VM-*` or `vm/` (not `vm/gen`, which the translator makes from `src/VM-*`), SourceUpdate reads the VM methods that changed (Lowtalk, by chunk) and the lines that changed in `vm/`'s C sources, and flags each image method it would change that relates to them: its primitive (`<primitive: 'stringHash'>`) is defined by a changed VM method (`<vmPrimitive: 102 name: 'stringHash'>`), is a changed VM method's selector (`ObjectMemory>>stringHash:`) or appears in a changed C line; a changed VM method's text names it (`String>>hash`); or a changed VM method has its selector (except common ones: `initialize`, `printOn:`, `hash` ...). If any is flagged, nothing is applied: `nothing applied: image changes that depend on VM changes in the same range, which this image's VM does not have until a restart: String>>hash (named by ObjectMemory>>stringHash: in src/VM-Core/ObjectMemory.st); restart with an image built at 99cfe6d, or force the update`. Restart, or `updateFrom: 'main' force: true` (`samaltak-ctl update --force`) to apply them anyway (a note lists them). `vmDependent` (`--json`: `vmDependent`) lists them.

**What needs a restart, or is not the image's.** Changes under `src/VM-*` and `vm/` are the VM: listed as *needs restart* (they take effect in an image built and booted anew; `SourceFiler needsRestart` remembers them across updates). Changes outside `src/` (Makefile, tools/, boot/, docs/, tests/) are the host's checkout: listed as *host side*. Other files in `src/`, packages not in this image and do-it chunks are listed as *not applied*. Example: `applied 37 methods in 9 classes, 1 new class (abc1234..def5678, 5 commits); needs restart for: src/VM-Core/Posix.st; host side, not in the image: Makefile, tools/samaltak-ctl`.

**When.** After a pull request is merged, when the image is to keep running (the in-image agent is told to; AgentInstructions). Hosted with a local checkout, update the checkout with git too, or the SourceFiler writes the image's next edits into the old files. Restart instead after VM changes, or when an update reports *partial* (installing stopped at an error: what was installed stays, the base commit does not move).

## Tests

`GitHubTestServer` (Tests-Net) is a fake GitHub over plain HTTP in the image: one repository in memory, the git data API and pulls, checking every request's headers. `GitHubClientTest` and `GitHubAccountTest` test the client and the account; `SourceFilerGitHubTest` (Tests-Tools) the store: one chunk changes and every other byte stays, new and removed files, extension files, two edits to one file, a failed commit, discard, a 3 MB file, which store is used, the token never printed. `SourceUpdateTest` (Tests-Tools) updates fixture classes the test files into the image between two commits of the fake GitHub: methods added, changed and removed, a new instance variable on a class with a live instance, a new class in a new package, a removed class, an extension file, VM and host files (reported, not applied), conflicts with the image and with the pending change set, `takeTheirs`, a head that does not compile (nothing applied), a dry run, the update command, new instance variables set as `initialize` sets them, and an image at 99cfe6d's parent updated across it (`String>>hash` refused as it depends on the VM's `stringHash`, applied with `force`). They run hosted and in the UEFI test boot (`UEFI_TESTS`); `SourceDirectoryStoreTest`, the local store, needs a writable directory and runs hosted only.
