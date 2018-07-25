#!/bin/bash -e

# defaults
SYSTEM_USER="survace"

SURVACE_INSTALL_DIR="/opt/survace/"
H5STREAM_INSTALL_DIR="/opt/h5stream/"
LIVE555_INSTALL_DIR="/opt/live555/"

HTTP_SERVER_PORT=8001
LOCAL_PROXY_RTSP_PORT_START=51230
SUPERVISOR_GROUP_CAM_PREFIX="cam"
WEBSITE_CAM_PREFIX="cam"

function announce_big
{
    echo
    echo "########################################################"
    echo "# "$1
    echo "########################################################"
}
function announce_small
{
    echo
    echo $1
    echo "--------------------------------------------------------"
}

function _conf_template_create()
{
    # prepare a template config
    touch variables

    # add user configurable variables
    echo "# Please edit/add the following configuration" >> variables
    echo "" >> variables
    echo "# directory where the recordings are stored" >> variables
    echo "# Edit to your preference" >> variables
    echo "VIDEO_DIR=${SURVACE_INSTALL_DIR}/recordings/" >> variables
    echo "" >> variables
    echo "# space limit in percent of the partition where the recordings are stored" >> variables
    echo "# that will trigger recordings rotation (removing old videos to have space for new ones)" >> variables
    echo "# Edit to your preference" >> variables
    echo "# Recomended: a percent smaller than 100 that will result in at least a couple of GB free" >> variables
    echo "MAX_SPACE_PERCENT=99" >> variables
    echo "" >> variables
    echo "# camera count and camera sources" >> variables
    echo "# Edit the number of cameras that you have and for each camera add a new variable like" >> variables
    echo "# CAMX_URL, CAMX_NAME where X is the id of the camera." >> variables
    echo "# Example: if you have 2 cameras, then you should add the following lines" >> variables
    echo "# CAM_COUNT=2" >> variables
    echo "# CAM1_URL='rtsp://10.0.0.5:554/stream1'" >> variables
    echo "# CAM1_NAME="front_camera"" >> variables
    echo "# CAM2_URL='rtsp://10.0.0.6:554/stream1'" >> variables
    echo "# CAM2_NAME='back_camera'" >> variables
    echo "CAM_COUNT=0" >> variables
    echo "" >> variables
    echo "# Do not edit the following configuration" >> variables
}

