# GitHub

The image turns its own source changes into a branch, a commit and a pull request on GitHub through the REST API, with no files, processes or git. The in-image agent (docs/agent.md) uses it: it changes code, runs the tests in the image, commits, and reports the pull request's URL; a person reviews and merges, and nothing in the image updates the base branch. It is for an image without a writable checkout of its sources (a copy of `build/samaltak.image` run elsewhere), or any image after `SourceFiler default useGitHub: true`.

## Flow

1. **Configure**, on the host: `samaltak-ctl open`, then `samaltak-ctl github-config --repo owner/repo --token-command 'cmd'`. One `github-config` request goes over the control connection: the repository (`owner/name`; that of the checkout's `origin` remote unless `--repo`), the base branch (`main` unless `--base`), the branch prefix (`agent/` unless `--prefix`), the API URL (`https://api.github.com` unless `--api-url`) and the token: the standard output of `--token-command` (run by `/bin/sh`), else the variable `--token-env` names, else `gh auth token` with `--from-gh`, else `$SAMALTAK_GITHUB_TOKEN`, else `$GITHUB_TOKEN`. The image answers its configuration with `hasToken`, never the token. `samaltak-ctl github-config` shows it, `--clear` forgets it all; a setting not given keeps its value, a bad one (a repository that is not `owner/name`, a base branch under the prefix) changes nothing and the command fails with the image's reason.
2. **Change**: compile, then write with the SourceFiler as always (below: a change set).
3. **Test** in the image: `FooTest run`.
4. **Commit**: `SourceFiler default commit: 'Area: what changed'` (a subject of at most ~72 characters, the pull request's title; optionally a short body after a blank line) answers a GitHubPullRequest; its url goes to the person who reviews it.

## Pieces (System-Net, layer 0; Compiler; Tools)

- **GitHubAccount** (`GitHubAccount default`, System-Net): repository (`owner/name`), baseBranch (`main`), branchPrefix (`agent/`), apiURL, and a token held in memory only (below). `isConfigured`: a repository and a token; `ownsBranch:`: under the prefix and not the base branch; `configure:` (the command's JSON names: `repository`, `baseBranch`, `branchPrefix`, `apiUrl`, `token`; a missing one keeps its value, a bad one changes nothing), `clear`. It registers the `github-config` control command: `{"cmd": "github-config", "repository": "owner/repo", "baseBranch": "main", "branchPrefix": "agent/", "token": "..."}`, `{"cmd": "github-config"}` (the configuration), `{"cmd": "github-config", "clear": true}`, each answering `{repository, baseBranch, branchPrefix, apiUrl, hasToken}`.
- **GitHubClient** (`GitHubClient on: anAccount`, System-Net): `get:`, `post:json:`, `patch:json:`, `put:json:`, `delete:` on API paths (`repositoryPath: 'git/blobs'`) → parsed JSON; one kept-alive HTTPClient connection; headers `Authorization: Bearer`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, `User-Agent`. A non-2xx status signals **GitHubError** (status, the API's message and errors, `METHOD /path`; never a header); so do a lost connection and a malformed body (status nil). It refuses, before sending, any write that would create, move or delete a branch outside `branchPrefix` or the base branch (git/refs, contents, merges, merging a pull request).
- **SourceFiler** (Compiler) writes single chunks (ChunkFile) through a store: **SourceDirectoryStore** (Compiler: the local `src/`, as before) or **GitHubSourceStore** (Tools: the repository's `src/`). It uses GitHub when the account is configured and there is no writable source directory, or after `useGitHub: true` (`false`: never). An application's runtime image has no Tools, so no GitHub store: its changes go to its directory as before.
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

**Never saved or shown.** It lives in the running image only: GitHubAccount is on the shutdown list and overwrites and drops every token before a snapshot or quit, its `printString` and the command's answer leave it out, GitHubError never carries a header. On the host it is in no argv (the token command and gh write it to samaltak-ctl's stdout pipe) and no log; it travels in the request's JSON only, over the control connection (127.0.0.1; it has no authentication: any local process that can reach the port could configure the account, as it could evaluate Smalltalk). After Save image or a restart the repository, the branches and a change set stay; the token must be sent again.

**Which token.** A fine-grained personal access token (github.com → Settings → Developer settings → Fine-grained tokens) for the one repository (Repository access: only select repositories) with Contents: read and write and Pull requests: read and write (Metadata: read comes with them), kept in a password manager and sent with its CLI:

    samaltak-ctl github-config --repo owner/repo --token-command 'pass show github/samaltak'

`gh auth token` (`--from-gh`) is gh's OAuth token: it reaches every repository the gh login can, so it is for trying things out, and samaltak-ctl says so. GitHubClient's ref guard keeps even a broad token off the base branch and every ref outside the prefix; branch protection on `main` is a second guard, GitHub's.

## The agent

AgentInstructions tells the agent: after changing code, run the affected test classes in the image, then `SourceFiler default commit: 'Area: what changed'` and report the pull request's url; never push to the base branch. Its `sourceState`, a line of the instructions, says where changes go in this image: to GitHub (repository, prefix, base), to a local checkout (the user commits with git), collected for GitHub without a token, or nowhere; in the last two the agent tells the user to run `samaltak-ctl github-config` on the host.

## Tests

`GitHubTestServer` (Tests-Net) is a fake GitHub over plain HTTP in the image: one repository in memory, the git data API and pulls, checking every request's headers. `GitHubClientTest` and `GitHubAccountTest` test the client and the account; `SourceFilerGitHubTest` (Tests-Tools) the store: one chunk changes and every other byte stays, new and removed files, extension files, two edits to one file, a failed commit, discard, a 3 MB file, which store is used, the token never printed; `SourceDirectoryStoreTest` the local store. `tests/tools/github_config_test.sh` (test-tools) checks the host side: the token from a command and from the environment, never printed, bad settings refused, absent from a snapshot and the VM's log. No test reaches GitHub.
