@{
    SchemaVersion = 1

    Python = @{
        MinimumVersion = '3.8'
    }

    EspIdf = @{
        Url       = 'https://github.com/espressif/esp-idf.git'
        Version   = 'v5.2.1'
        Commit    = 'a322e6bdad4b6675d4597fb2722eea2851ba88cb'
        Directory = 'third_party\esp-idf'
        Target    = 'esp32s3'
    }

    EspIdfTools = @{
        Directory = '.tools\esp-idf'

        # ESP-IDF officially supports rewriting GitHub release-asset downloads
        # through Espressif's download server via IDF_GITHUB_ASSETS. This is the
        # pibbi default because large toolchain archives were observed to be much
        # more reliable and significantly faster than direct GitHub downloads.
        GitHubAssetsHost = 'dl.espressif.com/github_assets'
    }

    WatcherFirmware = @{
        Url       = 'https://github.com/Seeed-Studio/SenseCAP-Watcher-Firmware.git'
        Track     = 'main'

        # Intentionally empty until one exact upstream revision has passed
        # build + flash + Watcher smoke testing on real hardware.
        Commit    = ''

        Directory = 'third_party\SenseCAP-Watcher-Firmware'
    }
}
