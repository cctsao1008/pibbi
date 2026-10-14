# pibbi ESP32-S3 Firmware

This pibbi-owned ESP-IDF project compiles the full Seeed factory firmware
implementation from third_party/SenseCAP-Watcher-Firmware without editing
its source checkout.

## Build and flash

From the pibbi repository root:

```powershell
.\tools\esp32s3\build.ps1
.\tools\esp32s3\flash.ps1 -Port COM31
.\tools\esp32s3\monitor.ps1 -Port COM31
```

The build wrapper selects this project by default (-Example pibbi). The
unmodified vendor application can still be built with -Example factory_firmware.
COM31 is the observed W1-A ESP32-S3 port on one Windows installation.

## Integration

- main/CMakeLists.txt compiles the original Seeed factory application sources.
- Only the upstream main.c translation unit remaps app_sensor_init at compile
  time to pibbi_app_sensor_init; no third_party source is modified.
- main/pibbi_startup.c first calls the original Seeed app_sensor_init, then
  starts pibbi's sensor service.
- components/pibbi_sensors reuses the Watcher BSP I2C bus (SDA GPIO47,
  SCL GPIO48) and maintains an inventory of Waveshare Environment Sensor HAT
  endpoints: 0x68, 0x76, 0x29, 0x53 and 0x59.
- Device-set changes publish PIBBI_SENSOR_PRESENCE_CHANGED via
  PIBBI_SENSOR_EVENTS; consumers can also use pibbi_sensors_get_presence().

The sensor presence event is an operational device inventory, not a sensor
measurement. Driver integration, observation transport and the LSMM adapter
are the next application features.

The factory Kconfig, default sdkconfig, partition layout and component
dependencies are mirrored to preserve upstream compatibility. Continue
using app-only flashing; keep nvsfactory and all credentials private.
