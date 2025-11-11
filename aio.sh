#!/bin/bash
# kiosk_setup.sh: One-time script for system configuration and installation.
set -euo pipefail

# --- Configuration Variables ---
CONFIG_FILE="$HOME/.printer.config"
DOWNLOAD_URL="https://www.dupage88.net/site/public/files/?item=7840"
BIN_DIR="$HOME/bin"
TMP_ZIP="/tmp/pi-setup_download.zip"
LOG_FILE="$HOME/kiosk_setup.log"
KIOSK_RUNTIME_SCRIPT="$HOME/kiosk_runtime.sh"

# --- Functions ---

# Function to check for and install whiptail
check_whiptail() {
    if ! command -v whiptail &> /dev/null; then
        echo "whiptail not found. Installing now..."
        sudo apt update > /dev/null 2>&1
        sudo apt install -y whiptail || { echo "ERROR: Failed to install whiptail. Exiting."; exit 1; }
    fi
}

collect_config() {
    check_whiptail # Ensure whiptail is available

    whiptail --title "Release Station Setup" --msgbox "Starting system configuration. All settings will be saved to $CONFIG_FILE." 8 60

    # 1. Hostname
    hostname=$(whiptail --title "Hostname" --inputbox "Enter a unique hostname for this kiosk." 8 60 "kiosk-01" 3>&1 1>&2 2>&3) || exit 1

    # 2. What is for Nimble or PaperCut
    whatfor=$(whiptail --title "What is for Nimber or PaperCut" --inputbox "What is for Nimble or PaperCut" 8 60 "PaperCut" 3>&1 1>&2 2>&3) || exit 1

    # 2. Case RGB Color
    rgb=$(whiptail --title "Case LED Color" --inputbox "Enter the case RGB color values (e.g., 255,0,0 for Red):" 8 60 "255,255,255" 3>&1 1>&2 2>&3) || exit 1

    # 3. Building Number
    building=$(whiptail --title "Building Selection" --menu "Select the Building Number:" 12 60 2 \
        "1" "Building 1 (Primary DNS: 10.1.65.10)" \
        "2" "Building 2+ (Primary DNS: 10.2.65.10)" 3>&1 1>&2 2>&3) || exit 1

    # 4. Primary Printer Name
    printer=$(whiptail --title "Primary Printer" --inputbox "Enter the Primary Printer name for job release (e.g., WB-A201-MFP):" 8 60 "" 3>&1 1>&2 2>&3) || exit 1

    # 5. Additional Printer Name
    showjobs=$(whiptail --title "Additional Printer" --inputbox "Enter an Additional Printer name (optional, WB-A201-MFP leave blank to skip):" 8 60 "" 3>&1 1>&2 2>&3)

    # 6. Static IP Address
    ip=$(whiptail --title "Static IP Address" --inputbox "Enter the Static IP Address (e.g., 10.x.y.z):" 8 60 "" 3>&1 1>&2 2>&3) || exit 1

    # Derive Gateway and DNS based on Building Number
    local first_three_octets
    first_three_octets=$(echo "$ip" | cut -d '.' -f 1-3)
    local gateway="${first_three_octets}.1"

    local dns
    if [[ "$building" == "1" ]]; then
        dns="10.1.65.10"
    elif [[ "$building" == "2" ]]; then
        dns="10.2.65.10"
    else
        whiptail --title "Warning" --msgbox "Unrecognized building number. Defaulting to 10.1.65.10." 8 60
        dns="10.1.65.10"
    fi

    # 7. LCD Display Model
    lcd=$(whiptail --title "LCD Display Model" --menu "Select the LCD Dispaly Model:" 12 60 2 \
        "1" "Model 1 (Standard Font: 1.0)" \
        "2" "Model 2 (Large Font/Rotated: 2.0)" 3>&1 1>&2 2>&3) || exit 1

    # Determine display settings based on LCD model
    local display_font
    if [[ "$lcd" == "1" ]]; then
        display_font="1.0"
    elif [[ "$lcd" == "2" ]]; then
        display_font="2.0"
    else
        whiptail --title "Warning" --msgbox "Invalid LCD choice. Defaulting to 1.0." 8 60
        display_font="1.0"
    fi

    # Create the escaped replacement string for the configuration file
    local final_showjobs_replacement
    if [[ -n "$showjobs" ]]; then
        # FINAL CORRECTED ESCAPING LOGIC:
        # Uses single quotes to assign 4 literal backslashes to the variable in the config file.
        # This results in the sourced variable having 2 backslashes (\\) which SED needs.
        final_showjobs_replacement=', papercut\\\\\\\'"$showjobs"
    else
        final_showjobs_replacement=""
    fi

    # Print to config file
    echo "# Kiosk Configuration Settings" > "$CONFIG_FILE"
    echo "hostname=\"$hostname\"" >> "$CONFIG_FILE"
    echo "printer=\"$printer\"" >> "$CONFIG_FILE"
    echo "ip=\"$ip\"" >> "$CONFIG_FILE"
    echo "rgb=\"$rgb\"" >> "$CONFIG_FILE"
    echo "gateway=\"$gateway\"" >> "$CONFIG_FILE"
    echo "dns=\"$dns\"" >> "$CONFIG_FILE"
    echo "display_font=\"$display_font\"" >> "$CONFIG_FILE"
    echo "final_showjobs_replacement=\"$final_showjobs_replacement\"" >> "$CONFIG_FILE"
    echo "whatfor=\"$whatfor\"" >> "$CONFIG_FILE"

    whiptail --title "Configuration Saved" --msgbox "Configuration saved to $CONFIG_FILE.\nHostname: $hostname\nIP: $ip\nDNS: $dns\nDisplay Font: $display_font" 10 60
}

