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

## `image.ps1`

Generates the HX6538 flash image from the verified ELF artifact produced by `build.ps1`.

```powershell
.\tools\hx6538\image.ps1
```

The image wrapper intentionally does **not** run `we2_local_image_gen.exe` inside the live `third_party/sscma-example-we2` checkout. Instead it:

1. requires a clean SDK tree and a build manifest for the current SDK HEAD;
2. verifies the ELF SHA-256 against the build manifest;
3. exports `we2_image_gen_local/` from the exact SDK commit with `git archive`;
4. stages the verified ELF into that isolated copy using the upstream partition JSON;
5. runs the upstream Windows generator with `project_case1_blp_wlcsp.json`;
6. validates and copies `output.img` into a run-specific artifact directory;
7. records the SDK/build/generator/config input identity and exact output hash in `image-manifest.json`;
8. compares the result with prior manifests that used the same validated input set.

Artifacts are preserved per generation run:

```text
artifacts/hx6538/image/<sdk-short-sha>/<run-id>/
├─ output.img
├─ image-manifest.json
└─ image-gen.log
```

This is deliberate. During initial Watcher bring-up, two consecutive runs of the upstream secure-boot image flow used the same SDK revision, ELF, generator, project configuration, and partition configuration, produced the same image size, but produced different `output.img` SHA-256 values. The generator log shows that secure-boot content certificates are regenerated on each run; the exact varying certificate/signature field has not yet been isolated. Therefore pibbi does **not** currently assume byte-for-byte reproducibility of the signed image.

`image-manifest.json` records an `InputSetSha256` for the validated deterministic inputs and a separate SHA-256 for the exact generated image. If a previous run with the same input-set identity produced a different image hash, the wrapper reports `observed-nondeterministic` and emits a warning.

The operational rule is:

- treat the ELF/build inputs as reproducible evidence;
- treat each signed `output.img` as a run-specific artifact;
- never overwrite a previous signed image;
- flash and record the exact image manifest/SHA used on hardware;
- do not treat a different image SHA alone as evidence of a source-code change.

This isolates image-generation side effects and ignored temporary files from the vendor SDK checkout while preserving provenance back to the exact build ELF and SDK commit.

If image generation fails, the staging directory under `.tools/work/hx6538-image/` is preserved automatically for inspection. On success it is removed unless `-KeepWorkDir` is specified:

```powershell
.\tools\hx6538\image.ps1 -KeepWorkDir
```

The SDK commit should still not be pinned after image generation alone. Pinning waits until one exact generated image has been flashed to the Watcher and the boot/camera/interface smoke test has passed. The image manifest and image SHA used for that smoke test should be retained as part of the baseline evidence.
