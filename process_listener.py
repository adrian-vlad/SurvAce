#!/usr/bin/python
import os
import sys
from supervisor.childutils import listener
from supervisor import childutils
from subprocess import call
import subprocess
import datetime

H5STREAM_TEST_FILE_URI = "rtsp://127.0.0.1:65001/live/test_file"
H5STREAM_SUPERVISOR_PROCESS_NAME = "survace_h5stream"

g_ticks = -1

def write_stderr(s):
    sys.stderr.write(s)
    sys.stderr.flush()
def log(s):
    write_stderr(str(datetime.datetime.today()) + " " + s + "\n")
def debug(s):
    log("[DEBUG] " + s)
def info(s):
    log("[INFO] " + s)
def err(s):
    log("[ERR] " + s)

def supervisor_restart(process_name):
    info("supervisorctl restarting " + process_name)
    with open(os.devnull, "w") as f:
        call(["supervisorctl", "restart", process_name], stdout=f, stderr=f)

def supervisor_group_restart(groupName):
    supervisor_restart(groupName + ":")

def restart_camera(camera_id):
    supervisor_group_restart(os.environ["SUPERVISOR_GROUP_CAM_PREFIX"] + str(camera_id))

def restart_h5stream():
    supervisor_restart(H5STREAM_SUPERVISOR_PROCESS_NAME)

def rtsp_stream_is_alive(stream_uri):
    openrtsp_path = os.environ["LIVE555_INSTALL_DIR"] + "/openRTSP"
    try:
        openrtsp_cmd = openrtsp_path + " -v -d 1 " + stream_uri + " 2> /dev/null | wc -l"
        debug("running '" + openrtsp_cmd + "'")
        out = subprocess.check_output(openrtsp_cmd, shell=True)
        if int(out) == 0:
            # stream does not work
            return False
    except Exception as e:
        write_stderr(str(e))
        return False

    return True

def process_state_fatal(payload):
    pheaders, pdata = childutils.eventdata(payload + "\n")
    groupName = pheaders["groupname"]

    # restart the whole group
    err("fatal " + groupName)
    supervisor_group_restart(groupName)

def process_tick5():
    global g_ticks
    g_ticks = (g_ticks + 1) % 2
    if g_ticks != 0:
        # do stuff only once every 10 seconds
        return

    # check if streams are alive
    for i in range(1, int(os.environ["CAM_COUNT"]) + 1):
        if not rtsp_stream_is_alive(os.environ["CAM" + str(i)+ "_LOCAL_URL"]):
            err("stream not live for " + os.environ["SUPERVISOR_GROUP_CAM_PREFIX"] + str(i))
            restart_camera(i)

def process_tick60():
    # check if h5stream is still streamming
    if not rtsp_stream_is_alive(H5STREAM_TEST_FILE_URI):
        err("h5stream not streamming")
        restart_h5stream()


def process_event(msg_hdr, msg_payload):
    if msg_hdr["eventname"] == "PROCESS_STATE_FATAL":
        process_state_fatal(msg_payload)
    if msg_hdr["eventname"] == "TICK_5":
        process_tick5()
    if msg_hdr["eventname"] == "TICK_60":
        process_tick60()

def main():
    while True:
        try:
            msg_hdr, msg_payload = listener.wait(sys.stdin, sys.stdout)

            if "eventname" in msg_hdr:
                process_event(msg_hdr, msg_payload)

            listener.ok(sys.stdout)
        except Exception as e:
            write_stderr(str(e))

if __name__ == '__main__':
    main()
