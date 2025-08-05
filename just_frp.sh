#!/bin/bash

# Just FRP - A Comprehensive FRP Tunneling Script
# Version: 4.1.2 (Final Polished Version)
# Author: Gemini AI & User Collaboration
# Architecture: Server on Iran, Client on Abroad. Domain points to Iran IP.

# --- Colors and Styles ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_MAGENTA='\033[0;35m'
C_CYAN='\033[1;36m'
C_BOLD_WHITE='\033[1;37m'

# --- Global Variables ---
FRP_VERSION="0.52.3" # Using a known stable version
FRP_INSTALL_DIR="/etc/frp"
FRP_BIN_DIR="/usr/local/bin"
FRP_SERVICE_DIR="/etc/systemd/system"
FRPS_CONFIG_FILE="${FRP_INSTALL_DIR}/frps.ini"
FRPC_CONFIG_FILE="${FRP_INSTALL_DIR}/frpc.ini"
SERVER_IP=""

# --- Helper Functions ---
print_header() {
    clear
    local border="${C_MAGENTA}============================================================${C_RESET}"
    echo -e "$border"
    echo -e "${C_CYAN}        █ █ █ █   █ █ █ █   █ █ █ █   █ █ █ █        ${C_RESET}"
    echo -e "${C_BOLD_WHITE}                J U S T   F R P                ${C_RESET}"
    echo -e "${C_BOLD_WHITE}              T U N N E L   M A N A G E R              ${C_RESET}"
    echo -e "${C_CYAN}        █ █ █ █   █ █ █ █   █ █ █ █   █ █ █ █        ${C_RESET}"
    echo -e "$border"
    echo -e "${C_BOLD_WHITE}                          Version 4.1.2                         ${C_RESET}"
    echo -e "\n${C_YELLOW}》 $1${C_RESET}"
    echo -e "${C_MAGENTA}------------------------------------------------------------${C_RESET}"
}

press_enter_to_continue() {
    echo ""
    read -p "Press [Enter] to continue..."
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${C_RED}Error: This script must be run as root.${C_RESET}"
        exit 1
    fi
}

