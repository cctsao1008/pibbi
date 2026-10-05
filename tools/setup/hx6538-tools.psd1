@{
    SchemaVersion = 1

    Python = @{
        MinimumVersion = '3.8'
    }

    ArmGnuToolchain = @{
        Version = '13.2.Rel1'
        Archive = 'arm-gnu-toolchain-13.2.rel1-mingw-w64-i686-arm-none-eabi.zip'
        Directory = 'arm-gnu-toolchain-13.2.Rel1-mingw-w64-i686-arm-none-eabi'
        Url = 'https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-mingw-w64-i686-arm-none-eabi.zip'
        Sha256 = '51d933f00578aa28016c5e3c84f94403274ea7915539f8e56c13e2196437d18f'
    }

    WindowsBuildTools = @{
        PackageVersion = '4.4.1-3'
        MakeVersion = '4.4.1'
        Archive = 'xpack-windows-build-tools-4.4.1-3-win32-x64.zip'
        Directory = 'xpack-windows-build-tools-4.4.1-3'
        Url = 'https://github.com/xpack-dev-tools/windows-build-tools-xpack/releases/download/v4.4.1-3/xpack-windows-build-tools-4.4.1-3-win32-x64.zip'
        ShaUrl = 'https://github.com/xpack-dev-tools/windows-build-tools-xpack/releases/download/v4.4.1-3/xpack-windows-build-tools-4.4.1-3-win32-x64.zip.sha'
    }

    SscmaWe2 = @{
        Url = 'https://github.com/Seeed-Studio/sscma-example-we2.git'
        Track = '1.0.x'

        # Intentionally empty until pibbi establishes its first known-good HX6538 baseline.
        # Once the clean upstream build and Watcher smoke test pass, replace this with the
        # exact validated commit SHA and treat changes as explicit dependency upgrades.
        Commit = ''

        Directory = 'third_party\sscma-example-we2'
    }
}
