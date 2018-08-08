#!/usr/bin/python
import os
import sys
import datetime
from supervisor.childutils import listener
from supervisor import childutils
from contextlib import contextmanager
import json
from pymediainfo import MediaInfo

g_ticks = -1
g_recordings_tree = {}

def write_stderr(s):
    sys.stderr.write(s)
    sys.stderr.flush()

@contextmanager
def cd(newdir):
    prevdir = os.getcwd()
    os.chdir(newdir)
    try:
        yield
    finally:
        os.chdir(prevdir)

def list_files(directory):
    files_list = []
    for root, directories, filenames in os.walk(directory):
        for filename in filenames:
            files_list.append(os.path.join(root, filename))

    return files_list

def get_percent_used(directory):
    st = os.statvfs(directory)
    free = st.f_bavail * st.f_frsize
    total = st.f_blocks * st.f_frsize
    used = (st.f_blocks - st.f_bavail) * st.f_frsize

    return used * 100 / total

def create_new_videos_dirs():
    website_cam_prefix = os.environ["WEBSITE_CAM_PREFIX"]

    for i in range(1, int(os.environ["CAM_COUNT"]) + 1):
        for j in range(0, 7):
            str_date = (datetime.date.today() + datetime.timedelta(days=j)).strftime('%Y_%m_%d')
            dir_path = os.path.join(os.environ["VIDEO_DIR"], "recordings", website_cam_prefix + str(i), str_date)
            if not os.path.isdir(dir_path):
                os.mkdir(dir_path)

def cleanup_drive_space():
    website_cam_prefix = os.environ["WEBSITE_CAM_PREFIX"]

    while True:
        # check the new space percent
        space_percent = int(get_percent_used(os.environ["VIDEO_DIR"]))
        if space_percent <= int(os.environ["MAX_SPACE_PERCENT"]):
            break

        # remove one video from each camera
        for i in range(1, int(os.environ["CAM_COUNT"]) + 1):
            files_list = list_files(os.path.join(os.environ["VIDEO_DIR"], "recordings", website_cam_prefix + str(i)))
            if len(files_list) > 0:
                os.remove(min(files_list))

def create_videos_list():
    website_cam_prefix = os.environ["WEBSITE_CAM_PREFIX"]

    with cd(os.environ["VIDEO_DIR"]):
        global g_recordings_tree

        # load the recordings tree
        if len(g_recordings_tree) <= 0:
            try:
                with open(os.environ["H5STREAM_INSTALL_DIR"] + "/www/recordings.json") as f:
                    g_recordings_tree = json.load(f)["cameras"]
            except Exception:
                pass

        #TODO numele astora lowest/highest sau smallest/biggest
        lowest_timestamp = 0
        biggest_timestamp = 0

        for i in range(1, int(os.environ["CAM_COUNT"]) + 1):
            camera_name = website_cam_prefix + str(i)

            if camera_name not in g_recordings_tree:
                # add the camera
                g_recordings_tree[camera_name] = {"name": "\"" + os.environ["CAM" + str(i) + "_NAME"] + "\"", "files": []}

            camera_files_tree = g_recordings_tree[camera_name]["files"]
            for root, directories, file_names in os.walk(os.path.join("recordings", camera_name)):
                for file_name in file_names:
                    file_path = os.path.join(root, file_name)

                    # find if this file was already added
                    rec_file = None
                    for f in camera_files_tree:
                        if file_path == f["path"]:
                            rec_file = f
                            break

                    # if file was found, check if it was modified since last time we read it
                    file_mtime = os.path.getmtime(file_path)
                    file_timestamp = 0
                    file_duration = None
                    media_check = True
                    if rec_file is not None:
                        file_timestamp = rec_file["timestamp"]
                        file_duration = rec_file["duration"]
                        if file_mtime == rec_file["mtime"]:
                            media_check = False

                    # check the info of the file
                    if media_check:
                        durations = [track.duration for track in MediaInfo.parse(file_path).tracks if track.track_type == "Video"]
                        if len(durations) > 0:
                            file_duration = int(durations[0])
                        if file_duration is None:
                            continue

                        file_timestamp = int(file_name.split("_")[0]) * 1000

                    # add or update the new file info
                    if rec_file is not None:
                        camera_files_tree.remove(rec_file)

                    # add the file
                    rec_file = {"path": file_path, "duration": file_duration, "timestamp": file_timestamp, "mtime": file_mtime}
                    camera_files_tree.append(rec_file)

                    # update the lowest and highest timestamp
                    if lowest_timestamp == 0 or lowest_timestamp > file_timestamp:
                        lowest_timestamp = file_timestamp
                    if biggest_timestamp == 0 or biggest_timestamp < file_timestamp + file_duration:
                        biggest_timestamp = file_timestamp + file_duration

        with open(os.environ["H5STREAM_INSTALL_DIR"] + "/www/recordings.json", "w") as f:
            f.write(json.dumps({"lowest_timestamp": lowest_timestamp, "biggest_timestamp": biggest_timestamp, "cameras": g_recordings_tree}, indent=4))

def process_tick60():
    global g_ticks
    g_ticks = (g_ticks + 1) % 10
    if g_ticks != 0:
        # do stuff only once every 10 minutes
        return

    # create new directories for the new days to store video files
    create_new_videos_dirs()

    # remove older videos if space available becomes small
    cleanup_drive_space()

    # create the list of videos to be loaded by the web server
    create_videos_list()

def process_event(msg_hdr, msg_payload):
    if msg_hdr["eventname"] == "TICK_60":
        process_tick60()

def main():
    process_tick60()

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
