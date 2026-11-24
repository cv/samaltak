# Hosted bootstrap

A clean `make image` compiles the VM from `vm/gen`, runs the builder in the
checked-in `boot/seed.image`, then runs stage 2. `make runtime` builds the
`src/runtime.txt` subset. Image building needs the hosted File backend (SDL
build) but opens no window.

To renew the checked-in seed, build the boot profile, not the runtime or
stage-2 image:

```sh
make vm
tmp=$(mktemp -d)
PACKAGES=boot/packages.txt boot/build-image.sh src "$tmp/seed.image"
BOOT_IMAGE="$tmp/seed.image" tests/boot/fresh_seed_test.sh
```

Install the tested artifact as `boot/seed.image`. The default builder runs
in that image; `BOOT_IMAGE` selects another. The last positional argument
to `boot/build-image.sh` selects the VM executable if needed.

Seeded FFI sites contain only an immutable symbolic descriptor and an
initially nil binding token. The first call prepares the binding in that
VM, and snapshot restore revalidates VM-local tokens. Preparation does not
call back into image environment lookup or error reporting.
