#!/bin/bash -e

CAMERA_URL=${1}
if [ -z "${CAMERA_URL}" ]; then
    echo "No url parameter"
    exit 1
fi
RECORDINGS_DIR=${2}
if [ -z "${RECORDINGS_DIR}" ]; then
    echo "No recordings dir parameter"
    exit 1
fi

# create directories for the next week
for ((i = 0; i <= 7; i++))
do
    mkdir -vp ${RECORDINGS_DIR}/`date +%Y_%m_%d -d "+${i} day"`/
done

# start recording
# -segment_clocktime_offset 1 -write_empty_segments 1
exec ffmpeg -nostdin -nostats -i ${CAMERA_URL} -metadata title="" -c copy -an -flags +global_header -f segment -segment_time 900 -segment_atclocktime 1 -reset_timestamps 1 -segment_format mp4 -strftime 1 -y ${RECORDINGS_DIR}/%Y_%m_%d/%s_%Y-%m-%d_%H-%M-%S.mp4
