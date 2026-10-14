#!/usr/bin/env python3
"""Reproducible warning fixes for pinned external ESP-IDF components.

Copy just the affected source files to pibbi's ignored component overlay.
Do not change original third_party/ or managed_components/ content.
"""
from __future__ import annotations
import argparse
from pathlib import Path


def patch_exact(text: str, before: str, after: str, count: int = 1) -> str:
    found = text.count(before)
    if found != count:
        raise RuntimeError(
            f"Component drift: expected {count}, found {found} copies of "
            f"{before[:90]!r}"
        )
    return text.replace(before, after)


def patch_lvgl(text: str) -> str:
    text = patch_exact(
        text,
        "    BaseType_t res;\n#if CONFIG_LVGL_PORT_TASK_STACK_ALLOC_EXTERNAL",
        "#if CONFIG_LVGL_PORT_TASK_STACK_ALLOC_EXTERNAL",
    )
    text = patch_exact(
        text, "#else\n    if (cfg->task_affinity < 0)",
        "#else\n    BaseType_t res;\n    if (cfg->task_affinity < 0)",
    )
    text = patch_exact(
        text,
        "    uint16_t touchpad_x[1] = { 0 };\n"
        "    uint16_t touchpad_y[1] = { 0 };\n"
        "    uint16_t touchpad_strength[1] = { 0 };\n"
        "    uint8_t touchpad_cnt = 0;",
        "    esp_lcd_touch_point_data_t touchpad_point[1] = {0};\n"
        "    uint8_t touchpad_cnt = 0;",
    )
    text = patch_exact(
        text,
        "    bool touchpad_pressed = esp_lcd_touch_get_coordinates("
        "touch_ctx->handle, touchpad_x, touchpad_y, "
        "touchpad_strength, &touchpad_cnt, 1);",
        "    const esp_err_t touch_err = esp_lcd_touch_get_data(\n"
        "        touch_ctx->handle, touchpad_point, &touchpad_cnt, 1);\n"
        "    const bool touchpad_pressed = (touch_err == ESP_OK && touchpad_cnt > 0);",
    )
    for before, after in (
        ("touchpad_strength[0]", "touchpad_point[0].strength"),
        ("touchpad_x[0]", "touchpad_point[0].x"),
        ("touchpad_y[0]", "touchpad_point[0].y"),
    ):
        text = patch_exact(text, before, after)
    return text


def patch_sscma(text: str) -> str:
    return patch_exact(
        text,
        "    BaseType_t res;\n    sscma_client_handle_t client = NULL;",
        "#ifndef CONFIG_SSCMA_PROCESS_TASK_STACK_ALLOC_EXTERNAL\n"
        "    BaseType_t res;\n#endif\n"
        "    sscma_client_handle_t client = NULL;",
    )


def patch_audio(text: str) -> str:
    # FreeRTOS xTaskCreatePinnedToCore accepts a nullable TaskHandle_t*.
    return patch_exact(text, "        (TaskHandle_t * const)  NULL,", "        NULL,")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--watcher", required=True, type=Path)
    parser.add_argument("--managed", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    sources = (
        ("esp_lvgl_port", args.watcher / "components" / "esp_lvgl_port"
         / "esp_lvgl_port.c", "esp_lvgl_port.c", patch_lvgl),
        ("sscma_client", args.watcher / "components" / "sscma_client"
         / "src" / "sscma_client_ops.c", "sscma_client_ops.c", patch_sscma),
        ("chmorgan__esp-audio-player",
         args.managed / "chmorgan__esp-audio-player" / "audio_player.cpp",
         "audio_player.cpp", patch_audio),
    )
    for name, source, filename, correct in sources:
        source = source.resolve()
        if not source.is_file():
            raise RuntimeError(f"Missing pinned component source: {source}")
        corrected = correct(source.read_text(encoding="utf-8").replace("\r\n", "\n"))
        output = args.output.resolve() / name / filename
        output.parent.mkdir(parents=True, exist_ok=True)
        if not output.exists() or output.read_text(encoding="utf-8") != corrected:
            output.write_text(corrected, encoding="utf-8", newline="\n")
        print(f"pibbi patched component source: {name}/{filename}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
