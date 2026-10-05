# HX6538 Build Tools

This directory owns pibbi's host-side HX6538 build, image, and flashing workflow. Vendor source remains under `third_party/sscma-example-we2`.

## `build.ps1`

Builds the unmodified upstream HX6538 application with pibbi's pinned project-local toolchain.

Run from the pibbi repository root:

```powershell
.\tools\hx6538\build.ps1
```

The script does not require a previously activated shell. It temporarily prepends pibbi's pinned Arm GNU Toolchain and GNU Make directories to `PATH` for the build process only.

### Vendor-tree cleanliness

The upstream Seeed/Himax build system has an unusual but intentional side effect: when selected libraries are built from source, their generated `.a` archives are copied back into the tracked `EPII_CM55M_APP_S/prebuilt_libs/gnu/` directory. A normal clean build can therefore make the vendor Git checkout appear dirty even when no source was edited.

`build.ps1` treats vendor-tree cleanliness as an invariant:

- before the build, it repairs only unstaged modifications to tracked `prebuilt_libs/gnu/*.a` archives left by an earlier upstream build;
- any other vendor-tree modification stops the build;
- after a successful build, it restores only those known upstream-generated archive changes;
- unexpected changes are left intact and cause a failure so they can be inspected.

The script deliberately does **not** use Git `skip-worktree`, blanket `git reset --hard`, or a permanent local patch to the vendor SDK.

### Build evidence

A successful build copies the ELF and writes a manifest under:

```text
artifacts/hx6538/build/<sdk-short-sha>/
```

The manifest records the exact SDK commit, compiler version, GNU Make version, ELF size, and ELF SHA-256. `artifacts/` is intentionally ignored by Git.

The upstream SDK commit is not considered pibbi's pinned baseline until image generation, flashing, Watcher boot, and the basic camera/interface smoke test also pass.

### Options

Skip `make clean` only for local iteration:

```powershell
.\tools\hx6538\build.ps1 -NoClean
```

Preserve the upstream-generated tracked archive modifications only when investigating the vendor build system:

```powershell
.\tools\hx6538\build.ps1 -KeepVendorBuildArtifacts
```

Neither option should be used for a release or baseline-validation build.
