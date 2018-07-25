# SurvAce

A free and lightweight NVR-like surveillance system.

## Getting Started
SurvAce is a collection of free tools that work together to act as a video surveillance system. SurvAce is only the software part. The hardware part can be any surveillance camera that streams h264 encoded video via RTSP stream.
SurvAce does the following:
- record videos in 15 minutes chunks;
- rotate the recorded video files (remove the old ones to make room for new ones) when the partition where they are stored reaches a certain percent of occupation;
- live view the camera streams;
- parallel view of recorded footage for any period of time;
- multiplatform interaction; the gui is entirely browser based (written in html 5, js and css) and it works on Google Chrome (desktop and Android);
- low CPU and RAM usage;
- support for h264 video RTSP streams;
- high availability and fast response.

### Prerequisites
The supported operating system is Ubuntu 16.04. It might work on higher versions of Ubuntu, but I haven't tested. The constraints of the operating system are given by the tools that SurvAce is using.

The install script makes most of the preparements and installations. The only software that needs to be installed beforehand is `Google Chrome` browser which is used to operate SurvAce.

### Installing
Clone this repo or download and unzip it in a directory of your choice. Navigate into terminal to that directory and make the install script executable:

```
chmod +x install.sh
```
Run the install.
```
./install.sh
```
The install will start and the promp will quickly block saying that you now have to press `Enter` key and you will be presented with a small config script in `nano` that you'll have to edit with your desired surveillance configuration (see below).

After finishing the edit, press `Ctrl-O` to save your changes and `Ctrl-X` to leave nano.

At this point the script will start installing every piece of software that it needs. It will use `sudo` commands to install the software system wide, so it will ask for the sudo password at some point.

When the install finishes the system is ready to be used.

## Configuration
##### VIDEO_DIR
The directory where you want your recordings saved. The directory can be any filesystem directory where files and folders can be created (directory mapped to a local hard drive, usb stick, or mapped to a network share). So you're not limited to storing footage on the local system.

In this directory SurvAce will create a new directory, `recordings`, where it will store the recorded footage for each camera.

##### MAX_SPACE_PERCENT
This should be a number from 1 to 99 that will indicate the maximum percent of hard drive space that will be used for video recordings. SurvAce will look at the maximum occupied space on the partition where **VIDEO_DIR** is located and, if it reaches the specified percent, it will start deleting old video files until the spaces occupied drops under that value.

Depending on how big the partition is, I recommend a maximum value of 90.

##### CAM_COUNT
This is the number of cameras that you want to add to SurvAce. For each of these cameras, you'll need to add a pair of **CAMX_URL** and **CAMX_NAME** settings, where `X` is the index of the camera starting with 1.

##### CAMX_URL
The URL of the camera stream. This should be an RTSP uri of the video stream for that camera. In order to find the RTSP stream for your particular camera, you'll have to consult your camera's manual.
In order to check that the URL is correct, try to open it in `vlc` (with vlc opened, go to `Menu->Media->Open Network Stream...`, paste the url in the text area field and hit play). If you're seeing the stream correctly, then you can safely put it in the SurvAce config.

##### CAMX_NAME
A name for the camera. It's not used at the moment.

## Adding a new camera to an already configured system
In order to add a new camera to the system, you'll have to run the install again and add your camera in the config at the start of the installation process. This could mean that your system will be down (recording and live viewing) for a couple of seconds (10-20 seconds) during which time the old SurvAce processes are stopped, the new configuration is installed and the processes are restarted.

## How to use
Accessing `http://<ip_of_SurvAce_machine>:8001/` in Google Chrome browser will open a directory listing with various files among which there are two html files: `live_view.html` and `recordings.html`:
- `live_view.html` allows to view your configured cameras' video streams in real time. It is a simple page with a grid that contains the video player for each of your configured camera streams. The grid automatically resizes to fill as much as possible of the available display space while keeping all video players at the same size (no wonky one camera bigger that the others). You can view the live video of a particular camera in fullscreen text to the native functionality of the browser's video player.
- `recordings.html` allows to browse through the recorded videos. This page has sliders to select day, hour, minute and seconds, play and pause buttons and the grid with the video players for each camera. All the video players are synchronized and, when played, they display the video from each camera for the exact moment that you selected. This way you can view at the same time from all the cameras what happened at that specific time. Each player also allows scrolling through the video and will synchronize all the other players. So you can scroll through the footage either using the sliders or the seek bar on the video players. Each video player allows to fullscreen or download that particular video file.

