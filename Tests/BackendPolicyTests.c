#include <assert.h>
#include <stdio.h>
#include "CableDeXPolicy.h"

int main(void) {
    unsetenv("CABLEDEX_CLIPBOARD");
    unsetenv("CABLEDEX_AUDIO");
    assert(cabledex_control_allowed(SC_CONTROL_MSG_TYPE_INJECT_KEYCODE));
    assert(cabledex_control_allowed(SC_CONTROL_MSG_TYPE_INJECT_TEXT));
    assert(cabledex_control_allowed(SC_CONTROL_MSG_TYPE_INJECT_TOUCH_EVENT));
    assert(cabledex_control_allowed(SC_CONTROL_MSG_TYPE_INJECT_SCROLL_EVENT));
    assert(cabledex_control_allowed(SC_CONTROL_MSG_TYPE_SET_DISPLAY_POWER));
    assert(!cabledex_control_allowed(SC_CONTROL_MSG_TYPE_GET_CLIPBOARD));
    assert(!cabledex_control_allowed(SC_CONTROL_MSG_TYPE_SET_CLIPBOARD));
    assert(!cabledex_control_allowed(SC_CONTROL_MSG_TYPE_SCAN_FILE));
    assert(!cabledex_control_allowed(SC_CONTROL_MSG_TYPE_START_APP));
    assert(!cabledex_control_allowed(SC_CONTROL_MSG_TYPE_UHID_CREATE));
    assert(!cabledex_control_allowed(SC_CONTROL_MSG_TYPE_ROTATE_DEVICE));
    assert(!cabledex_control_allowed((enum sc_control_msg_type) 999));
    const char *server = "/bundle/Tools/scrcpy-server";
    assert(cabledex_push_allowed(server, "/data/local/tmp/scrcpy-server.jar", server));
    assert(!cabledex_push_allowed("/tmp/untrusted.apk", "/data/local/tmp/scrcpy-server.jar", server));
    assert(!cabledex_push_allowed(server, "/sdcard/Download/server.jar", server));
    assert(!cabledex_push_allowed(server, "/data/local/tmp/../server.jar", server));
    assert(!cabledex_push_allowed(server, "/data/local/tmp/scrcpy-server.jar", NULL));
    setenv("CABLEDEX_CLIPBOARD", "1", 1);
    assert(cabledex_control_allowed(SC_CONTROL_MSG_TYPE_GET_CLIPBOARD));
    assert(cabledex_control_allowed(SC_CONTROL_MSG_TYPE_SET_CLIPBOARD));
    assert(!cabledex_control_allowed(SC_CONTROL_MSG_TYPE_SCAN_FILE));
    setenv("CABLEDEX_CLIPBOARD", "0", 1);
    assert(!cabledex_control_allowed(SC_CONTROL_MSG_TYPE_GET_CLIPBOARD));
    setenv("CABLEDEX_CLIPBOARD", "true", 1);
    assert(!cabledex_control_allowed(SC_CONTROL_MSG_TYPE_SET_CLIPBOARD));
    assert(!cabledex_feature_enabled("CABLEDEX_AUDIO"));
    setenv("CABLEDEX_AUDIO", "1", 1);
    assert(cabledex_feature_enabled("CABLEDEX_AUDIO"));
    setenv("CABLEDEX_AUDIO", "0", 1);
    assert(!cabledex_feature_enabled("CABLEDEX_AUDIO"));
    puts("Passed 25 compiled backend policy checks: display/input allowlist, explicit sharing gates and temporary-server-only raw push.");
}
