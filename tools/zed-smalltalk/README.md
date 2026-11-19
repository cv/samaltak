# Smalltalk for Zed

Highlights `.st` files, including Samaltak chunk files and Pharo Tonel files.

In Zed, run `zed: install dev extension` from the command palette and select
this `tools/zed-smalltalk` directory.

To regenerate the parser, run `npx --yes tree-sitter-cli@0.25.10 generate --abi 14`
from `grammar/`. Commit the regenerated files and update the grammar revision
in `extension.toml` to that commit.
