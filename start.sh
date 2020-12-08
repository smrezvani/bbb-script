#!/bin/bash

##
# My Variables
##
source ./data.sh

# Color variables
red='\e[31m'
green='\e[32m'
blue='\e[34m'
clear='\e[0m'

# Shecan DNS
SHECAN="nameserver 178.22.122.100"
SHECAN_IS_SET=$(grep -Fxq "$SHECAN" /etc/resolv.conf)

##
# My Functions
##
function prepair_server() {
  if [[ ! -f /root/.bbb-secret ]]
  then
    (date +%s | sha256sum | base64 | head -c 48 ; echo) > /root/.bbb-secret
  fi
  if [[ ! $SHECAN_IS_SET ]]
  then
    printf "Shecan is not Active. Do you want to active it?\n"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) active_shecan; break;;
            No ) break;;
        esac
    done
  fi
  printf "Update the packages list...\n"
  apt clean && apt update -q
  sleep 1
  (echo "${FQDN}" > /etc/hostname)
  hostname -F /etc/hostname
  apt update && apt upgrade -y && apt autoremove -y
cat > /etc/timezone << EOF
$TIME_ZONE
EOF
  printf "Do you need to connect to NFS?\n"
  select yn in "Yes" "No"; do
    case $yn in
      Yes ) check_private_cloud; break;;
      No ) break;;
    esac
  done
}

function active_shecan() {
  printf "Change DNS to Shecan...\n"
cat > /etc/resolv.conf << EOF
nameserver 178.22.122.100
nameserver 185.51.200.2
EOF
  sleep 2
  printf "Shecan is activated!\n\n"
}

function check_private_cloud() {
  # Maximum number to try
  ((count = 10))
  while [[ $count -ne 0 ]] ; do
    # Try once
    ping -c 1 192.168.100.21
    rc=$?
    if [[ $rc -eq 0 ]]
    then
      # If okay, flag to exit loop
      ((count = 1))
    fi
    # So we don't go forever
    ((count = count - 1))
  done

  # Make final determination
  if [[ $rc -eq 0 ]]
  then
    printf "Mount NFS to the server...\n"
    mount_nfs
  else
    printf "Start to connect to \"Private Cloud\"\n"
    connect_private_cloud
    mount_nfs
  fi
}

function mount_nfs() {
  if [[ ! -d /nfs/ ]]
  then
    printf "Create NFS mount point...!"
      mkdir /nfs
  fi
  if ! grep -q nfs "/etc/fstab";
  then
    echo '192.168.100.230:/nfs /nfs/ nfs defaults 0 0' >> /etc/fstab
  fi
  mount -a
  printf "The NFS partition mounted to the server...!"
}

function connect_private_cloud() {
  if [[! -f /etc/systemd/system/openconnect.service ]]
  then
    # Check openconnect is installed or not
    OC_PKG=openconnect
    if ! dpkg --get-selections | grep -q "^$OC_PKG[[:space:]]*install$";
    then
      apt update && apt install $OC_PKG -y
    fi

cat > /etc/systemd/system/openconnect.service << EOF
    [Unit]
    Description=Connect to DarsPlus private cloud
    After=network.target

    [Service]
    Type=simple
    Environment=password=$ocPassword
    ExecStart=/bin/sh -c 'echo $password | sudo openconnect --passwd-on-stdin --user=$ocUsername --no-cert-check https://$ocservIP:$ocPort'
    Restart=always

    [Install]
    WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl start openconnect.service
    systemctl enable openconnect.service
  else
    printf "Service alredy configured. Check it man before any other change!!!"
  fi
}

function install_bbb() {
  BBB_PKG=bbb-web
  if ! dpkg --get-selections | grep -q "^$BBB_PKG[[:space:]]*install$";
  then
    printf "For install new BBB you should prepare the sevrer.\n"
    printf "Do you want to run prepare command?\n"
    select yn in "Yes" "No"; do
      case $yn in
        Yes ) prepair_server; break;;
        No ) break;;
      esac
    done
  fi
  new_install
}

function new_install() {
  if [[ -f /etc/bigbluebutton/bbb-conf/apply-config.sh ]]
  then
      rm -rf /etc/bigbluebutton/bbb-conf/apply-config.sh
  fi

  wget -qO- https://ubuntu.bigbluebutton.org/bbb-install.sh | bash -s -- -v xenial-22 -s $FQDN -e $eMail -c $turnServer:$turnSecret -w
  
  apply-config
}

function apply-config() {
  chmod +x apply-config.sh
  cp apply-config.sh /etc/bigbluebutton/bbb-conf/apply-config.sh
  bbb-conf --restart
}

function press_any_key() {
  printf "\nPress any key to back to menu..."
  while [ true ]
    do
    read -n 1
    if [ $? = 0 ]
    then
      clear ; menu ;
    fi
  done
}

# Call the menu function
RUN() {
  if [ $EUID != 0 ]; 
  then 
    printf "This script should run as root.\n";
    printf "Please enter [sudo] password:\n"
    sudo -i
  else
    clear
    menu
  fi
}

# Color Functions
ColorGreen(){
	echo -ne $green$1$clear
}
ColorBlue(){
	echo -ne $blue$1$clear
}
# Main menu
menu(){
  clear
echo -ne "
What do you want to do?
$(ColorGreen '1)') Prepare server for new instalation
$(ColorGreen '2)') Connect to private cloud and mount NFS
$(ColorGreen '3)') Install or Update BigBlueButton
$(ColorGreen '4)') Apply needed configuration to BBB
$(ColorGreen '0)') Exit
$(ColorBlue 'Choose an option:') "
        read a
        case $a in
	        1) prepair_server ; press_any_key ;;
	        2) check_private_cloud ; press_any_key ;;
	        3) install_bbb ; press_any_key ;;
          4) apply-config ; press_any_key ;;
		0) clear; exit 0 ;;
		*) echo -e $red"Wrong option."$clear; sleep 1; clear; menu;;
        esac
}

# RUN the script
RUN
