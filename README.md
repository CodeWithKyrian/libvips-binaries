# libvips-binaries

Pre-built libvips shared libraries for all major platforms.

Used by [phpmlkit/opal](https://github.com/phpmlkit/opal) (and potentially other projects)
to avoid requiring users to have libvips installed system-wide.

## License

Apache 2.0. See [LICENSE](LICENSE).

This repository is **heavily based on** [lovell/sharp-libvips](https://github.com/lovell/sharp-libvips),
the binary build system that powers [sharp](https://sharp.pixelplumbing.com/).
We adapted their build scripts for our own release pipeline — huge thanks to Lovell Fuller
and the sharp team for their excellent work.

## Platforms

| Platform | Architecture  | Build method                         |
|----------|---------------|--------------------------------------|
| macOS    | arm64, x86_64 | Native (Clang + Homebrew deps)       |
| Linux    | x86_64, arm64 | Rocky Linux 8 Docker (glibc 2.28)    |
| Windows  | x64           | Official libvips Win64 SDK repackage |

## Usage

Trigger the workflow manually with a version number. The matrix builds for all
platforms in parallel, or you can select specific platforms. When `create_release`
is enabled, a GitHub Release is created with `.tar.gz` assets:

```
libvips-darwin-arm64v8.tar.gz
libvips-darwin-x64.tar.gz
libvips-linux-x64.tar.gz
libvips-linux-arm64v8.tar.gz
libvips-win-x64.tar.gz
```

## Build scripts

| Script           | Platform      | Notes                                                 |
|------------------|---------------|-------------------------------------------------------|
| `build.sh`       | All           | Dispatcher — macOS natively, Linux/Windows via Docker |
| `build/posix.sh` | macOS + Linux | Full source build with static dependency linking      |
| `build/win.sh`   | Windows       | Downloads official libvips release, repackages        |

All build scripts are derived from [lovell/sharp-libvips](https://github.com/lovell/sharp-libvips)
under the Apache 2.0 license.