install_packages() {
    echo "Updating system and installing dependencies..."
    sudo apt update
    sudo apt upgrade -y

    sudo apt install -y \
        wget unzip unattended-upgrades openjdk-25-jdk \
        pcsc-tools pcscd libusb-dev libacsccid1 libnfc-dev \
        python3-pip openssh-server chromium libcanberra-gtk* \
        netcat-openbsd network-manager > "$LOG_FILE" 2>&1 || { echo "ERROR: Package installation failed. See $LOG_FILE"; exit 1; }
    sudo pip3 install Adafruit-Blinka-Raspberry-Pi5-Neopixel adafruit-circuitpython-neopixel Adafruit-Blinka --break-system-packages
sudo raspi-config nonint do_configure_keyboard us
sudo raspi-config nonint do_blanking 1
sudo raspi-config nonint do_squeekboard S3
sudo raspi-config nonint do_wifi_country US
echo "usb_max_current_enable=1" | sudo tee -a sudo tee -a /boot/firmware/config.txt
echo "https://nimble.dupage88.net/kiosk" | sudo tee /boot/firmware/fullpageos.txt
sudo sed -i '/^\#\!\/bin\/bash/a\exit'  /opt/custompios/scripts/start_chromium_browser

}

configure_network() {
    echo "Applying static network configuration using nmcli..."

    # Check if config variables are loaded. If not, load them now.
    if [[ -z "${ip:-}" || -z "${gateway:-}" || -z "${dns:-}" ]]; then
        if [[ -f "$CONFIG_FILE" ]]; then
            source "$CONFIG_FILE"
        else
            echo "ERROR: Configuration file not found. Skipping network setup."
            return 1
        fi
    fi

    # nmcli commands to apply static IP, netmask (/24), gateway, and DNS
    # 'Wired connection 1' is the common default connection name in Raspberry Pi OS
    sudo nmcli c mod 'Wired connection 1' ipv4.addresses "$ip/24" ipv4.method manual
    sudo nmcli c mod 'Wired connection 1' ipv4.gateway "$gateway"
    sudo nmcli c mod 'Wired connection 1' ipv4.dns "$dns"

    # Bring the connection down and up to apply changes immediately
    #sudo nmcli c down 'Wired connection 1'
    #sudo nmcli c up 'Wired connection 1' || echo "WARNING: Failed to bring 'Wired connection 1' up. Network settings will be applied on reboot."

    echo "Network configuration applied: IP=$ip, Gateway=$gateway, DNS=$dns"
}