function conf_edit
{
    # TODO: primary (for recording) and secondary (for live viewing) streams

    # try to get the variables file from the installation dir
    if [ -f "${SURVACE_INSTALL_DIR}/variables" ]; then
        cp "${SURVACE_INSTALL_DIR}/variables" .
    else
        # try to get the variables file from a previous installation attempt
        if [ -f "${CWD}/variables" ]; then
            cp "${CWD}/variables" .
        else
            # no installation file found; create one
            _conf_template_create
        fi
    fi

    # let the user make the configuration
    read -n 1 -s -r -p "You need to edit your specific setup configuration. Press enter when ready" ; echo "..."
    nano variables

    # add non configurable variables
    if grep -qs "H5STREAM_INSTALL_DIR" variables; then
        sed -i "/H5STREAM_INSTALL_DIR/d" variables
    fi
    echo "H5STREAM_INSTALL_DIR=${H5STREAM_INSTALL_DIR}" >> variables

    if grep -qs "LIVE555_INSTALL_DIR" variables; then
        sed -i "/LIVE555_INSTALL_DIR/d" variables
    fi
    echo "LIVE555_INSTALL_DIR=${LIVE555_INSTALL_DIR}" >> variables

    if grep -qs "SUPERVISOR_GROUP_CAM_PREFIX" variables; then
        sed -i "/SUPERVISOR_GROUP_CAM_PREFIX/d" variables
    fi
    echo "SUPERVISOR_GROUP_CAM_PREFIX=${SUPERVISOR_GROUP_CAM_PREFIX}" >> variables

    if grep -qs "WEBSITE_CAM_PREFIX" variables; then
        sed -i "/WEBSITE_CAM_PREFIX/d" variables
    fi
    echo "WEBSITE_CAM_PREFIX=${WEBSITE_CAM_PREFIX}" >> variables

    # import the variables
    set -a
    source variables
    set +a

    for ((i = 1; i <= $CAM_COUNT; i++))
    do
        LOCAL_PROXY_RTSP_PORT=$((${LOCAL_PROXY_RTSP_PORT_START} + ${i}))
        LOCAL_URL="rtsp://localhost:${LOCAL_PROXY_RTSP_PORT}/proxyStream"

        if grep -qs "CAM${i}_LOCAL_URL" variables; then
            sed -i "/CAM${i}_LOCAL_URL/d" variables
        fi
        echo "CAM${i}_LOCAL_URL=${LOCAL_URL}" >> variables
    done

    echo "" >> variables

    # import the variables again
    set -a
    source variables
    set +a

    # validate the configuration
    if (( $MAX_SPACE_PERCENT <= 99 )); then :
    else
        echo "Error: MAX_SPACE_PERCENT bigger than 99"
        exit 1
    fi

    if (( $CAM_COUNT > 0 )); then :
    else
        echo "Error: CAM_COUNT must be bigger than 0"
        exit 1
    fi

    for ((i = 1; i <= $CAM_COUNT; i++))
    do
        _CAM_URL="CAM${i}_URL"
        _CAM_NAME="CAM${i}_NAME"
        if [ -z ${!_CAM_URL+x} ]; then
            echo "Error: ${_CAM_URL} is not set"
            exit 1
        fi
        if [ -z ${!_CAM_NAME+x} ]; then
            echo "Error: ${_CAM_NAME} is not set"
            exit 1
        fi
    done

    # copy the new variables file in the cwd
    cp variables "${CWD}/variables"
}

function install_ffmpeg
{
    sudo apt-get -y install ffmpeg
}

function install_python2.7
{
    sudo apt-get -y install python2.7
    sudo apt-get -y install python-pip
    sudo pip install --ignore-installed pymediainfo
}

function install_mediainfo
{
    sudo apt-get -y install mediainfo
}

function install_curl
{
    sudo apt-get -y install curl
}

function install_supervisor
{
    sudo apt-get -y install supervisor
}

