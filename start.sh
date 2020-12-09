#!/bin/bash

# Script PATH
SCRIPT_PATH=/root/.bbb-script

# RUN the script
RUN() {

  # Check for root user
  if [ $EUID != 0 ]; 
  then 
    printf "This script should run as root.\n";
    sudo -i
  fi

  # Check for config file
  if [[ ! -f $SCRIPT_PATH/config ]]
  then
    config_generator
  fi

  # Source the config file
  source $SCRIPT_PATH/config

  # Check for BBB secret file
  if [[ ! -f $SCRIPT_PATH/secret ]]
  then
    secret_generator
  fi

  # Check for BBB properties file
  if [[ ! -f $SCRIPT_PATH/bigbluebutton.properties ]]
  then
    install -D /root/bbb-script/bigbluebutton.properties $SCRIPT_PATH
  fi

  # Check for BBB settings file
  if [[ ! -f $SCRIPT_PATH/settings.yml ]]
  then
    install -D /root/bbb-script/settings.yml $SCRIPT_PATH
  fi

  # Check for BBB bigbluebutton-default
  if [[ ! -d $SCRIPT_PATH/bigbluebutton-default/ ]]
  then
    mkdir -p $SCRIPT_PATH/bigbluebutton-default/
    install -D /root/bbb-script/bigbluebutton-default/* $SCRIPT_PATH/bigbluebutton-default/
  fi

  # Create menu
  clear
  menu

}

## Functions ##
function config_generator() {

  # Check for script path on /root/
  if [ ! -d $SCRIPT_PATH ]
  then
    mkdir -p $SCRIPT_PATH
  fi

  # create or change config file
  create_config_file

}

function create_config_file() {

  # If Config file exist just change it. If not exist, create from template then change it.
  if [[ ! -f $SCRIPT_PATH/config ]]
  then
cat > $SCRIPT_PATH/config << EOF
# File's PATH
SCRIPT_ROOT=/root/bbb-script
BBB_PROP=/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties
HTML5_CONFIG=/usr/share/meteor/bundle/programs/server/assets/app/config/settings.yml
DEFAULT_PAGE=/var/www/bigbluebutton-default
BBB_PKG=bbb-web
BBB_CONF_PATH=/etc/bigbluebutton/bbb-conf

TIME_ZONE=

# BBB Installation
FQDN=
eMail=
turnServer=
turnSecret=

# OpenConnect
ocservIP=
ocPort=
ocUsername=
ocPassword=
EOF
  fi

  # Get input from user
  printf "Input time zone(default: Asia/Tehran): "
  read TIME_ZONE
  TIME_ZONE=${TIME_ZONE:-Asia/Tehran}
  printf "Input FQDN(example: bbb.domain.com): "
  read FQDN
  printf "Input email address for Let's Encrypt: "
  read eMail
  printf "Input turn server FQDN(example: turn.domain.com): "
  read turnServer
  printf "Input turn server secret: "
  read turnSecret
  printf "\n*** If you dont need openconnect, don't fill inputs. ***\n"
  printf "Input openconnect IP address: "
  read ocservIP
  printf "Input openconnect Port number: "
  read ocPort
  printf "Input openconnect username: "
  read ocUsername
  printf "Input openconnect password: "
  read ocPassword
  printf "Creating config file...\n"
  sleep 2

  # Change variables
  sed -i "s,^TIME_ZONE=.*,TIME_ZONE=$TIME_ZONE" $BBB_CONFIG
  sed -i "s,^FQDN=.*,FQDN=$FQDN" $BBB_CONFIG
  sed -i "s,^eMail=.*,eMail=$eMail" $BBB_CONFIG
  sed -i "s,^turnServer=.*,turnServer=$turnServer" $BBB_CONFIG
  sed -i "s,^turnSecret=.*,turnSecret=$turnSecret" $BBB_CONFIG
  sed -i "s,^ocservIP=.*,ocservIP=$ocservIP" $BBB_CONFIG
  sed -i "s,^ocPort=.*,ocPort=$ocPort" $BBB_CONFIG
  sed -i "s,^ocUsername=.*,ocUsername=$ocUsername" $BBB_CONFIG
  sed -i "s,^ocPassword=.*,ocPassword=$ocPassword" $BBB_CONFIG

}

function secret_generator() {

  # Check if BBB install or not!
  if ! dpkg --get-selections | grep -q "^$BBB_PKG[[:space:]]*install$"
  then
    if [[ ! -f $SCRIPT_PATH/secret ]]
    then
      (date +%s | sha256sum | base64 | head -c 48 ; echo) > $SCRIPT_PATH/secret
    fi
  else
    if [[ ! -f $SCRIPT_PATH/secret ]]
    then
      (bbb-conf --secret | grep 'Secret:' | sed 's/^.*: //') > $SCRIPT_PATH/secret
    fi
  fi

}

function prepair_server() {

  # Check for hostname
  if [ "$(hostname)" !== "$FQDN" ]
  then
    (echo "${FQDN}" > /etc/hostname)
    hostname -F /etc/hostname
  fi

  # Set time zone
  timedatectl set-timezone $TIME_ZONE

  # Check for Shecan nameservers
  SHECAN="nameserver 178.22.122.100"
  SHECAN_IS_SET=$(grep -Fxq "$SHECAN" /etc/resolv.conf)
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
  apt clean && apt update -q && apt upgrade -y && apt autoremove -y
  
  # Check for NFS
  printf "Should I mount NFS partition?\n"
  select yn in "Yes" "No"; do
    case $yn in
      Yes ) check_private_network; break;;
      No ) break;;
    esac
  done

}

function active_shecan() {
cat > /etc/resolv.conf << EOF
nameserver 178.22.122.100
nameserver 185.51.200.2
EOF
}

function check_private_network() {

  # Check private network connection
  printf "Input the NFS private IP: "
  read NFS_IP
  if ping -c1 $NFS_IP 1>/dev/null 2>/dev/null
  then
    mount_nfs
  else
    connect_private_network
    mount_nfs
  fi

}

function mount_nfs() {
  if [[ ! -d /nfs/ ]]
  then
      mkdir /nfs
  fi
  if ( ! grep -q nfs "/etc/fstab" )
  then
    echo '192.168.100.230:/nfs /nfs/ nfs defaults 0 0' >> /etc/fstab
  fi
  mount -a
}
 
function connect_private_network() {

  # Check for openconnect service
  if [[ ! -f /etc/systemd/system/openconnect.service ]]
  then
    # Check openconnect is installed or not
    OC_PKG=openconnect
    if ! dpkg --get-selections | grep -q "^$OC_PKG[[:space:]]*install$";
    then
      apt update -q && apt install $OC_PKG -y
    fi

# Create openconnect service file
cat > /etc/systemd/system/openconnect.service << EOF
    [Unit]
    Description=Connect to private network
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
  fi

}

function install_update() {

  # Check for install or update BBB
  if ! dpkg --get-selections | grep -q "^$BBB_PKG[[:space:]]*install$";
  then
    # Install new BBB on clean server
    prepair_server
    new_install
  else
    # Update existing BBB instalation
    new_install
  fi
}

function new_install() {
  bbb_install_command
  apply-config
}

function update_everything() {
  apt update -q && apt upgrade -y && apt autoremove -y
  sleep 2
  bbb_install_command
  apply-config
}

function bbb_install_command() {
  wget -qO- https://ubuntu.bigbluebutton.org/bbb-install.sh | bash -s -- -v xenial-22 -s $FQDN -e $eMail -c $turnServer:$turnSecret -w
}

function apply-config() {
  if [[ -f $BBB_CONF_PATH/apply-config.sh ]]
  then
      rm -rf $BBB_CONF_PATH/apply-config.sh
  fi
  chmod +x $SCRIPT_ROOT/apply-config.sh
  cp $SCRIPT_ROOT/apply-config.sh $BBB_CONF_PATH/
  bbb-conf --restart
}

function press_any_key() {
  printf "\n\nPress any key to back to menu...!"
  while [ true ]
    do
    read -n 1
    if [ $? = 0 ]
    then
      clear ; menu ;
    fi
  done
}

# Color Variables
red='\e[31m'
green='\e[32m'
blue='\e[34m'
clear='\e[0m'

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
$(ColorGreen '1)') Generate new config file
$(ColorGreen '2)') Install or Update BBB
$(ColorGreen '3)') Connect to private network and mount NFS
$(ColorGreen '4)') Apply config to BBB
$(ColorGreen '0)') Exit
$(ColorBlue 'Choose an option:') "
        read a
        case $a in
	        1) create_config_file ; press_any_key ;;
	        2) install_update ; press_any_key ;;
	        3) check_private_network ; press_any_key ;;
	        4) apply-config ; press_any_key ;;

		0) clear; exit 0 ;;
		*) echo -e $red"Wrong option."$clear; sleep 1; clear; menu;;
        esac
}

# RUN the script
RUN