download_and_prep_apps() {
    echo "Downloading and preparing Kiosk applications..."
    mkdir -p "$BIN_DIR"

    # Download and unzip the application bundle
    wget -O "$TMP_ZIP" "$DOWNLOAD_URL"
    # Overwrite the destination directory
    rm -rf /tmp/pi-setup/ # Clean up previous temporary unzip location
    unzip -o "$TMP_ZIP" -d /tmp/

    # Sync the application files to the bin directory
    rsync -avc /tmp/pi-setup// "$BIN_DIR/"

    # Clean up and set permissions
    rm -rf /tmp/pi-setup/ "$TMP_ZIP"
    chmod +x "$BIN_DIR/printrelease"/*.sh

    echo "Applications ready in $BIN_DIR."
}

setup_autostart() {
    echo "Configuring Kiosk autostart and cleanup..."

    # 1. Point X session to the runtime script
    echo -e "$KIOSK_RUNTIME_SCRIPT\nexec \$STARTUP" | sudo tee /etc/X11/Xsession.d/99x11-common_start > /dev/null

    # 2. Disable default Chromium launch on boot
    if [[ -f "/opt/custompios/scripts/start_chromium_browser" ]]; then
        sudo sed -i '/^\#\!\/bin\/bash/a\exit'  /opt/custompios/scripts/start_chromium_browser
    fi

    # 3. Disable keyring prompt
    if [[ -f "/usr/bin/gnome-keyring-daemon" ]]; then
        sudo chmod -x /usr/bin/gnome-keyring-daemon
    fi

    # 4. Schedule daily reboot
    (crontab -l 2>/dev/null; echo "0 6 * * * sudo reboot") | crontab -
}

# --- Main Execution Flow ---
SKIP_SETUP=false

# Check if the config file exists
if [[ -f "$CONFIG_FILE" ]]; then
    # Use whiptail for the prompt
    if (whiptail --title "Existing Configuration Found" --yesno "$CONFIG_FILE already exists. Run setup again?" 8 60); then
        echo "Proceeding with new setup (re-configuring and re-installing)..."
        SKIP_SETUP=false
    else
        echo "Skipping configuration and installation. Proceeding to create the runtime script using existing settings."
        SKIP_SETUP=true
    fi
fi

# Execute setup steps if SKIP_SETUP is false
if [[ "$SKIP_SETUP" == false ]]; then
        collect_config
        install_packages
        download_and_prep_apps
        configure_network # Network configuration (after config collection)
        setup_autostart
    else
        # Still run installation steps if skipping config, just source the config later
        install_packages
        download_and_prep_apps
        configure_network # Network configuration (relies on config file being there)
        setup_autostart
fi

# Load the configuration variables whether setup was run or skipped.
# This is mandatory for generating the runtime script below.
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "FATAL ERROR: Configuration file not found after setup. Exiting."
    exit 1
fi

# --- Create the dedicated runtime script ---
# The logic below relies on variables sourced from ~/.printer.config

echo "Creating the Kiosk Runtime Script: $KIOSK_RUNTIME_SCRIPT"
# Use single quotes ('EOF') to prevent premature variable expansion in the outer script
tee "$KIOSK_RUNTIME_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
# kiosk_runtime.sh: Executed every time the graphical session starts.
set -euo pipefail # Fail fast on errors, undefined variables, or pipeline errors

# === Configuration ===
CONFIG_FILE="/home/admin/.printer.config"
BIN_DIR="/home/admin/bin"
REMOTE_HOST="10.2.61.2"
REMOTE_PORT=443
MAX_RETRIES=5
SLEEP_INTERVAL=5
INTERFACE="eth0"

# Source the configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "FATAL: Configuration file not found at $CONFIG_FILE. Cannot start kiosk." | tee -a /home/admin/runtime_errors.log
    exit 1
fi
source "$CONFIG_FILE"

# === Function: Wait for Network Connectivity ===

wait_for_network() {
    echo "Waiting for IP address..."
    local ip_addr=""
    local countdown_seconds=10 # Set the desired countdown duration

    # === 1. Check for Static IP ===
    for ((i = 1; i <= MAX_RETRIES; i++)); do
        # Check if the expected static IP is assigned
        ip_addr=$(ip addr show "$INTERFACE" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
        if [[ -n "$ip_addr" && "$ip_addr" == "$ip" ]]; then
            echo "Got static IP address: $ip_addr"
            break
        fi
        echo "Attempt $i: IP address not assigned yet. Retrying in $SLEEP_INTERVAL seconds..."
        sleep "$SLEEP_INTERVAL"
    done

    if [[ "$ip_addr" != "$ip" ]]; then
        echo "ERROR: Static IP $ip not assigned after $MAX_RETRIES attempts." | tee -a /home/admin/runtime_errors.log
        echo "!!! System will REBOOT in $countdown_seconds seconds. !!!"
        # Start Countdown
        for ((s = countdown_seconds; s >= 1; s--)); do
            echo -ne "Rebooting in $s..."\\r
            sleep 1
        done
        echo ""
        sudo reboot
        return 1
    fi

    # === 2. Check for Remote Host Reachability ===
    echo "Checking if $REMOTE_HOST:$REMOTE_PORT is reachable..."
    for ((i = 1; i <= MAX_RETRIES; i++)); do
        if nc -z "$REMOTE_HOST" "$REMOTE_PORT" &> /dev/null; then
            echo "$REMOTE_HOST:$REMOTE_PORT is up! Starting Kiosk..."
            return 0
        fi
        echo "Attempt $i: Server not reachable. Retrying in $SLEEP_INTERVAL seconds..."
        sleep "$SLEEP_INTERVAL"
    done

    echo "ERROR: Server $REMOTE_HOST:$REMOTE_PORT is still down." | tee -a /home/admin/runtime_errors.log
    echo "!!! System will REBOOT in $countdown_seconds seconds. !!!"
    # Start Countdown
    for ((s = countdown_seconds; s >= 1; s--)); do
        echo -ne "Rebooting in $s..."\\r
        sleep 1
    done
    echo ""
    sudo reboot
    return 1
}


# === Runtime Execution ===

if ! wait_for_network; then
    exit 1
fi

# Display and Power Management Setup
xset -dpms
xset s off

# Display Rotation and Touch Correction (only for model 2)
if [[ "$display_font" == "2.0" ]]; then
    echo "Setting display rotation and touch calibration..."
    xrandr --output DSI-2 --rotate left
    # xinput device ID 6 may need adjustment depending on hardware/drivers
    xinput set-prop 6 "Coordinate Transformation Matrix" 0 -1 1 1 0 0 0 0 1
fi

# === File Download and Preparation ===
TMP_ZIP="/home/admin/tmp.zip"
DEST_DIR="/home/admin/pi-setup"

wget -O "$TMP_ZIP" "https://www.dupage88.net/site/public/files/?item=7840"
rm -rf "$DEST_DIR"
rm -rf /home/admin/bin
unzip "$TMP_ZIP" -d /home/admin/
rsync -av /home/admin/pi-setup/ /home/admin/bin
chmod +x /home/admin/bin/printrelease/*.sh

# Configure Application Properties
echo "Configuring application property files..."
# Variables ($display_font, $final_showjobs_replacement, $printer, $rgb) are sourced from ~/.printer.config
sed -i "s/@DISPLAY_FONT@/$display_font/g" "$BIN_DIR/printrelease/config.properties"
sed -i "s/@SHOWJOBS@/$final_showjobs_replacement/g" "$BIN_DIR/printrelease/config.properties"
sed -i "s/@PRINTER@/$printer/g" "$BIN_DIR/printrelease/config.properties"
sed -i "s/@rgb@/$rgb/g" "$BIN_DIR/nfc/settings.properties"

  if [[ "$whatfor" == "PaperCut" ]]; then
        # Launch Background Services
	echo "Launching background services (LED, NFC Reader)..."
	python "$BIN_DIR/case-led/led_values.py" "$rgb" &
	java -jar "$BIN_DIR/nfc/nfc-reader-depends-0.5.3-SNAPSHOT.jar" "$BIN_DIR/nfc/settings.properties" &

	# Launch Main Application
	echo "Launching main Print Release application..."
	"$BIN_DIR/printrelease/pc-release-linux.sh"
    elif [[ "$whatfor" == "Nimble" ]]; then
        pactl set-default-sink alsa_output.usb-JOUNIVO_JOUNIVO_JV801_20200822-00.analog-stereo
	pactl set-sink-mute @DEFAULT_SINK@ 0
	pactl set-sink-volume @DEFAULT_SINK@ 95%
	java -jar /home/admin/bin/nfc/nfc-reader-depends-0.5.1-SNAPSHOT.jar /home/admin/bin/nfc/nimblesettings.properties &
	chromium https://nimble.dupage88.net --kiosk --noerrdialogs --disable-pinch --disable-infobars --no-first-run --enable-features=OverlayScrollbar --start-maximized
    else
	sleep 20
        sudo reboot
    fi

EOF

chmod +x "$KIOSK_RUNTIME_SCRIPT"
echo "Setup complete. Please reboot to start the kiosk in runtime mode."
