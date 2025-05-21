#!/bin/bash

# Check if setup has already been completed
if [ -f ~/.nimble.config ]; then
  echo "This script has already been executed"
  exit 1
fi

echo "Starting Nimble Station Setup..."
echo ""

sudo nmcli radio wifi on
sudo iw reg set US
sudo iwlist wlan0 scan
sleep 5
sudo nmcli dev wifi connect d88-guest

# Prompt for static network settings
read -p "Enter a hostname: " hostname
read -p "Enter an IP Address: " ip
read -p "Enter a Gateway Address: " gateway
read -p "Enter a DNS Address: " dns

# Configure wired connection with provided details
echo "Using hostname: $hostname"
echo "Using IP: $ip"

sudo nmcli c mod 'Wired connection 1' ipv4.addresses "$ip/24" ipv4.method manual
sudo nmcli c mod 'Wired connection 1' ipv4.gateway "$gateway"
sudo nmcli c mod 'Wired connection 1' ipv4.dns "$dns"
sudo nmcli c down 'Wired connection 1' && sudo nmcli c up 'Wired connection 1'


# Allow time for NTP to update
echo "Giving some time for NTP to update..."
sleep 10
echo "Proceeding with system updates..."

# System updates and package installation
sudo apt update && sudo apt upgrade -y
sudo apt install -y unattended-upgrades unclutter
sudo apt autoremove -y

# Set timezone and hostname
echo "US/Central" | sudo tee /etc/timezone
echo "$hostname" | sudo tee /etc/hostname

# Add cron job to reboot the system daily
echo "1 2 * * * root /sbin/reboot" | sudo tee -a /etc/cron.d/restart

# Configure temporary filesystems
echo "
tmpfs    /tmp        tmpfs      defaults,noatime,mode=1777,size=500m    0    0
tmpfs    /var/log    tmpfs      defaults,noatime,mode=1777,size=500m    0    0
tmpfs    /var/tmp    tmpfs      defaults,noatime,mode=1777,size=100m    0    0
" | sudo tee -a /etc/fstab

# Save configuration details to file
echo -e "hostname=$hostname\nip=$ip\ngateway=$gateway\ndns=$dns" > ~/.nimble.config

# Add unclutter command to hide cursor in X11 session
echo "unclutter -idle 0" | sudo tee -a /etc/X11/Xsession.d/99x11-common_start

# Download custom wallpaper
sudo wget -O /usr/share/rpd-wallpaper/fisherman.jpg https://www.dupage88.net/site/public/agoraimages/?item=18485

# Configure Wayland settings
sudo raspi-config nonint do_wayland W2

# Disable on-screen keyboard
sudo raspi-config nonint do_squeekboard S3

# Create the kiosk.sh script to launch Chromium in kiosk mode
cat <<EOF > ~/kiosk.sh
#!/bin/bash
while true; do
   amixer -q -M sset Master 90%
   chromium-browser https://nimble.dupage88.net --kiosk --noerrdialogs --disable-pinch --disable-infobars --no-first-run --enable-features=OverlayScrollbar --start-maximized
done
EOF

chmod +x ~/kiosk.sh

# Configure autostart for kiosk mode
cat <<EOF | sudo tee -a ~/.config/wayfire.ini
[autostart]
xdg-autostart = lxsession-xdg-autostart
kiosk = bash ~/kiosk.sh
screensaver = false
dpms = false
EOF

# Completion message
echo "==========================================================="
echo "Nimble Station Setup Completed. Please reboot the system."
echo "==========================================================="
