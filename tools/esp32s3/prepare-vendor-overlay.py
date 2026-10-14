#!/usr/bin/env python3
"""Reproducible, non-destructive Watcher source corrections for pibbi.

Copy upstream sources into an ignored repository-local overlay. The compiler
uses the copy; third_party/ is never edited. All semantic edits are guarded:
a source change that invalidates an expected snippet fails the build.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def replace_exact(text: str, before: str, after: str, count: int = 1) -> str:
    found = text.count(before)
    if found != count:
        raise RuntimeError(
            f"Upstream source drift: expected {count} copy/copies of "
            f"{before!r}, found {found}"
        )
    return text.replace(before, after)


def correct(rel: str, data: str) -> tuple[str, list[str]]:
    changes: list[str] = []

    def fix(before: str, after: str, count: int = 1) -> None:
        nonlocal data
        data = replace_exact(data, before, after, count)
        changes.append(f"{count} x {before[:72]!r}")

    if rel == "util/util.h":
        fix('#include "cJSON.h">', '#include "cJSON.h"')
    elif rel == "util/util.c":
        fix('#include "cJSON.h">', '#include "cJSON.h"')
    elif rel == "app/at_cmd.h":
        fix("#include <esp_event_loop.h>", "#include <esp_event.h>")
    elif rel == "app/app_taskflow.c":
        data, count = re.subn(r"\\[ \t]+(?=\r?\n)", r"\\", data)
        if count != 167:
            raise RuntimeError(f"Unexpected Task Flow escaped line count: {count}")
        changes.append(f"{count} escaped-line trailing whitespace fixes")
    elif rel == "view/ui/ui.c":
        # SquareLine Studio emits unused getter locals in event callbacks.
        data, count = re.subn(
            r"^[ \t]*lv_obj_t\s*\*\s*target\s*=\s*lv_event_get_target\(e\);[ \t]*\n",
            "", data, flags=re.MULTILINE,
        )
        if count != 91:
            raise RuntimeError(f"Unexpected generated unused target count: {count}")
        changes.append(f"{count} unused LVGL getter locals removed")
    elif rel == "app/app_time.c":
        fix('#include "sntp.h"\n', "")
        fix("sntp_init();", "esp_sntp_init();")
        fix("extern void sntp_stop(void);\n", "")
        fix("sntp_stop();", "esp_sntp_stop();")
        fix("sntp_setoperatingmode(", "esp_sntp_setoperatingmode(")
        fix("sntp_setservername(", "esp_sntp_setservername(", 2)
    elif rel == "app/app_ble.c":
        for name in (
            "DISP_ONLY", "DISP_YES_NO", "KEYBOARD_ONLY",
            "NO_IO", "KEYBOARD_DISP",
        ):
            data, count = re.subn(
                rf"^#define BLE_SM_IO_CAP_{name}[ \t]+\d+[ \t]*\n",
                "", data, flags=re.MULTILINE,
            )
            if count != 1:
                raise RuntimeError(f"Expected one duplicate BLE definition: {name}")
            changes.append(f"removed duplicate BLE_SM_IO_CAP_{name}")
    elif rel == "app/app_png.c":
        fix("#define EMOJI_HTTP_TIMEOUT_MS           30000\n", "")
        fix('cJSON_AddStringToObject(download_item, "size", size);',
            'cJSON_AddNumberToObject(download_item, "size", size);', 2)
    elif rel == "app/app_cmd.c":
        fix("struct arg_str *json;", "struct arg_lit *json;")
        fix("struct arg_rex0 *subcmd;", "struct arg_rex *subcmd;")
    elif rel == "app/at_cmd.c":
        fix("byte_array_to_hex_string(get_eui(), 8, (const char *)eui_rsp);",
            "byte_array_to_hex_string(get_eui(), 8, eui_rsp);")
        fix("byte_array_to_hex_string(get_bt_mac(), 6, (const char *)bt_mac_rsp);",
            "byte_array_to_hex_string(get_bt_mac(), 6, bt_mac_rsp);")
    elif rel == "task_flow_engine/src/tf.c":
        # Original code called the callback exactly when it was NULL.
        fix("if( module_status_cb == NULL ) {",
            "if( module_status_cb != NULL ) {")
    elif rel == "app/app_audio_player.c":
        fix("uint8_t  bits_per_sample,", "uint32_t bits_per_sample,")
        fix("p_audio_player->p_mp3_decode_buf, 0)",
            "(short *)p_audio_player->p_mp3_decode_buf, 0)")
        fix("MAX_NCHAN * MAX_NGRAN * MAX_NSAMP;",
            "MAX_NCHAN * MAX_NGRAN * MAX_NSAMP * sizeof(int16_t);")
    elif rel == "task_flow_module/tf_module_ai_camera.c":
        fix("memset(classes_dst, NULL,", "memset(classes_dst, 0,")
        fix("memset(p_module_ins->classes, NULL,", "memset(p_module_ins->classes, 0,")
        fix("classes_src[i] != NULL && i < CONFIG_MODEL_CLASSES_MAX_NUM",
            "i < CONFIG_MODEL_CLASSES_MAX_NUM && classes_src[i] != NULL")
    elif rel == "task_flow_module/tf_module_timer.c":
        fix("if(ret != ESP_OK) {\n        return NULL;\n    }",
            "if(ret != ESP_OK) {\n        return ret;\n    }")
    elif rel == "task_flow_module/tf_module_uart_alarm.c":
        fix("sscma_client_box_t *p_box =  &p_data->inference.p_data[i];",
            "sscma_client_box_t *p_box =  &((sscma_client_box_t *)p_data->inference.p_data)[i];")
        # The second instance is a classification, not a detection box.
        fix("sscma_client_class_t *p_class =  &p_data->inference.p_data[i];",
            "sscma_client_class_t *p_class =  &((sscma_client_class_t *)p_data->inference.p_data)[i];")
        fix("total_len +=  classes_cnt*10 + 4 + 1;",
            "total_len +=  classes_cnt*2 + 4 + 1;")
    elif rel == "view/view.c":
        fix("uint8_t *p_src =NULL;", "const lv_img_dsc_t *p_src = NULL;")
        fix("lv_img_set_src(ui_mainwifi , (void *)p_src);",
            "lv_img_set_src(ui_mainwifi, p_src);")
        fix("lv_slider_set_value(ui_vslider, (int32_t *)vol_value, LV_ANIM_OFF);",
            "lv_slider_set_value(ui_vslider, vol_value, LV_ANIM_OFF);")
        fix("view_alarm_off(task_st);",
            "view_alarm_off(task_st != NULL ? *task_st : 0);")
        fix("case 3:\n                            p_src = &ui_img_wifi_2_png;\n",
            "case 3:\n                            p_src = &ui_img_wifi_2_png;\n                            break;\n")
    elif rel == "view/ui_manager/ui_events.c":
        fix("uint8_t emoji_switch_scr = NULL;", "uint8_t emoji_switch_scr = 0;")
        fix("uint32_t emoji_user_data = NULL;", "uint32_t emoji_user_data = 0;")
        fix("g_guide_disable = retry_get_data((uint8_t* (*)(int))get_usage_guide, UI_CALLER, MAX_RETRIES);",
            "g_guide_disable = get_usage_guide(UI_CALLER);")
        fix("qrcode_content = (char *)retry_get_data((uint8_t* (*)(int))get_qrcode_content, UI_CALLER, MAX_RETRIES);",
            "qrcode_content = (char *)get_qrcode_content();")
        fix("retry_get_data((uint8_t* (*)(int))get_brightness, UI_CALLER, MAX_RETRIES);",
            "get_brightness(UI_CALLER);")
        fix("retry_get_data((uint8_t* (*)(int))get_sound, UI_CALLER, MAX_RETRIES);",
            "get_sound(UI_CALLER);")
        fix("const uint8_t *rgb_switch = retry_get_data((uint8_t* (*)(int))get_rgb_switch, UI_CALLER, MAX_RETRIES);",
            "int rgb_switch = get_rgb_switch(UI_CALLER);")
        fix("const uint8_t *ble_switch = retry_get_data((uint8_t* (*)(int))get_ble_switch, UI_CALLER, MAX_RETRIES);",
            "int ble_switch = get_ble_switch(UI_CALLER);")
        fix("g_screenoff_time = (int *)retry_get_data(get_screenoff_time, UI_CALLER, MAX_RETRIES);",
            "g_screenoff_time = get_screenoff_time(UI_CALLER);")
        fix("g_screenoff_switch = (int *)retry_get_data(get_screenoff_switch, UI_CALLER, MAX_RETRIES);",
            "g_screenoff_switch = get_screenoff_switch(UI_CALLER);")
        fix("const char *sw_version = (char *)retry_get_data((uint8_t* (*)(int))get_software_version, UI_CALLER, MAX_RETRIES);",
            "const char *sw_version = get_software_version(UI_CALLER);")
        fix("const char *himax_version = (char *)retry_get_data((uint8_t* (*)(int))get_himax_software_version, UI_CALLER, MAX_RETRIES);",
            "const char *himax_version = get_himax_software_version(UI_CALLER);")
    elif rel == "util/factory_info.h":
        # The factory NVS reader owns and fills heap buffers. Getter functions
        # continue to expose const char*, but the owned struct fields are mutable.
        for field in ("sn", "eui", "code", "device_key", "batchid",
                      "access_key", "ai_key", "device_control_key"):
            fix(f"const char *{field};", f"char *{field};")

    # esp_event_post_to's fifth argument is size_t. NULL is a pointer and
    # generates -Wint-conversion; the intended payload length is zero.
    if rel.endswith(".c"):
        def event_fix(m: re.Match[str]) -> str:
            call = m.group(0)
            return re.sub(r",\s*NULL,\s*NULL,\s*(?=pdMS_TO_TICKS\s*\()",
                          ", NULL, 0, ", call)

        data, n = re.subn(r"\besp_event_post_to\s*\(.*?\);",
                          lambda m: event_fix(m), data, flags=re.DOTALL)
        # Count changed calls rather than every existing event post.
        # Script remains deterministic even for upstream patches without matches.

    return data, changes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    source, output = args.source.resolve(), args.output.resolve()
    if source == output or source in output.parents or output in source.parents:
        raise RuntimeError("Source and output must be separate trees")

    changed = {}
    expected = set()
    for p in source.rglob("*"):
        if not p.is_file():
            continue
        rel = p.relative_to(source).as_posix()
        expected.add(rel)
        out = output / rel
        raw = p.read_bytes()
        if p.suffix in (".c", ".h"):
            decoded = raw.decode("utf-8")
            corrected, details = correct(rel, decoded)
            raw = corrected.encode("utf-8")
            if details:
                changed[rel] = details
        if not out.exists() or out.read_bytes() != raw:
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(raw)

    for p in output.rglob("*"):
        if p.is_file() and p.relative_to(output).as_posix() not in expected:
            p.unlink()

    print(f"pibbi vendor overlay prepared: {len(expected)} source files, "
          f"{len(changed)} files with guarded corrections")
    for rel, details in sorted(changed.items()):
        print(f"  {rel}: {', '.join(details)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