function prepare_h5stream
{
    H5STREAM_BASE_URL="https://linkingvision.com/download/h5stream/"
    H5STREAM_TAR_NAME=`curl -s ${H5STREAM_BASE_URL} | python -c "import sys; import re; print('\n'.join(re.split('[\"<>]', sys.stdin.read())));" | grep "Ubuntu-16.04-64bit.tar.gz" | tail -n 1`

    # download the latest package
    wget $H5STREAM_BASE_URL/$H5STREAM_TAR_NAME

    # extract it
    mkdir h5stream
    tar -xf $H5STREAM_TAR_NAME -C h5stream --strip-components 1

    # remove all the html files
    rm h5stream/www/*.html
    # remove the old conf
    rm h5stream/conf/*
}

function prepare_live555
{
    # download the latest source archive
    LIVE555_BASE_URL="http://www.live555.com/liveMedia/public/"
    LIVE555_TAR_NAME="live555-latest.tar.gz"
    wget $LIVE555_BASE_URL/$LIVE555_TAR_NAME

    # extract it
    mkdir live
    tar -xf $LIVE555_TAR_NAME -C live --strip-components 1

    # prepare for write
    chmod -R +w live
    cd live

    # patch liveProxy code to increase it's buffer so it does not have any problems with big streams
    sed -i '/OutPacketBuffer::maxSize = 100000;/c \ \ OutPacketBuffer::maxSize = 10000000;' proxyServer/live555ProxyServer.cpp

    PLATFORM=linux-64bit

    # add port reuse flag
    sed -i '/^COMPILE_OPTS/ s/$/ -DALLOW_RTSP_SERVER_PORT_REUSE=1/' config.${PLATFORM}

    # compile
    ./genMakefiles ${PLATFORM}
    make
    cd ..
}

function conf_h5stream
{
    mkdir h5stream_conf

    # create the new h5stream conf file
    touch h5stream_conf/h5ss.conf

    # start writting the file
    echo "{" >> h5stream_conf/h5ss.conf
    echo " \"http\": {" >> h5stream_conf/h5ss.conf
    echo "  \"nHTTPPort\": ${HTTP_SERVER_PORT}," >> h5stream_conf/h5ss.conf
    echo "  \"nHTTPSPort\": 8443," >> h5stream_conf/h5ss.conf
    echo "  \"bAuth\": false" >> h5stream_conf/h5ss.conf
    echo " }," >> h5stream_conf/h5ss.conf
    echo " \"rtsp\": {" >> h5stream_conf/h5ss.conf
    echo "  \"bRTSPSink\": true," >> h5stream_conf/h5ss.conf
    echo "  \"nRTSPPort\": 65001," >> h5stream_conf/h5ss.conf
    echo "  \"nSSLPort\": 65002," >> h5stream_conf/h5ss.conf
    echo " }," >> h5stream_conf/h5ss.conf
    echo " \"rtmp\": {" >> h5stream_conf/h5ss.conf
    echo "  \"bRTMPSink\": false," >> h5stream_conf/h5ss.conf
    echo "  \"nRTMPPort\": 65003," >> h5stream_conf/h5ss.conf
    echo "  \"nSSLPort\": 65004," >> h5stream_conf/h5ss.conf
    echo " }," >> h5stream_conf/h5ss.conf
    echo " \"flv\": {" >> h5stream_conf/h5ss.conf
    echo "  \"bFLVSink\": false," >> h5stream_conf/h5ss.conf
    echo "  \"nFLVPort\": 65005," >> h5stream_conf/h5ss.conf
    echo "  \"nSSLPort\": 65006," >> h5stream_conf/h5ss.conf
    echo " }," >> h5stream_conf/h5ss.conf
    echo " \"webrtc\": {" >> h5stream_conf/h5ss.conf
    echo "  \"bWebRTCSink\": true" >> h5stream_conf/h5ss.conf
    echo " }," >> h5stream_conf/h5ss.conf
    echo " \"system\": {" >> h5stream_conf/h5ss.conf
    echo "  \"nLogType\": \"H5_LOG_DEBUG\"," >> h5stream_conf/h5ss.conf
    echo "  \"bConsoleLog\": true," >> h5stream_conf/h5ss.conf
    echo "  \"nServerThreadNum\": $((${CAM_COUNT} + 2))" >> h5stream_conf/h5ss.conf
    echo " }," >> h5stream_conf/h5ss.conf
    echo " \"source\": {" >> h5stream_conf/h5ss.conf
    echo "  \"nConnectType\": \"H5_ALWAYS\"," >> h5stream_conf/h5ss.conf
    echo "  \"nRTSPType\": \"H5_RTSP_TCP\"," >> h5stream_conf/h5ss.conf
    echo "  \"src\": [" >> h5stream_conf/h5ss.conf

    # add each camera
    for ((i = 1; i <= $CAM_COUNT; i++))
    do
        LOCAL_PROXY_RTSP_PORT=$((${LOCAL_PROXY_RTSP_PORT_START} + ${i}))
        LOCAL_URL="rtsp://localhost:${LOCAL_PROXY_RTSP_PORT}/proxyStream"

        echo "   {" >> h5stream_conf/h5ss.conf
        echo "    \"strName\": \"${WEBSITE_CAM_PREFIX}${i}\"," >> h5stream_conf/h5ss.conf
        echo "    \"strToken\": \"${WEBSITE_CAM_PREFIX}${i}\"," >> h5stream_conf/h5ss.conf
        echo "    \"nType\": \"H5_STREAM\"," >> h5stream_conf/h5ss.conf
        echo "    \"strUrl\": \"${LOCAL_URL}\"," >> h5stream_conf/h5ss.conf
        echo "    \"strUser\": \"\"," >> h5stream_conf/h5ss.conf
        echo "    \"strPasswd\": \"\"," >> h5stream_conf/h5ss.conf
        echo "    \"nConnectType\": \"H5_ALWAYS\"," >> h5stream_conf/h5ss.conf
        echo "    \"nRTSPType\": \"H5_RTSP_UDP\"" >> h5stream_conf/h5ss.conf
        echo "   }," >> h5stream_conf/h5ss.conf
    done

    # add the test file
    echo "   {" >> h5stream_conf/h5ss.conf
    echo "    \"strName\": \"test_file\"," >> h5stream_conf/h5ss.conf
    echo "    \"strToken\": \"test_file\"," >> h5stream_conf/h5ss.conf
    echo "    \"strUrl\": \"${H5STREAM_INSTALL_DIR}/www/stream_test_file.mp4\"," >> h5stream_conf/h5ss.conf
    echo "    \"nType\": \"H5_FILE\"," >> h5stream_conf/h5ss.conf
    echo "    \"nConnectType\": \"H5_ONDEMAND\"," >> h5stream_conf/h5ss.conf
    echo "    \"nRTSPType\": \"H5_RTSP_AUTO\"" >> h5stream_conf/h5ss.conf
    echo "   }," >> h5stream_conf/h5ss.conf

    echo "  ]" >> h5stream_conf/h5ss.conf
    echo " }" >> h5stream_conf/h5ss.conf
    echo "}" >> h5stream_conf/h5ss.conf
}

function conf_supervisord
{
    mkdir supervisor_conf

    # create conf for process listener
    conf_path="supervisor_conf/survace_process_listener.conf"
    touch ${conf_path}
    echo "[eventlistener:survace_process_listener]" >> ${conf_path}
    echo "command=$SURVACE_INSTALL_DIR/nice_and_drop.py root -5 /bin/bash -c \"set -a; source $SURVACE_INSTALL_DIR/variables; set +a; exec $SURVACE_INSTALL_DIR/process_listener.py\"" >> ${conf_path}
    echo "events=PROCESS_STATE_FATAL,TICK_5,TICK_60" >> ${conf_path}
    echo "buffer_size=100" >> ${conf_path}
    echo "umask=022" >> ${conf_path}
    echo "priority=-1" >> ${conf_path}
    echo "autostart=true" >> ${conf_path}
    echo "autorestart=true" >> ${conf_path}
    echo "stopsignal=INT" >> ${conf_path}
    echo "stopwaitsecs=2" >> ${conf_path}
    echo "stopasgroup=true" >> ${conf_path}
    echo "killasgroup=true" >> ${conf_path}
    echo "" >> ${conf_path}

    # create conf for interval listener
    conf_path="supervisor_conf/survace_interval_listener.conf"
    touch ${conf_path}
    echo "[eventlistener:survace_interval_listener]" >> ${conf_path}
    echo "command=$SURVACE_INSTALL_DIR/nice_and_drop.py $SYSTEM_USER -5 /bin/bash -c \"set -a; source $SURVACE_INSTALL_DIR/variables; set +a; exec $SURVACE_INSTALL_DIR/interval_listener.py\"" >> ${conf_path}
    echo "events=TICK_60" >> ${conf_path}
    echo "buffer_size=100" >> ${conf_path}
    echo "umask=022" >> ${conf_path}
    echo "priority=-1" >> ${conf_path}
    echo "autostart=true" >> ${conf_path}
    echo "autorestart=true" >> ${conf_path}
    echo "stopsignal=INT" >> ${conf_path}
    echo "stopwaitsecs=2" >> ${conf_path}
    echo "stopasgroup=true" >> ${conf_path}
    echo "killasgroup=true" >> ${conf_path}
    echo "" >> ${conf_path}

    # create conf for h5stream
    conf_path="supervisor_conf/survace_h5stream.conf"
    touch ${conf_path}
    echo "[program:survace_h5stream]" >> ${conf_path}
    echo "command=/bin/bash -c \"LD_LIBRARY_PATH=$H5STREAM_INSTALL_DIR/lib/:\$LD_LIBRARY_PATH exec $H5STREAM_INSTALL_DIR/h5ss\"" >> ${conf_path}
    echo "directory=$H5STREAM_INSTALL_DIR" >> ${conf_path}
    echo "umask=022" >> ${conf_path}
    echo "priority=999" >> ${conf_path}
    echo "autostart=true" >> ${conf_path}
    echo "autorestart=true" >> ${conf_path}
    echo "stopsignal=INT" >> ${conf_path}
    echo "stopwaitsecs=2" >> ${conf_path}
    echo "stopasgroup=true" >> ${conf_path}
    echo "killasgroup=true" >> ${conf_path}
    echo "user=$SYSTEM_USER" >> ${conf_path}
    echo "redirect_stderr=true" >> ${conf_path}
    echo "; TODO: separate log files. AUTO log files and their backups will be deleted when supervisord restarts." >> ${conf_path}
    echo "" >> ${conf_path}
    echo "[group:survace_h5stream]" >> ${conf_path}
    echo "programs=survace_h5stream" >> ${conf_path}
    echo "priority=999" >> ${conf_path}
    echo "" >> ${conf_path}

    # create conf for each camera
    for ((i = 1; i <= $CAM_COUNT; i++))
    do
        _CAM_URL="CAM${i}_URL"
        REMOTE_URL=${!_CAM_URL}
        LOCAL_PROXY_RTSP_PORT=$((${LOCAL_PROXY_RTSP_PORT_START} + ${i}))
        LOCAL_URL="rtsp://localhost:${LOCAL_PROXY_RTSP_PORT}/proxyStream"
        RECORDINGS_DIR="${VIDEO_DIR}/recordings/${WEBSITE_CAM_PREFIX}${i}/"

        conf_path="supervisor_conf/survace_${SUPERVISOR_GROUP_CAM_PREFIX}${i}.conf"
        touch ${conf_path}

        # create conf for live55 proxy
        echo "[program:${SUPERVISOR_GROUP_CAM_PREFIX}${i}_live555proxy]" >> ${conf_path}
        echo "command=$SURVACE_INSTALL_DIR/nice_and_drop.py $SYSTEM_USER -5 $LIVE555_INSTALL_DIR/live555ProxyServer -p ${LOCAL_PROXY_RTSP_PORT} \"${REMOTE_URL}\"" >> ${conf_path}
        echo "umask=022" >> ${conf_path}
        echo "priority=10" >> ${conf_path}
        echo "autostart=true" >> ${conf_path}
        echo "autorestart=true" >> ${conf_path}
        echo "stopsignal=INT" >> ${conf_path}
        echo "stopwaitsecs=2" >> ${conf_path}
        echo "stopasgroup=true" >> ${conf_path}
        echo "killasgroup=true" >> ${conf_path}
        echo "redirect_stderr=true" >> ${conf_path}
        echo "; TODO: separate log files. AUTO log files and their backups will be deleted when supervisord restarts." >> ${conf_path}
        echo "" >> ${conf_path}

        # create conf for ffmpeg
        echo "[program:${SUPERVISOR_GROUP_CAM_PREFIX}${i}_ffmpeg]" >> ${conf_path}
        echo "command=$SURVACE_INSTALL_DIR/nice_and_drop.py $SYSTEM_USER -5 $SURVACE_INSTALL_DIR/cam_ffmpeg.sh \"${LOCAL_URL}\" \"${RECORDINGS_DIR}\"" >> ${conf_path}
        echo "umask=022" >> ${conf_path}
        echo "priority=11" >> ${conf_path}
        echo "autostart=true" >> ${conf_path}
        echo "autorestart=true" >> ${conf_path}
        echo "stopsignal=INT" >> ${conf_path}
        echo "stopwaitsecs=2" >> ${conf_path}
        echo "stopasgroup=true" >> ${conf_path}
        echo "killasgroup=true" >> ${conf_path}
        echo "redirect_stderr=true" >> ${conf_path}
        echo "; TODO: separate log files. AUTO log files and their backups will be deleted when supervisord restarts." >> ${conf_path}
        echo "" >> ${conf_path}

        # create the group for both
        echo "[group:${SUPERVISOR_GROUP_CAM_PREFIX}${i}]" >> ${conf_path}
        echo "programs=${SUPERVISOR_GROUP_CAM_PREFIX}${i}_live555proxy,${SUPERVISOR_GROUP_CAM_PREFIX}${i}_ffmpeg" >> ${conf_path}
        echo "priority=9" >> ${conf_path}
        echo "" >> ${conf_path}
    done
}

function install_all
{
    # stop supervisor
    sudo supervisorctl stop survace_process_listener || true
    sudo supervisorctl stop survace_interval_listener || true
    sudo supervisorctl stop survace_h5stream || true
    for ((i = 1; i <= $CAM_COUNT; i++))
    do
        sudo supervisorctl stop ${SUPERVISOR_GROUP_CAM_PREFIX}${i}: || true
    done

    # unmount the directories
    recordings_dir=`python -c "import os; print(os.path.realpath(\"$H5STREAM_INSTALL_DIR/www/recordings/\"))"`
    h5stream_temp_dir=`python -c "import os; print(os.path.realpath(\"$H5STREAM_INSTALL_DIR/www/hls/\"))"`
    if mount | grep -Fq "${recordings_dir}"; then
        sudo umount -fl "${recordings_dir}"
    fi
    if mount | grep -Fq "${h5stream_temp_dir}"; then
        sudo umount -fl "${h5stream_temp_dir}"
    fi

    sudo mkdir -p "${VIDEO_DIR}/recordings/"
    sudo chown -R $SYSTEM_USER:$SYSTEM_USER "${VIDEO_DIR}/recordings/"

    # add startup mounts
    sudo cp /etc/fstab /etc/fstab_`date +%Y_%m_%d_%H_%M_%S`.old
    if ! grep -Fq "${recordings_dir}" /etc/fstab; then
        sudo bash -c "echo \"\" >> /etc/fstab"
        sudo bash -c "echo \"${VIDEO_DIR}/recordings/ \"${recordings_dir}\" none bind,ro\" >> /etc/fstab"
    fi

    if ! grep -Fq "${h5stream_temp_dir}" /etc/fstab; then
        sudo bash -c "echo \"\" >> /etc/fstab"
        sudo bash -c "echo \"tmpfs \"${h5stream_temp_dir}\" tmpfs defaults,size=512m\" >> /etc/fstab"
    fi

    # save recordings.json
    cp ${H5STREAM_INSTALL_DIR}/www/recordings.json . &> /dev/null || true
    # h5stream
    if [ -d "${H5STREAM_INSTALL_DIR}" ]; then
        cd /opt/
        sudo rm -rf h5stream
        cd -
    fi
    sudo cp -r h5stream /opt/
    sudo cp h5stream_conf/h5ss.conf ${H5STREAM_INSTALL_DIR}/conf/
    sudo cp ${CWD}/*.html ${H5STREAM_INSTALL_DIR}/www/
    sudo cp ${CWD}/stream_test_file.mp4 ${H5STREAM_INSTALL_DIR}/www/
    sudo mkdir -p ${H5STREAM_INSTALL_DIR}/www/recordings/
    sudo mkdir -p ${H5STREAM_INSTALL_DIR}/www/hls/
    # restore recordings.json
    sudo cp recordings.json ${H5STREAM_INSTALL_DIR}/www/ &> /dev/null || true
    # own it
    sudo chown -R $SYSTEM_USER:$SYSTEM_USER ${H5STREAM_INSTALL_DIR}

    # live555 proxy
    if [ -d "${LIVE555_INSTALL_DIR}" ]; then
        cd /opt/
        sudo rm -rf live555
        cd -
    fi
    sudo mkdir -p ${LIVE555_INSTALL_DIR}
    sudo cp live/proxyServer/live555ProxyServer ${LIVE555_INSTALL_DIR}
    sudo cp live/testProgs/openRTSP ${LIVE555_INSTALL_DIR}
    sudo chown -R $SYSTEM_USER:$SYSTEM_USER ${LIVE555_INSTALL_DIR}

    # supervisor
    sudo rm -f /etc/supervisor/conf.d/survace_*.conf
    sudo cp supervisor_conf/* /etc/supervisor/conf.d/

    # survace scripts
    if [ -d "${SURVACE_INSTALL_DIR}" ]; then
        cd /opt/
        sudo rm -rf survace
        cd -
    fi
    sudo mkdir -p ${SURVACE_INSTALL_DIR}
    sudo cp variables ${SURVACE_INSTALL_DIR}
    sudo cp ${CWD}/nice_and_drop.py ${SURVACE_INSTALL_DIR}
    sudo cp ${CWD}/process_listener.py ${SURVACE_INSTALL_DIR}
    sudo cp ${CWD}/interval_listener.py ${SURVACE_INSTALL_DIR}
    sudo cp ${CWD}/cam_ffmpeg.sh ${SURVACE_INSTALL_DIR}
    sudo chmod +x ${SURVACE_INSTALL_DIR}/nice_and_drop.py
    sudo chmod +x ${SURVACE_INSTALL_DIR}/process_listener.py
    sudo chmod +x ${SURVACE_INSTALL_DIR}/interval_listener.py
    sudo chmod +x ${SURVACE_INSTALL_DIR}/cam_ffmpeg.sh
    sudo chown -R ${SYSTEM_USER}:${SYSTEM_USER} ${SURVACE_INSTALL_DIR}

    # create recordings directory
    sudo mkdir -pv ${VIDEO_DIR}

    # create directories for each camera
    for ((i = 1; i <= $CAM_COUNT; i++))
    do
        # create directories for each day for a week
        for ((j = 0; j <= 7; j++))
        do
            sudo mkdir -pv ${VIDEO_DIR}/${WEBSITE_CAM_PREFIX}${i}/`date +%Y_%m_%d -d "+${j} day"`/
        done
    done

    sudo chown -R ${SYSTEM_USER}:${SYSTEM_USER} ${VIDEO_DIR}

    # mount the directories
    sudo mount "${recordings_dir}"
    sudo mount "${h5stream_temp_dir}"

    # start supervisor
    sudo supervisorctl reread
    for ((i = 1; i <= $CAM_COUNT; i++))
    do
        sudo supervisorctl start ${SUPERVISOR_GROUP_CAM_PREFIX}${i}: || true
    done
    sudo supervisorctl start survace_h5stream || true
    sudo supervisorctl start survace_interval_listener || true
    sudo supervisorctl start survace_process_listener || true
}

function add_user
{
    sudo adduser $SYSTEM_USER --system --group --no-create-home
}


# create a temporary directory
CWD=`pwd`
TEMP_DIR=`mktemp -d`
cd $TEMP_DIR


# edit specific configuration
announce_big "Edit your specific configuration"
conf_edit

# install dependecy packages
announce_big "Installing dependency packages"

announce_small "Installing ffmpeg"
install_ffmpeg

announce_small "Installing python 2.7"
install_python2.7

announce_small "Installing mediainfo"
install_mediainfo

announce_small "Installing curl"
install_curl

announce_small "Installing supervisor"
install_supervisor


# prepare 3rd party packages
announce_big "Preparing 3rd party packages"

announce_small "Preparing h5stream"
prepare_h5stream

announce_small "Preparing live555"
prepare_live555


# create configuration files
announce_big "Creating configuration files"

announce_small "Creating h5stream configuration file"
conf_h5stream

announce_small "Creating supervisord configuration files"
conf_supervisord

# adding new user
announce_big "Adding new user"

announce_small "Adding user $SYSTEM_USER"
add_user

# install
announce_big "Installing SurvAce"
install_all

# cleanup
announce_big "Install finished. Enjoy!!!"
cd $CWD
rm -rf $TEMP_DIR

