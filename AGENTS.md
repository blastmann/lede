# Repository Guidelines

## Project Structure & Module Organization
`package/` contains OpenWrt packages, usually one directory per package with a `Makefile`, optional `files/`, and numbered `patches/`. `target/linux/` defines board families, subtargets, image recipes, and kernel tweaks. `toolchain/` and `tools/` build host tooling and cross-compilers. Shared build logic lives in `include/` and top-level `rules.mk` / `Makefile`. Helper scripts are in `scripts/`. Build outputs land in `bin/targets/` and `bin/packages/`; treat them as generated artifacts.

## Build, Test, and Development Commands
Run the standard feed and config flow before building:

```bash
./scripts/feeds update -a
./scripts/feeds install -a
make menuconfig
make download -j8
make -j$(nproc)
```

Use `make defconfig` to refresh `.config` from Kconfig defaults. For first builds or hard failures, prefer `make -j1 V=s` for readable logs. Targeted checks are faster than full firmware builds, for example `make package/base-files/compile V=s` or `make package/feeds/nikki/luci-app-nikki/compile V=s`. Cleanup targets come from the root `Makefile`: `make clean`, `make targetclean`, and `make dirclean`.

## Coding Style & Naming Conventions
Follow existing OpenWrt style instead of reformatting files wholesale. Makefiles use tabs for recipe lines and uppercase metadata keys such as `PKG_NAME` and `PKG_RELEASE`. Package, target, and image filenames are lowercase with hyphens or board names, for example `package/kernel/r8125/` or `target/linux/armsr/armv8/target.mk`. Keep patch series ordered and prefixed numerically, such as `0001-...patch` or `200-...patch`.

## Testing Guidelines
There is no separate unit-test tree in this repo; validation is build-based. At minimum, run `make defconfig` after config changes and compile the affected package or target. For broad changes, build the relevant firmware image and confirm artifacts appear under `bin/targets/`. If you touch feed-integrated packages, mirror CI by compiling the affected feed package directly.

## Commit & Pull Request Guidelines
Recent history uses short, imperative subjects with prefixes like `ci:`. Keep commit messages focused and avoid mixing unrelated package and target work. The PR template forbids GitHub Actions-only commits and `users.noreply.github.com` author emails. PRs should explain scope, affected targets/packages, and the exact validation commands you ran; add screenshots only for LuCI or other UI changes.
