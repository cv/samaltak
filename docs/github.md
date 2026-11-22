# GitHub

The image turns its own source changes into a branch, a commit and a pull request on GitHub through the REST API, with no files, processes or git: hosted, and on UEFI over the Smalltalk TLS client (docs/tls.md).

## Pieces (System-Net, layer 0; Tools)

- **GitHubAccount** (`GitHubAccount default`): repository (`owner/name`), baseBranch (`main`), branchPrefix (`agent/`), apiURL, and a token held in memory only (erased before every snapshot and quit, never printed). The host sets it with the `github-config` control command.
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

## Tests

`GitHubTestServer` (Tests-Net) is a fake GitHub over plain HTTP in the image: one repository in memory, the git data API and pulls, checking every request's headers. `GitHubClientTest` and `GitHubAccountTest` test the client and the account; `SourceFilerGitHubTest` (Tests-Tools) the store: one chunk changes and every other byte stays, new and removed files, extension files, two edits to one file, a failed commit, discard, a 3 MB file, which store is used, the token never printed. They run hosted and in the UEFI test boot (`UEFI_TESTS`; the local directory test is skipped there).
