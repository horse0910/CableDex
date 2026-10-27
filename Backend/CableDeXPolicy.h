#ifndef CABLEDEX_POLICY_H
#define CABLEDEX_POLICY_H
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include "control_msg.h"

static inline bool
cabledex_feature_enabled(const char *name) {
    const char *value = getenv(name);
    return value && !strcmp(value, "1");
}

// Positive allowlist shared by production code and the compiled policy tests.
static inline bool
cabledex_control_allowed(enum sc_control_msg_type type) {
    switch (type) {
        case SC_CONTROL_MSG_TYPE_INJECT_KEYCODE:
        case SC_CONTROL_MSG_TYPE_INJECT_TEXT:
        case SC_CONTROL_MSG_TYPE_INJECT_TOUCH_EVENT:
        case SC_CONTROL_MSG_TYPE_INJECT_SCROLL_EVENT:
        case SC_CONTROL_MSG_TYPE_BACK_OR_SCREEN_ON:
        case SC_CONTROL_MSG_TYPE_SET_DISPLAY_POWER:
        case SC_CONTROL_MSG_TYPE_RESET_VIDEO:
            return true;
        case SC_CONTROL_MSG_TYPE_GET_CLIPBOARD:
        case SC_CONTROL_MSG_TYPE_SET_CLIPBOARD:
            return cabledex_feature_enabled("CABLEDEX_CLIPBOARD");
        default:
            return false;
    }
}

static inline bool
cabledex_push_allowed(const char *local, const char *remote, const char *verified_server) {
    return local && remote && verified_server
        && !strcmp(local, verified_server)
        && !strcmp(remote, "/data/local/tmp/scrcpy-server.jar");
}
#endif