get_public_ip() {
    echo -e "${C_BLUE}Attempting to automatically detect public IP...${C_RESET}"
    IP=$(curl -s4 ifconfig.me)
    if [[ ! "$IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "${C_YELLOW}ifconfig.me failed, trying ipinfo.io...${C_RESET}"
        IP=$(curl -s4 ipinfo.io/ip)
    fi
    if [[ ! "$IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "${C_YELLOW}ipinfo.io failed, trying api.ipify.org...${C_RESET}"
        IP=$(curl -s4 api.ipify.org)
    fi
    if [[ ! "$IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "${C_RED}Could not automatically determine public IP.${C_RESET}"
        read -p "Please enter this server's public IP address manually: " IP
    fi
    SERVER_IP=$IP
}


detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo -e "${C_RED}Error: Unsupported architecture: $ARCH.${C_RESET}"; exit 1 ;;
    esac
    FRP_FILENAME="frp_${FRP_VERSION}_linux_${ARCH}"
}

download_and_extract_frp() {
    if [ -f "${FRP_BIN_DIR}/frps" ]; then
        echo -e "${C_YELLOW}FRP is already installed. Skipping download.${C_RESET}"
        sleep 2
        return
    fi
    echo -e "${C_BLUE}Downloading FRP v${FRP_VERSION} for ${ARCH}...${C_RESET}"
    cd /tmp
    wget "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FRP_FILENAME}.tar.gz" -O frp.tar.gz
    if [ $? -ne 0 ]; then echo -e "${C_RED}Error: Failed to download FRP.${C_RESET}"; exit 1; fi

    tar -xzf frp.tar.gz
    mkdir -p ${FRP_INSTALL_DIR}
    cp ${FRP_FILENAME}/frps ${FRP_BIN_DIR}/frps
    cp ${FRP_FILENAME}/frpc ${FRP_BIN_DIR}/frpc
    chmod +x ${FRP_BIN_DIR}/frps ${FRP_BIN_DIR}/frpc
    rm -rf /tmp/frp.tar.gz /tmp/${FRP_FILENAME}
    echo -e "${C_GREEN}FRP has been installed successfully.${C_RESET}"
    sleep 2
}

# --- Core Functions ---

setup_frps_on_iran() {
    print_header "Installing FRP Server (on IRAN Server)"
    read -p "Enter your domain name (that points to THIS server's IP): " DOMAIN
    if [ -z "$DOMAIN" ]; then echo -e "${C_RED}Error: Domain name cannot be empty.${C_RESET}"; exit 1; fi
    read -p "Enter a secure token for authentication: " AUTH_TOKEN
    if [ -z "$AUTH_TOKEN" ]; then echo -e "${C_RED}Error: Token cannot be empty.${C_RESET}"; exit 1; fi
    read -p "Enter the main FRP bind port (e.g., 443, 8443): " BIND_PORT
    if ! [[ "$BIND_PORT" =~ ^[0-9]+$ ]]; then echo -e "${C_RED}Invalid port number.${C_RESET}"; exit 1; fi

    get_public_ip # Call the new robust IP detection function
    
    echo -e "\n${C_YELLOW}Please ensure your domain '${C_CYAN}${DOMAIN}${C_YELLOW}' points to THIS server's IP: ${C_CYAN}${SERVER_IP}${C_RESET}"
    read -p "Press [Enter] to continue."

    apt install -y snapd
    if ! command -v certbot &> /dev/null; then
        snap install core; snap refresh core
        snap install --classic certbot
        ln -s /snap/bin/certbot /usr/bin/certbot
    fi

    echo -e "\n${C_BLUE}Obtaining SSL certificate for ${DOMAIN}...${C_RESET}"
    certbot certonly --standalone -d "${DOMAIN}" --non-interactive --agree-tos --email "admin@${DOMAIN}"
    if [ $? -ne 0 ]; then echo -e "${C_RED}Error: Failed to obtain SSL certificate. Is port 80 open?${C_RESET}"; exit 1; fi

    echo -e "\n${C_BLUE}Configuring FRPS...${C_RESET}"
    DASHBOARD_PASS=$(openssl rand -base64 12)
    cat > ${FRPS_CONFIG_FILE} <<EOF
[common]
bind_port = ${BIND_PORT}
token = ${AUTH_TOKEN}
subdomain_host = ${DOMAIN}
tls_cert_file = /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
tls_key_file = /etc/letsencrypt/live/${DOMAIN}/privkey.pem
dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = ${DASHBOARD_PASS}
EOF

    if command -v ufw &> /dev/null; then
        ufw allow 80/tcp
        ufw allow ${BIND_PORT}/tcp
        ufw allow 7500/tcp
        ufw reload
    fi

    cat > ${FRP_SERVICE_DIR}/frps.service <<EOF
[Unit]
Description=FRP Server (Iran)
After=network.target
[Service]
Type=simple
User=root
ExecStart=${FRP_BIN_DIR}/frps -c ${FRPS_CONFIG_FILE}
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frps
    systemctl start frps

    print_header "FRP Server Installation Complete!"
    echo -e "${C_GREEN}FRP Server is now running on your IRAN server.${C_RESET}"
    echo -e "\n${C_YELLOW}Use this info to set up the client on the ABROAD server:${C_RESET}"
    echo -e "------------------------------------------------------------"
    echo -e "Domain:               ${C_CYAN}${DOMAIN}${C_RESET}"
    echo -e "Server Port:          ${C_CYAN}${BIND_PORT}${C_RESET}"
    echo -e "Token:                ${C_CYAN}${AUTH_TOKEN}${C_RESET}"
    echo -e "Dashboard:            ${C_CYAN}http://${SERVER_IP}:7500${C_RESET}"
    echo -e "Dashboard User/Pass:  ${C_CYAN}admin / ${DASHBOARD_PASS}${C_RESET}"
    echo -e "------------------------------------------------------------"
    press_enter_to_continue
}

setup_frpc_on_abroad() {
    print_header "Installing FRP Client (on ABROAD Server)"
    read -p "Enter the IRAN server's domain name: " SERVER_DOMAIN
    read -p "Enter the IRAN server's bind port (e.g., 443): " SERVER_PORT
    read -p "Enter the authentication token: " AUTH_TOKEN

    echo -e "\n${C_BLUE}Configuring FRPC...${C_RESET}"
    cat > ${FRPC_CONFIG_FILE} <<EOF
[common]
server_addr = ${SERVER_DOMAIN}
server_port = ${SERVER_PORT}
token = ${AUTH_TOKEN}
tls_enable = true
EOF
    
    add_port_mapping # Call the function to add initial ports
    
    cat > ${FRP_SERVICE_DIR}/frpc.service <<EOF
[Unit]
Description=FRP Client (Abroad)
After=network.target
[Service]
Type=simple
User=root
ExecStart=${FRP_BIN_DIR}/frpc -c ${FRPC_CONFIG_FILE}
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frpc
    systemctl start frpc

    print_header "FRP Client Installation Complete!"
    echo -e "${C_GREEN}FRP Client is now running on your ABROAD server.${C_RESET}"
    echo -e "${C_YELLOW}The configured ports are now exposed via your IRAN server's domain.${C_RESET}"
    press_enter_to_continue
}

uninstall_frp() {
    print_header "Uninstall Just FRP"
    read -p "Are you sure you want to completely uninstall Just FRP? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        echo -e "${C_YELLOW}Uninstall cancelled.${C_RESET}"; return;
    fi

    systemctl stop frps &>/dev/null; systemctl disable frps &>/dev/null
    systemctl stop frpc &>/dev/null; systemctl disable frpc &>/dev/null
    rm -f ${FRP_SERVICE_DIR}/frps.service ${FRP_SERVICE_DIR}/frpc.service
    rm -f ${FRP_BIN_DIR}/frps ${FRP_BIN_DIR}/frpc
    rm -rf ${FRP_INSTALL_DIR}
    systemctl daemon-reload
    echo -e "${C_GREEN}Just FRP has been successfully uninstalled.${C_RESET}"
    press_enter_to_continue
}

check_status() {
    print_header "Tunnel Status"
    if [ -f "${FRPS_CONFIG_FILE}" ]; then
        echo -e "${C_BOLD_WHITE}This machine is configured as: SERVER (IRAN)${C_RESET}"
        if systemctl is-active --quiet frps; then
            echo -e "FRPs Service: ${C_GREEN}Active (running)${C_RESET}"
        else
            echo -e "FRPs Service: ${C_RED}INACTIVE or FAILED${C_RESET}"
        fi
        echo -e "\n${C_YELLOW}Recent Logs:${C_RESET}"
        journalctl -u frps -n 10 --no-pager
    elif [ -f "${FRPC_CONFIG_FILE}" ]; then
        echo -e "${C_BOLD_WHITE}This machine is configured as: CLIENT (ABROAD)${C_RESET}"
        if systemctl is-active --quiet frpc; then
            echo -e "FRPc Service: ${C_GREEN}Active (running)${C_RESET}"
        else
            echo -e "FRPc Service: ${C_RED}INACTIVE or FAILED${C_RESET}"
        fi
        echo -e "\n${C_YELLOW}Recent Logs:${C_RESET}"
        journalctl -u frpc -n 10 --no-pager
    else
        echo -e "${C_YELLOW}Just FRP is not installed on this machine.${C_RESET}"
    fi
    press_enter_to_continue
}

add_port_mapping() {
    if [ ! -f "${FRPC_CONFIG_FILE}" ]; then
        echo -e "${C_RED}FRP Client is not installed. Cannot add ports.${C_RESET}"; sleep 2; return;
    fi
    
    while true; do
        print_header "Add/Manage Port Mappings (Client on Abroad)"
        echo -e "${C_YELLOW}Current Mappings in ${C_CYAN}${FRPC_CONFIG_FILE}${C_RESET}:"
        grep -E '^\[' ${FRPC_CONFIG_FILE} | grep -v 'common' | sed 's/\[//g;s/\]//g'
        echo -e "------------------------------------------------------------"
        echo -e " (a) Add a new port mapping"
        echo -e " (r) Remove a port mapping"
        echo -e " (q) Quit and apply changes"
        read -p "Your choice: " choice
        
        case $choice in
            [aA])
                echo ""
                read -p "   Enter LOCAL Port on this ABROAD server (e.g., 22 for SSH): " local_port
                read -p "   Enter REMOTE Port on the IRAN server (e.g., 2222): " remote_port
                
                if [[ "$local_port" =~ ^[0-9]+$ && "$remote_port" =~ ^[0-9]+$ ]]; then
                    proxy_name="remote_${remote_port}"
                    if grep -q "\[${proxy_name}\]" ${FRPC_CONFIG_FILE}; then
                        echo -e "${C_RED}Error: A proxy with this remote port already exists.${C_RESET}"; sleep 2; continue;
                    fi
                    
                    cat >> ${FRPC_CONFIG_FILE} <<EOF

[${proxy_name}]
type = tcp
local_ip = 127.0.0.1
local_port = ${local_port}
remote_port = ${remote_port}
EOF
                    echo -e "${C_GREEN}Mapping added: Iran:${remote_port} -> Abroad:${local_port}${C_RESET}"
                    echo -e "${C_YELLOW}IMPORTANT: You must open port ${C_CYAN}${remote_port}${C_YELLOW} on the IRAN server's firewall!${C_RESET}"
                    sleep 3
                else
                    echo -e "${C_RED}Invalid port numbers.${C_RESET}"; sleep 2;
                fi
                ;;
            [rR])
                echo ""
                read -p "   Enter the REMOTE port of the mapping to remove (e.g., 2222): " remote_port
                proxy_name="remote_${remote_port}"
                if grep -q "\[${proxy_name}\]" ${FRPC_CONFIG_FILE}; then
                    # Complex sed command to delete a whole block
                    sed -i "/^\[${proxy_name}\]/, /^\s*$/{ /^\s*$/!d; }; /^\[${proxy_name}\]/d" ${FRPC_CONFIG_FILE}
                    echo -e "${C_GREEN}Mapping for remote port ${remote_port} removed.${C_RESET}"; sleep 2;
                else
                    echo -e "${C_RED}Error: No mapping found for remote port ${remote_port}.${C_RESET}"; sleep 2;
                fi
                ;;
            [qQ])
                break
                ;;
            *)
                echo -e "${C_RED}Invalid choice.${C_RESET}"; sleep 1;
                ;;
        esac
    done
    echo -e "\n${C_BLUE}Restarting FRP Client to apply changes...${C_RESET}"
    systemctl restart frpc
    sleep 2
}

manage_cron_restart() {
    print_header "Manage Scheduled Restarts"
    
    SERVICE_NAME=""
    if [ -f "${FRPS_CONFIG_FILE}" ]; then SERVICE_NAME="frps";
    elif [ -f "${FRPC_CONFIG_FILE}" ]; then SERVICE_NAME="frpc";
    else echo -e "${C_RED}Just FRP is not installed.${C_RESET}"; press_enter_to_continue; return; fi

    CRON_CMD="systemctl restart ${SERVICE_NAME}"
    
    echo -e "Select a restart schedule for the ${C_CYAN}${SERVICE_NAME}${C_RESET} service:"
    echo " 1) Every hour"
    echo " 2) Every 6 hours"
    echo " 3) Every 12 hours"
    echo " 4) Every day (at 4 AM)"
    echo " 5) ${C_RED}Remove scheduled restart${C_RESET}"
    echo " 6) Back to main menu"
    read -p "Enter your choice [1-6]: " cron_choice

    # Remove existing cron job first
    (crontab -l 2>/dev/null | grep -v "${CRON_CMD}") | crontab -
    
    CRON_SCHEDULE=""
    case $cron_choice in
        1) CRON_SCHEDULE="0 * * * *" ;;
        2) CRON_SCHEDULE="0 */6 * * *" ;;
        3) CRON_SCHEDULE="0 */12 * * *" ;;
        4) CRON_SCHEDULE="0 4 * * *" ;;
        5) echo -e "${C_GREEN}Scheduled restart removed.${C_RESET}"; press_enter_to_continue; return ;;
        6) return ;;
        *) echo -e "${C_RED}Invalid choice.${C_RESET}"; sleep 2; return ;;
    esac

    (crontab -l 2>/dev/null; echo "${CRON_SCHEDULE} ${CRON_CMD}") | crontab -
    echo -e "${C_GREEN}Restart schedule successfully set!${C_RESET}"
    press_enter_to_continue
}

