#!/bin/bash
#sudo raspi-config nonint do_rpi_connect 1
#sudo raspi-config nonint do_wayland W1

sudo raspi-config nonint do_configure_keyboard us
sudo raspi-config nonint do_blanking 1
sudo raspi-config nonint do_squeekboard S3
sudo raspi-config nonint do_wifi_country US
echo "usb_max_current_enable=1" | sudo tee -a sudo tee -a /boot/firmware/config.txt
echo "https://nimble.dupage88.net/kiosk" | sudo tee /boot/firmware/fullpageos.txt
sudo apt update;
sudo apt upgrade -y;
sudo apt install -y openjdk-17-jdk wget unzip unattended-upgrades pcsc-tools pcscd libusb-dev libacsccid1 libnfc-dev;

cd ~/
wget -O /home/admin/tmp.zip "https://www.dupage88.net/site/public/files/?item=7738"
rm -rf /home/admin/jobrelease_MF -r
unzip /home/admin/tmp.zip
rsync -avc  /home/admin/jobrelease_MF/nfc /home/admin/

cat << 'EOF' |sudo tee /etc/X11/Xsession.d/99x11-common_start
xrandr --output DSI-2 --rotate left
xset -dpms; xset s off
xinput set-prop 6 "Coordinate Transformation Matrix" 0 -1 1 1 0 0 0 0 1
pactl set-default-sink alsa_output.usb-JOUNIVO_JOUNIVO_JV801_20200822-00.analog-stereo
pactl set-sink-mute @DEFAULT_SINK@ 0
pactl set-sink-volume @DEFAULT_SINK@ 100%
wget -O /home/admin/tmp.zip "https://www.dupage88.net/site/public/files/?item=7738"
rm -rf /home/admin/jobrelease_MF -r
unzip /home/admin/tmp.zip
rsync -avc  /home/admin/jobrelease_MF/nfc /home/admin/
java -jar /home/admin/nfc/nfc-reader-depends-0.5.1-SNAPSHOT.jar /home/admin/nfc/nimblesettings.properties &
exec $STARTUP
EOF

CHOICE=$(whiptail --title "System Control" --menu "Select an action:" 15 50 2 "reboot" "Restart the system." "poweroff" "Shut down and power off." 3>&1 1>&2 2>&3); EXIT_STATUS=$?; if [ $EXIT_STATUS -eq 0 >
#sudo reboot
