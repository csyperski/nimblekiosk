#!/bin/bash

sudo systemctl enable ssh
sudo apt update && sudo apt upgrade -y
sudo apt install -y openjdk-17-jdk wget unzip unattended-upgrades pcsc-tools pcscd libusb-dev libacsccid1 libnfc-dev python3-pip openssh-server chromium 'libcanberra-gtk*' openbox unclutter xdotool pulseaudio-utils
sudo apt purge cups* magnus --autoremove -y
sudo usermod -a -G dialout "$USER"
sudo snap connect chromium:raw-usb
sudo nmcli device wifi connect "d88-guest"
echo "administrator ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/administrator-nopasswd && sudo chmod 0440 /etc/sudoers.d/administrator-nopasswd
echo -e "[Seat:*]\nautologin-user=administrator\nautologin-session=openbox" | sudo tee /etc/lightdm/lightdm.conf > /dev/null
tee ~/kiosk.sh > /dev/null << 'EOF'
#!/bin/bash
xset s off s noblank -dpms
sudo nmcli device wifi connect "d88-guest"
sudo snap connect chromium:raw-usb
pactl set-default-sink alsa_output.usb-JOUNIVO_JOUNIVO_JV801_20200822-00.analog-stereo
pactl set-sink-mute @DEFAULT_SINK@ 0
pactl set-sink-volume @DEFAULT_SINK@ 100%
#sleep 20
wget -O /home/administrator/tmp.zip "https://www.dupage88.net/site/public/files/?item=7738"
rm -rf /home/administrator/jobrelease_MF -r
unzip /home/administrator/tmp.zip
rsync -avc /home/administrator/jobrelease_MF/nfc /home/administrator/
cd nfc
java -jar /home/administrator/nfc/nfc-reader-depends-0.5.1-SNAPSHOT.jar /home/administrator/nfc/nimblesettings.properties &
exec chromium --no-first-run --disable-pinch --overscroll-history-navigation=0 --kiosk "https://nimble.dupage88.net/kiosk"
EOF
chmod +x ~/kiosk.sh
wget -O tmp.zip "https://www.dupage88.net/site/public/files/?item=7738"
unzip ~/tmp.zip
mv jobrelease_MF/nfc/ ~/nfc/
rm -rf tmp.zip jobrelease_MF # Added to clean up files from this section
mkdir -p /home/administrator/.config/openbox
echo -e "/home/administrator/kiosk.sh &" | tee /home/administrator/.config/openbox/autostart
touch /home/administrator/.config/openbox/menu.xml
cp /etc/xdg/openbox/rc.xml /home/administrator/.config/openbox/
sudo sed -i 's/^enabled=1/enabled=0/' /etc/default/apport