# --- Main Menu ---
show_menu() {
    print_header "Main Menu"
    echo -e "Architecture: ${C_BOLD_WHITE}Server on Iran, Client on Abroad${C_RESET}\n"
    echo -e " ${C_CYAN}1)${C_RESET}  Install FRP Server (Run on IRAN)"
    echo -e " ${C_CYAN}2)${C_RESET}  Install FRP Client (Run on ABROAD)"
    echo ""
    echo -e " ${C_CYAN}3)${C_RESET}  Add/Manage Ports (Run on ABROAD)"
    echo -e " ${C_CYAN}4)${C_RESET}  Manage Scheduled Restarts"
    echo -e " ${C_CYAN}5)${C_RESET}  Check Tunnel Status"
    echo ""
    echo -e " ${C_CYAN}6)${C_RESET}  ${C_RED}Uninstall Just FRP${C_RESET}"
    echo -e " ${C_CYAN}7)${C_RESET}  Exit"
    echo -e "${C_MAGENTA}============================================================${C_RESET}"
    read -p "Enter your choice [1-7]: " choice
    case $choice in
        1) check_root; detect_arch; install_dependencies; download_and_extract_frp; setup_frps_on_iran ;;
        2) check_root; detect_arch; install_dependencies; download_and_extract_frp; setup_frpc_on_abroad ;;
        3) check_root; add_port_mapping ;;
        4) check_root; manage_cron_restart ;;
        5) check_root; check_status ;;
        6) check_root; uninstall_frp ;;
        7) exit 0 ;;
        *) echo -e "${C_RED}Invalid option.${C_RESET}"; sleep 1;;
    esac
}

# --- Script Entry Point ---
while true; do
    show_menu
done
