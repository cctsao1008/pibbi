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


def remove_dead_static_function(data: str, name: str) -> str:
    """Remove a source-verified, unused file-local C function.

    Only a single-line static function declaration with a brace-delimited
    body ending at column zero is accepted. Refuse upstream drift.
    """
    pattern = (r"(?ms)^static[^;\n]*\b" + re.escape(name)
               + r"\s*\([^;]*?\)\s*\{.*?^\}\n?")
    updated, count = re.subn(pattern, "", data)
    if count != 1:
        raise RuntimeError(f"Expected one unused static C function {name}, got {count}")
    return updated


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

    # Source-grounded fixes from the 2026-10-14 full clean-build log.
    # All replacements are asserted against the pinned Seeed revision.
    if rel == "task_flow_engine/include/tf.h":
        fix("tf_module_mgmt_t *mgmt_handle;", "const tf_module_mgmt_t *mgmt_handle;", 1)
        fix("tf_module_mgmt_t *mgmt_handle);", "const tf_module_mgmt_t *mgmt_handle);", 1)
    elif rel == "task_flow_engine/include/tf_parse.h":
        fix("tf_module_mgmt_t *mgmt_handle;", "const tf_module_mgmt_t *mgmt_handle;", 1)
    elif rel == "task_flow_engine/src/tf.c":
        fix("tf_module_mgmt_t *mgmt_handle)", "const tf_module_mgmt_t *mgmt_handle)", 1)
    elif rel == "app/app_sensecraft.h":
        fix("static esp_err_t sensecraft_deviceinfo_get(struct sensecraft_deviceinfo *p_info);\n", "", 1)
        fix("char *p_module_name,", "const char *p_module_name,", 2)
        fix("char *taskflow_name,", "const char *taskflow_name,", 1)
    elif rel == "app/app_sensecraft.c":
        fix("static const char *TAG = \"sensecaft\";", "static esp_err_t sensecraft_deviceinfo_get(struct sensecraft_deviceinfo *p_info);\nstatic const char *TAG = \"sensecaft\";", 1)
        fix("char *p_module_name,", "const char *p_module_name,", 2)
        fix("char *taskflow_name,", "const char *taskflow_name,", 1)
        fix("char *p_err_module = NULL;", "const char *p_err_module = NULL;", 2)
    elif rel == "app/app_ota.h":
        fix("esp_partition_t *partition;", "const esp_partition_t *partition;", 1)
    elif rel == "app/app_device_info.h":
        fix("uint8_t *get_bt_mac();", "const uint8_t *get_bt_mac();", 1)
    elif rel == "app/app_device_info.c":
        fix("uint8_t *get_bt_mac()", "const uint8_t *get_bt_mac()", 1)
    elif rel == "data_defs.h":
        fix("char *fw_version;  //ESP32's firmware", "const char *fw_version;  //ESP32's firmware", 1)
    elif rel == "app/app_taskflow.c":
        fix("    char *p_module_name = NULL;", "    const char *p_module_name = NULL;", 2)
        fix("__taskflow_tid_get(char *p_task_flow,", "__taskflow_tid_get(const char *p_task_flow,", 1)
    elif rel == "task_flow_module/tf_module_uart_alarm.c":
        fix("    char *prompt = NULL;", "    const char *prompt = NULL;", 1)
        fix("free(tf_info.p_tf_name);", "free((void *)tf_info.p_tf_name);", 1)
    elif rel == "task_flow_module/tf_module_http_alarm.c":
        fix("free(tf_info.p_tf_name);", "free((void *)tf_info.p_tf_name);", 1)
    elif rel == "task_flow_module/tf_module_sensecraft_alarm.c":
        fix("free(tf_info.p_tf_name);", "free((void *)tf_info.p_tf_name);", 1)
    elif rel == "app/app_voice_interaction.c":
        fix("            // No need for break", "            __attribute__((fallthrough)); // FINISH intentionally performs STOP cleanup", 1)
    elif rel == "app/app_rgb.c":
        fix("static caller_context_t caller_contexts[STACK_SIZE];\n", "", 1)
        fix("static int stack_top = -1; // Empty stack\n", "", 1)
        fix("static esp_timer_handle_t rgb_timer_handle;\n", "", 1)
        fix("static uint8_t flag = 0;\n", "", 1)

    # Remove compiler-identified dead locals and preserve side effects.
    if rel == "app/app_wifi.c":
        fix("static EventGroupHandle_t __wifi_event_group;\n", "", 1)
        fix("    uint32_t ulNotificationValue;\n", "", 1)
    elif rel == "app/app_device_info.c":
        fix("static StackType_t *app_device_info_task_stack = NULL;\n", "", 1)
        fix("static StaticTask_t app_device_info_task_buffer;\n", "", 1)
        fix("static sscma_client_info_t *g_himax_info;\n", "", 1)
        fix("    uint8_t code[8];\n", "", 1)
        fix("    uint32_t cnt = 0;\n", "", 1)
    elif rel == "app/app_cmd.c":
        fix("    int write_len = 0;\n", "", 1)
        fix("static int vi_ctrl_cmd(int argc, char **argv)\n{\n    char file[32] = {0};\n    char file_wav[32] = {0};\n    int record_time = 0;", "static int vi_ctrl_cmd(int argc, char **argv)\n{\n    char file[32] = {0};", 1)
    elif rel == "app/app_ota.c":
        fix("            int num_orders = cJSON_GetArraySize(orders);\n", "", 1)
    elif rel == "app/app_audio_player.c":
        fix("            UBaseType_t available_bytes = 0;\n", "", 1)
    elif rel == "view/ui_manager/ui_events.c":
        fix("static struct view_data_setting_switch set_sw;\n", "", 1)
        fix("static struct view_data_emoticon_display emo_disp;\n", "", 1)
        fix("    lv_coord_t x = lv_obj_get_x(knob);\n", "", 1)
        fix("    lv_coord_t y = lv_obj_get_y(knob);\n", "", 1)
        fix("void ui_event_emoticonok(lv_event_t * e)\n{\n    lv_event_code_t event_code = lv_event_get_code(e);\n    lv_obj_t * target = lv_event_get_target(e);", "void ui_event_emoticonok(lv_event_t * e)\n{\n    lv_event_code_t event_code = lv_event_get_code(e);", 1)
        fix("    lv_obj_t *push2talk_panel_child;\n", "", 1)
    elif rel == "view/view.c":
        fix("static uint8_t system_mode = 0;     // 0: normal; 1: sleep; 2: standby\n", "", 1)
        fix("static uint32_t inactive_time = 0;\n", "", 1)
        fix("                static bool load_flag;\n", "", 1)
        fix("                lv_timer_t *timer = lv_timer_create(toggle_image_visibility, 500, NULL);", "                lv_timer_create(toggle_image_visibility, 500, NULL);", 1)
        fix("                int * rgb_st = (int *)event_data;\n", "", 1)
        fix("                int *sw = (int *)event_data;\n", "", 1)
    elif rel == "task_flow_module/tf_module_local_alarm.c":
        fix("        FILE *fp = NULL;\n", "", 1)
        fix("        esp_err_t status = ESP_FAIL;\n", "", 1)
    elif rel == "task_flow_module/tf_module_alarm_trigger.c":
        fix("        uint8_t *p_audio = NULL;\n", "", 1)
    elif rel == "task_flow_module/tf_module_img_analyzer.c":
        fix("                uint8_t *p_audio = NULL;\n", "", 1)
    elif rel == "task_flow_module/tf_module_ai_camera.c":
        fix("    bool condition_check = true;\n", "", 1)

    # Keep the effects of ESP-IDF GOTO error macros, use returned errors.
    if rel == "app/app_ble.c":
        fix("    const ble_uuid_t *uuid;\n", "", 1)
        fix("        uuid = ctxt->chr->uuid;\n", "", 2)
        fix("    const char *name;\n", "", 1)
    elif rel == "app/app_sensecraft.c":
        fix("            char *p_topic = NULL;\n", "", 1)
        fix("                p_topic = event->topic;\n", "", 1)
        fix("static esp_err_t sensecraft_deviceinfo_get(struct sensecraft_deviceinfo *p_info)\n{\n    esp_err_t ret = ESP_OK;", "static esp_err_t sensecraft_deviceinfo_get(struct sensecraft_deviceinfo *p_info)\n{", 1)
    elif rel == "app/app_voice_interaction.c":
        fix("static int __audio_stream_http_connect(struct app_voice_interaction *p_vi)\n{\n    esp_err_t  ret = ESP_OK;", "static int __audio_stream_http_connect(struct app_voice_interaction *p_vi)\n{", 1)
        fix("            size_t bin_offset  = 0;\n", "", 1)
    elif rel == "task_flow_module/tf_module_http_alarm.c":
        fix("static void __event_handler(void *handler_args, esp_event_base_t base, int32_t id, void *p_event_data)\n{\n    esp_err_t ret = ESP_OK;", "static void __event_handler(void *handler_args, esp_event_base_t base, int32_t id, void *p_event_data)\n{", 1)
        fix("static void http_alarm_task(void *p_arg)\n{\n    int ret = 0;\n    tf_module_http_alarm_t *p_module_ins = (tf_module_http_alarm_t *)p_arg;\n    struct tf_module_http_alarm_params *p_params = &p_module_ins->params;", "static void http_alarm_task(void *p_arg)\n{\n    int ret = 0;\n    tf_module_http_alarm_t *p_module_ins = (tf_module_http_alarm_t *)p_arg;", 1)
        fix("err:\n    if(p_module_ins->task_handle ) {", "err:\n    ESP_LOGE(TAG, \"HTTP alarm init failed: %s\", esp_err_to_name(ret));\n    if(p_module_ins->task_handle ) {", 1)
    elif rel == "task_flow_engine/src/tf.c":
        fix("esp_err_t tf_engine_flow_set(const char *p_str, size_t len)\n{\n    assert(gp_engine);\n    esp_err_t ret = ESP_OK;", "esp_err_t tf_engine_flow_set(const char *p_str, size_t len)\n{\n    assert(gp_engine);", 1)
        fix("esp_err_t tf_module_register(const char *p_name,\n                             const char *p_desc,\n                             const char *p_version,\n                             const tf_module_mgmt_t *mgmt_handle)\n{\n    assert(gp_engine);\n    esp_err_t ret = ESP_OK;", "esp_err_t tf_module_register(const char *p_name,\n                             const char *p_desc,\n                             const char *p_version,\n                             const tf_module_mgmt_t *mgmt_handle)\n{\n    assert(gp_engine);", 1)
    elif rel == "task_flow_module/tf_module_alarm_trigger.c":
        fix("err:\n    if (p_module_ins->sem_handle) {", "err:\n    ESP_LOGE(TAG, \"alarm trigger init failed: %s\", esp_err_to_name(ret));\n    if (p_module_ins->sem_handle) {", 1)
    elif rel == "task_flow_module/tf_module_sensecraft_alarm.c":
        fix("err:\n    if (p_module_ins->sem_handle) {", "err:\n    ESP_LOGE(TAG, \"SenseCraft alarm init failed: %s\", esp_err_to_name(ret));\n    if (p_module_ins->sem_handle) {", 1)
    elif rel == "task_flow_module/tf_module_img_analyzer.c":
        fix("err:\n    if(p_module_ins->task_handle ) {", "err:\n    ESP_LOGE(TAG, \"image analyzer init failed: %s\", esp_err_to_name(ret));\n    if(p_module_ins->task_handle ) {", 1)
    elif rel == "task_flow_module/tf_module_uart_alarm.c":
        # ESP_GOTO_ON_ERROR writes ret, while err: is outside the first-instance if.
        # Keep ret in the enclosing function scope so logging can read it.
        fix("    p_module_ins->module_base.ops = &__g_module_ops;\n\n    if (atomic_fetch_add(&g_ins_cnt, 1) == 0) {\n        // the 1st time instance, we should init the hardware\n        esp_err_t ret;",
            "    p_module_ins->module_base.ops = &__g_module_ops;\n    esp_err_t ret = ESP_OK;\n\n    if (atomic_fetch_add(&g_ins_cnt, 1) == 0) {\n        // the 1st time instance, we should init the hardware", 1)
        fix("err:\n    free(p_module_ins);", "err:\n    ESP_LOGE(TAG, \"UART alarm init failed: %s\", esp_err_to_name(ret));\n    free(p_module_ins);", 1)

    # Remove unused stub locals; propagate unregister result instead of losing it.
    if rel == "task_flow_module/tf_module_debug.c":
        fix("static int __start(void *p_module)\n{\n    tf_module_debug_t *p_module_ins = (tf_module_debug_t *)p_module;", "static int __start(void *p_module)\n{", 1)
        fix("static int __cfg(void *p_module, cJSON *p_json)\n{\n    tf_module_debug_t *p_module_ins = (tf_module_debug_t *)p_module;", "static int __cfg(void *p_module, cJSON *p_json)\n{", 1)
        fix("static int __msgs_pub_set(void *p_module, int output_index, int *p_evt_id, int num)\n{\n    tf_module_debug_t *p_module_ins = (tf_module_debug_t *)p_module;", "static int __msgs_pub_set(void *p_module, int output_index, int *p_evt_id, int num)\n{", 1)
        fix("    esp_err_t ret = tf_event_handler_unregister(p_module_ins->evt_id, __event_handler);\n    return 0;", "    return tf_event_handler_unregister(p_module_ins->evt_id, __event_handler);", 1)
        fix("    tf_module_debug_t *p_module_ins = (tf_module_debug_t *)handler_args;\n", "", 1)
    elif rel == "task_flow_module/tf_module_local_alarm.c":
        fix("static int __start(void *p_module)\n{\n    tf_module_local_alarm_t *p_module_ins = (tf_module_local_alarm_t *)p_module;", "static int __start(void *p_module)\n{", 1)
        fix("static int __msgs_pub_set(void *p_module, int output_index, int *p_evt_id, int num)\n{\n    tf_module_local_alarm_t *p_module_ins = (tf_module_local_alarm_t *)p_module;", "static int __msgs_pub_set(void *p_module, int output_index, int *p_evt_id, int num)\n{", 1)
    elif rel == "task_flow_module/tf_module_http_alarm.c":
        fix("static int __start(void *p_module)\n{\n    tf_module_http_alarm_t *p_module_ins = (tf_module_http_alarm_t *)p_module;", "static int __start(void *p_module)\n{", 1)
        fix("static int __msgs_pub_set(void *p_module, int output_index, int *p_evt_id, int num)\n{\n    tf_module_http_alarm_t *p_module_ins = (tf_module_http_alarm_t *)p_module;", "static int __msgs_pub_set(void *p_module, int output_index, int *p_evt_id, int num)\n{", 1)
    elif rel == "task_flow_module/tf_module_uart_alarm.c":
        fix("static int __start(void *p_module)\n{\n    tf_module_uart_alarm_t *p_module_ins = (tf_module_uart_alarm_t *)p_module;", "static int __start(void *p_module)\n{", 1)
        fix("static int __msgs_pub_set(void *p_module, int output_index, int *p_evt_id, int num)\n{\n    tf_module_uart_alarm_t *p_module_ins = (tf_module_uart_alarm_t *)p_module;", "static int __msgs_pub_set(void *p_module, int output_index, int *p_evt_id, int num)\n{", 1)
    elif rel == "task_flow_module/tf_module_sensecraft_alarm.c":
        fix("static int __start(void *p_module)\n{\n    tf_module_sensecraft_alarm_t *p_module_ins = (tf_module_sensecraft_alarm_t *)p_module;", "static int __start(void *p_module)\n{", 1)
        fix("static int __msgs_pub_set(void *p_module, int output_index, int *p_evt_id, int num)\n{\n    tf_module_sensecraft_alarm_t *p_module_ins = (tf_module_sensecraft_alarm_t *)p_module;", "static int __msgs_pub_set(void *p_module, int output_index, int *p_evt_id, int num)\n{", 1)
    elif rel == "task_flow_module/tf_module_alarm_trigger.c":
        fix("static int __start(void *p_module)\n{\n    tf_module_alarm_trigger_t *p_module_ins = (tf_module_alarm_trigger_t *)p_module;", "static int __start(void *p_module)\n{", 1)
    elif rel == "task_flow_module/tf_module_img_analyzer.c":
        fix("static int __start(void *p_module)\n{\n    char *p_token = NULL, *p_host = NULL;\n\n    tf_module_img_analyzer_t *p_module_ins = (tf_module_img_analyzer_t *)p_module;\n    struct tf_module_img_analyzer_params *p_params = &p_module_ins->params;", "static int __start(void *p_module)\n{\n    char *p_token = NULL, *p_host = NULL;\n\n    tf_module_img_analyzer_t *p_module_ins = (tf_module_img_analyzer_t *)p_module;", 1)
    elif rel == "task_flow_module/tf_module_ai_camera.c":
        fix("static bool __condition_check_whith_filter(tf_module_ai_camera_t *p_module_ins, struct tf_data_inference_info *p_inference)\n{\n    struct tf_module_ai_camera_params *p_params = &p_module_ins->params;", "static bool __condition_check_whith_filter(tf_module_ai_camera_t *p_module_ins, struct tf_data_inference_info *p_inference)\n{", 1)

    # Remove file-local dead implementations diagnosed as unused by GCC.
    if rel == "app/app_wifi.c":
        data = remove_dead_static_function(data, "min")
        changes.append("Removed dead static function min")
        data = remove_dead_static_function(data, "__wifi_shutdown")
        changes.append("Removed dead static function __wifi_shutdown")
    elif rel == "app/app_device_info.c":
        data = remove_dead_static_function(data, "__safely_set_devicecfg_uint_value")
        changes.append("Removed dead static function __safely_set_devicecfg_uint_value")
        data = remove_dead_static_function(data, "__safely_set_devicecfg_str_value")
        changes.append("Removed dead static function __safely_set_devicecfg_str_value")
    elif rel == "app/app_taskflow.c":
        data = remove_dead_static_function(data, "__taskflow_reload_from_spiffs")
        changes.append("Removed dead static function __taskflow_reload_from_spiffs")
    elif rel == "app/app_voice_interaction.c":
        data = remove_dead_static_function(data, "__data_lock")
        changes.append("Removed dead static function __data_lock")
        data = remove_dead_static_function(data, "__data_unlock")
        changes.append("Removed dead static function __data_unlock")
    elif rel == "view/ui_manager/pm.c":
        data = remove_dead_static_function(data, "printGroup")
        changes.append("Removed dead static function printGroup")
    elif rel == "view/view_image_preview.c":
        data = remove_dead_static_function(data, "jpeg_decoder_deinit")
        changes.append("Removed dead static function jpeg_decoder_deinit")
    elif rel == "util/util.c":
        data = remove_dead_static_function(data, "WriteNameToBuffer")
        changes.append("Removed dead static function WriteNameToBuffer")

    # esp_event_post_to's fifth argument is size_t. NULL is a pointer and
    # generates -Wint-conversion; the intended payload length is zero.
    if rel.endswith(".c"):
        def event_fix(m: re.Match[str]) -> str:
            call = m.group(0)
            return re.sub(r",\s*NULL,\s*NULL,\s*(?=pdMS_TO_TICKS\s*\()",
                          ", NULL, 0, ", call)

        previous = data
        data = re.sub(r"\besp_event_post_to\s*\(.*?\);",
                      event_fix, data, flags=re.DOTALL)
        if data != previous:
            changes.append("zero-length ESP event payloads use size 0")

    # R3 compiler-diagnostic fixes: source-asserted; no warnings are suppressed.
    if rel == "app/app_cmd.c":
        fix("    char *url = NULL;", "    const char *url = NULL;", 1)
    elif rel == "app/app_ota.c":
        fix("esp_err_t app_ota_ai_model_download(char *url, int size_bytes)", "esp_err_t app_ota_ai_model_download(const char *url, int size_bytes)", 1)
        fix("esp_err_t app_ota_esp32_fw_download(char *url)", "esp_err_t app_ota_esp32_fw_download(const char *url)", 1)
        fix("esp_err_t app_ota_himax_fw_download(char *url)", "esp_err_t app_ota_himax_fw_download(const char *url)", 1)
    elif rel == "app/app_ota.h":
        fix("esp_err_t app_ota_ai_model_download(char *url, int size_bytes);", "esp_err_t app_ota_ai_model_download(const char *url, int size_bytes);", 1)
        fix("esp_err_t app_ota_esp32_fw_download(char *url);", "esp_err_t app_ota_esp32_fw_download(const char *url);", 1)
        fix("esp_err_t app_ota_himax_fw_download(char *url);", "esp_err_t app_ota_himax_fw_download(const char *url);", 1)
    elif rel == "app/app_device_info.c":
        fix("char *get_software_version(int caller)", "const char *get_software_version(int caller)", 1)
        fix("const uint8_t *get_bt_mac()", "const uint8_t *get_bt_mac(void)", 1)
    elif rel == "app/app_device_info.h":
        fix("char *get_software_version(int caller);", "const char *get_software_version(int caller);", 1)
        fix("const uint8_t *get_bt_mac();", "const uint8_t *get_bt_mac(void);", 1)
    elif rel == "view/ui_manager/ui_events.c":
        fix("    const uint8_t *bt_mac = retry_get_data(get_bt_mac, 0, MAX_RETRIES);", "    const uint8_t *bt_mac = get_bt_mac();", 1)
    elif rel == "app/app_sensecraft.c":
        fix("end:\n    free(url);\n    esp_http_client_close(client);", "end:\n    if (ret != ESP_OK) {\n        ESP_LOGE(TAG, \"SenseCraft HTTP request failed: %s\", esp_err_to_name(ret));\n    }\n    free(url);\n    esp_http_client_close(client);", 1)
        fix("    size_t len =0;\n", "", 1)
    elif rel == "app/app_wifi.c":
        fix("void wifi_scan(void)\n{\n    esp_err_t ret;", "void wifi_scan(void)\n{\n    esp_err_t ret = ESP_OK;", 1)
        fix("wifi_scan_end:\n    free(ap_info);", "wifi_scan_end:\n    if (ret != ESP_OK) {\n        ESP_LOGE(TAG, \"Wi-Fi scan failed: %s\", esp_err_to_name(ret));\n    }\n    free(ap_info);", 1)
    elif rel == "app/at_cmd.c":
        fix("    int time_flag = 0;\n", "", 1)
        fix("    struct view_data_wifi_st *p_cfg;\n", "", 1)
        fix("            static bool fist = true;\n", "", 1)
    elif rel == "view/ui_manager/animation.c":
        fix("static const char *TAG = \"animation_event\";\n", "", 1)
    elif rel == "view/view_alarm.c":
        fix("static lv_obj_t * ui_Page_test;\n", "", 1)
    elif rel == "view/ui_manager/pm.c":
        fix("static const char *TAG = \"PM_EVENT\";\n#define PM_PAGE_PRINTER (0)", "#define PM_PAGE_PRINTER (0)\n#if PM_PAGE_PRINTER\nstatic const char *TAG = \"PM_EVENT\";\n#endif", 1)
        fix("    static lv_obj_t * focused_obj;\n", "", 1)
        fix("        const char *group_obj_name = lv_obj_get_user_data(groupInfo->group[index]);\n", "", 1)
    elif rel == "app/app_taskflow.c":
        fix("    struct app_taskflow * p_taskflow = ( struct app_taskflow *)p_arg;\n    struct view_data_taskflow_status status;\n    bool need_report = false;\n    intmax_t tid = 0;\n    const char *p_module_name = NULL;\n    char err_msg[64];", "    struct view_data_taskflow_status status;\n    intmax_t tid = 0;", 1)
        fix("                    int engine_status = 0;\n                    struct view_data_taskflow_status status;\n", "                    int engine_status = 0;\n", 1)
    elif rel == "app/app_voice_interaction.c":
        fix("        ESP_LOGE(TAG, \"code is not number or not find\");\n        goto err;", "        ESP_LOGE(TAG, \"code is not number or not find\");\n        ret = ESP_ERR_INVALID_RESPONSE;\n        goto err;", 1)
        fix("        ESP_LOGE(TAG, \"data is not object\");\n        goto err;", "        ESP_LOGE(TAG, \"data is not object\");\n        ret = ESP_ERR_INVALID_RESPONSE;\n        goto err;", 1)
        fix("            if (result == NULL) {\n                ESP_LOGE(TAG, \"malloc failed\");\n                goto err;", "            if (result == NULL) {\n                ESP_LOGE(TAG, \"malloc failed\");\n                ret = ESP_ERR_NO_MEM;\n                goto err;", 1)
        fix("    if (p_json_root != NULL) {\n        cJSON_Delete(p_json_root);\n    }\n    return ESP_OK;\n}\n\nint app_vi_result_free", "    if (p_json_root != NULL) {\n        cJSON_Delete(p_json_root);\n    }\n    return ret;\n}\n\nint app_vi_result_free", 1)
    elif rel == "task_flow_engine/src/tf_parse.c":
        fix("err:\n    if (p_json_root != NULL)", "err:\n    if (ret != ESP_OK) {\n        ESP_LOGE(TAG, \"Taskflow JSON parsing failed: %s\", esp_err_to_name(ret));\n    }\n    if (p_json_root != NULL)", 2)

    # The module-status callback has a disabled (#if 0) reporting branch.
    # Drop assignments only inside this callback, preserving other callbacks.
    if rel == "app/app_taskflow.c":
        start = data.index("static void __task_flow_module_status_cb(")
        end = data.index("static void __taskflow_task(", start)
        block = data[start:end]
        for item in ('        p_module_name = p_name;\n',
                     '        p_module_name = "unknown";\n'):
            if block.count(item) != 1:
                raise RuntimeError("R3 module-status callback source drift")
            block = block.replace(item, "")
        data = data[:start] + block + data[end:]
        changes.append("R3: removed dormant callback assignments")

    # Do not remove timings used by later view functions.
    if rel == "view/view_image_preview.c":
        start = data.index("int view_image_preview_flush(")
        end = data.index("void view_image_black_flush(", start)
        block = data[start:end]
        for item, count in (
            ("    int64_t start = 0, end = 0;\n", 1),
            ("    start = esp_timer_get_time();\n", 2),
            ("    end = esp_timer_get_time();\n", 2),
        ):
            if block.count(item) != count:
                raise RuntimeError("R3 image-preview timing source drift")
            block = block.replace(item, "")
        data = data[:start] + block + data[end:]
        changes.append("R3: removed unused image-preview timings")

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
            decoded = raw.decode("utf-8").replace("\r\n", "\n")
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