## How does it work
SurvAce uses different tools to achieve all the features of a surveillance system.

#### Live555 proxy server
Live555 proxy is a server for proxying different kind of AV streams. SurvAce uses it to proxy the cameras' streams to the other tools that SurvAce uses. This approach was chosen in order to not overload the network link to the cameras. This way only a single connection to the cameras is used and network bandwidth is kept at a minimum.

Check more about Live555 proxy server on [Live555 proxy server's web page](http://www.live555.com/proxyServer/).

#### FFmpeg
FFmpeg is a complete, cross-platform solution to record, convert and stream audio and video. SurvAce uses FFmpeg to capture the RTSP streams and record them to the hard drive. This is one of the core tools of SurvAce. Without it's powerful AV capabilities this project would have been hard to develop.

Check more about FFmpeg on [FFmpeg's web page](https://www.ffmpeg.org/).

#### H5stream
H5stream is a webserver developed by linkingvision that streams RTMP and RTSP to web browsers. H5stream receives the RTSP streams and packs them in WebRTC that the browser can then use to display the videos. It doesn't use any transcoding or heavy processing, so the overhead is very small. Usually, live viewing is way under 1 second latency (about 400-600ms).

Besides this very important functionality, SurvAce also uses h5stream for it's webserver capability. The live and recordings view pages are hosted by it.

Check more about h5stream on [h5stream's web page](https://linkingvision.com/product-h5stream/).

#### Supervisor
Supervisor is a tool that monitors and controls UNIX processes. SurvAce uses Supervisor to monitor the tools and scripts that do the heavy lifting.

Check more about Supervisor on [supervisor's web page](http://supervisord.org/).

#### Python
Everybody knows Python. It's one of the nicest platform for scripting. SurvAce uses Python for a couple of monitoring and helper scripts. Also Supervisor is implemented in Python.

#### HTML 5
The gui for operating SurvAce is implemented in HTML 5. This makes SurvAce platform independed working on both desktop and mobile.

#### Other + performance
**Low network usage** is achieved by using live555 proxy to only open one connection to each camera keeping the bandwidth to a lowest. This allows you to use cheaper 10/100T network switches for connecting your cameras even if the cameras are set to send very high quality 1080p 30FPS video streams.

**Low CPU usage** is achieved by the fact that no video stream is transcoded. FFmpeg saves the streams directly to the filesystem. H5stream just packs the streams for WebRTC. Live555 proxy only serves duplicated streams to multiple clients without any additional procesing. No heavy processing is needed.
Each FFmpeg process stays at 0.5-2% maximum. Each live555 proxy process stays at 1-3%. H5stream stays at about 5% and will increase for each live view page opened with about 10-20% for a 2 camera system.

**Low memory usage**: FFmpeg 30MB, live555 proxy 5MB, h5stream 100-200MB depending on usage.

All of these should make SurvAce run on a low end one core 2GB of ram computer with no problem.

**Low live view latency** achieved by h5stream using WebRTC which has very low latency natively, about 500ms.

## How to take it for a spin
You can start playing with SurvAce even if you don't have a physical surveillance camera. The things that you need should already be available for the most of people:
- spare PC, or a virtual machine on your current computer that you'll use to install Ubuntu;
- Android mobile phone that you'll use to install [IP Webcam](https://play.google.com/store/apps/details?id=com.pas.webcam) or other similar app that can emulate a rtsp capable webcam on your phone.

###### Install Ubuntu
Get it from [here](http://releases.ubuntu.com/16.04/) and install it on your spare PC or on your virtual machine. You can create a virtual machine by using VMware or VirtualBox. Just make sure that the network adapter is set to `bridged`, so your virtual machine will see your network directly.
You could create a new partition that you can use just for storing the recordings. 10-20GB should suffice.

###### Setup camera app
I recommend IP Webcam because it does the job right.

Connect your Android phone to your network's WiFi and install IP Webcam.
After you open the app, go to `Video preferences->Video recording` and set video format to `MP4`. If, later on, the stream will not work, you can switch this to `MKV` (and press yes to download the codec for it).

Go back to the first screen and scroll down and press `Start server`. The live view will be displayed along with a couple of buttons and some info. On the bottom middle there are some links for http and https where you can view and interact with the app in a web browser. We'll not be using that. Instead, note the http link and construct the following link:`rtsp://<ip_displayed_on_the_app>:<port_displayed_on_the_app>/h264_noaudio.sdp`. This will be our link to the video stream. In order to test that it works, with the app opened and started, run vlc and paste the link. If the video is displayed correctly, then you're good to go.

###### Install SurvAce
Follow the install procedure to install SurvAce on the Ubuntu system. In the config part, edit the config with one camera and the link you constructed above.
```
VIDEO_DIR=<your_directory_of_choice>
MAX_SPACE_PERCENT=90
CAM_COUNT=1
CAM1_URL='<your_constructed_url>'
CAM1_NAME=test
```
Make sure that the Ubuntu machine and your Android phone are on the same network.

###### Have fun
After the install is finished you should now have a fully functional SurvAce system running on your Ubuntu machine. Navigate in Chrome to `http://<ubuntu_machine_ip>:8001/`. You should see a directory listing of filess and directories. You can click on `live_view.html` and you should see what your phone camera sees in real time. You can also click on `recordings.html`, but you'll have to wait for 15-30 minutes in order for Survace to record at least 1 full video file and be able to play it in the recordings page.

If everything works ok, you can now experiment with multiple cameras (phones), different camera settings etc.

## Limitations
##### No security access
At the moment, accessing SurvAce gui from the browser is not protected by any secury. It's basically free for all that have access to the network.

##### No audio
Because mp4 containers (the format of the video files saved by FFmpeg in Survace) do not support PCM audio (an audio encoding which is common in surveillance cameras) I choose not to save audio. Audio is not usually saved when doing surveillance anyway. If you want to also record audio, then you'll have to change and test the SurvAce scripts yourself.

##### Other
SurvAce is in an incipient stage. This makes it very rough and, perhaps, not so user friendly. The basic functionality is there, but it misses all the fancy features that other more user-oriented applications might have.

## FAQ
TODO

## TODO
- add some images to this readme;
- when installing stop all the survace related supervisor processes;
- it seems there is a problem when a maximum of 2 live view pages can be opened at a moment;
- add play speed modifier buttons.

## Motivation
I started working on this project when I realized that there was no free lightweight NVR software available for Linux/Unix. There are some free alternatives, but most of them do heavy transcoding from h264, thus a very high CPU load.

Having some good scripting and programming skills (my background is C/C++ developer, but I tackled many times bash and python scripting) I decided to take the matter into my own hands.

I start researching ways to implement each feature. I discovered that I can use FFmpeg for recording. I knew about Supervisor and that I will use it for monitoring the scripts.

I already chose that the GUI will be browser based because of the flexibility of using it on multiple platforms. I originally wanted SurvAce to work also in browsers other than Chrome, but I saw that each browser implements the video player differently and it would have meant a lot of extra time spent. Since Chrome has a wide adoption among users, I figured that it won't be a big issue if it works only on it.

The biggest issue was to make live viewing available in web browser. Web browsers do not support RTSP streams. So a solution based on WebRTC or Websockets would have been needed. After a long time of searching I came across [linkingvision](https://linkingvision.com/) and their product, `h5stream`, which does exactly what I needed: presenting a RTSP video stream through WebRTC or Websockets to the browser. Fortunately, they offer the server for free with a runtime limitation of one hour.

Having found all of these pieces it was only a matter of assembling and packaging them in something useful: **SurvAce**.

## Authors
* **Adrian Vlad** - scripts and html pages

See also the list of [contributors](https://github.com/adrian-vlad/SurvAce/contributors) who participated in this project.

## License
This project is licenced under GNU LESSER GENERAL PUBLIC LICENSE. Please see [COPYING](COPYING) and [COPYING.LESSER](COPYING.LESSER) for details.

I used this license because Live555 has the most restrictive license and that's LGPL.

Also, I wouldn't mind if you would give me a shout about how you use this software and what improvements did you make, especially if you're building something awesome with it.

In rest, go bananas. Feel free to deploy and share this software with as many people as possible.

## Acknowledgments
Thanks to all the people that developed these awesome tools:
- ffmpeg
- live555
- python
- h5stream
- ubuntu
- unix in general.

Thanks to everyone that has taken and will take an interest in this project by reading, downloading, testing, or providing feedback. This project lives through me, but mostly through the people that got in touch with SurvAce.

## Donation
I'm working on this project on my spare time, so, if you want to show your appreciation even more, feel free to give me a beer.

[![paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=M5W46KCX8DM6S)

Also, please support the creators of the aforementioned tools. They do a great job and deserve to be supported.
