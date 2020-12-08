#!/bin/bash

# This script will run every time after reboot BBB
# Pull in the helper functions for configuring BigBlueButton
source /etc/bigbluebutton/bbb-conf/apply-lib.sh
source ./data.sh

# Variables
if [[ ! $SCRIPT_ROOT/bbb-secret ]]
then
  bbb-conf --secret > $SCRIPT_ROOT/bbb-secret
fi
SECRET=$(sed -n -e '/Secret/ s/.*\= *//p' $SCRIPT_ROOT/bbb-secret)

# Create backup from BBB properties file
function backup_properties() {
  now=$(date +"%m_%d_%Y-%H_%M_%S")
  cp $BBB_PROP $SCRIPT_ROOT/backup/bigbluebutton.properties-$now
  echo "  - Backup bigbluebutton.properties ------------------------ [Ok]"
}

function apply_properties() {
  rm -rf $BBB_PROP
  cp $SCRIPT_ROOT/bigbluebutton.properties $BBB_PROP
  sleep 1
  sed -i "s,^bigbluebutton.web.serverURL=.*,bigbluebutton.web.serverURL=https://$FQDN,g" $BBB_PROP
  sleep 1
  sed -i "s,^screenshareRtmpServer=.*,screenshareRtmpServer=$FQDN,g" $BBB_PROP
  sleep 1
  sed -i "s,^securitySalt=.*,securitySalt=$SECRET,g" $BBB_PROP

  sleep 1
  chmod 444 $BBB_PROP
  echo "  - Apply change to bigbluebutton.properties --------------- [Ok]"
  sleep 1
}

function backup_settings() {
  now=$(date +"%m_%d_%Y-%H_%M_%S")
  cp $HTML5_CONFIG $SCRIPT_ROOT/backup/settings.yml-$now
  echo "  - Backup Settings file ----------------------------------- [Ok]"
}

function apply_settings() {
  API_KEY=$(yq r $HTML5_CONFIG private.etherpad.apikey)
  rm -rf $HTML5_CONFIG
  cp $SCRIPT_ROOT/settings.yml $HTML5_CONFIG

  # Last version of settings
  yq w -i $HTML5_CONFIG public.app.clientTitle DarsPlus Live Session
  yq w -i $HTML5_CONFIG public.app.appName DarsPlus client
  yq w -i $HTML5_CONFIG public.app.copyright "@2020 DarsPlus ltd."
  yq w -i $HTML5_CONFIG public.app.helpLink https://darsplus.com/liveclass/
  yq w -i $HTML5_CONFIG public.app.breakoutRoomLimit 2
  yq w -i $HTML5_CONFIG public.app.defaultSettings.application.overrideLocale fa
  yq w -i $HTML5_CONFIG public.kurento.wsUrl wss://$FQDN/bbb-webrtc-sfu
  yq w -i $HTML5_CONFIG public.captions.fontFamily Vazir
  yq w -i $HTML5_CONFIG public.note.enabled false
  yq w -i $HTML5_CONFIG public.note.url https://$FQDN/pad
  yq w -i $HTML5_CONFIG public.clientLog.external.enabled true
  yq w -i $HTML5_CONFIG private.etherpad.apikey $API_KEY

  sleep 1
  chmod 444 $HTML5_CONFIG
  chown 995:995 $HTML5_CONFIG
  echo "  - Apply new seeting to BBB setting.yml ------------------- [Ok]"
  sleep 1
}

# Add Vazir font to BBB HTML5 client
function vazir_font() {
    HEAD_FILE="/usr/share/meteor/bundle/programs/web.browser/head.html"
    CDN_LINK='<link href="https://cdn.jsdelivr.net/gh/rastikerdar/vazir-font@v26.0.2/dist/font-face.css" rel="stylesheet" type="text/css" />'
    CDN_ISTRUE=$(grep -Fxq $CDN_LINK $HEAD_FILE)
    if ! $CDN_ISTRUE
    then
        sed -i "2i$CDN_LINK" $HEAD_FILE
    fi
    sleep 1
    sed -i "s:Source Sans Pro:Vazir:g" $HEAD_FILE
    echo "  - Apply settings to heade.html ------------------------- [Ok]"
    sleep 1
}

function change_default_page() {
  rm -rf $DEFAULT_PAGE/* && cp -r $SCRIPT_ROOT/bigbluebutton-default/* $DEFAULT_PAGE/
  printf "  - Install default page for BBB --------------------------- [Ok]\n\n"
  sleep 1
}

function apply_config() {
# Latest version of properties
cat << EOF
╔══════════════════════════════════════════════╗
║                                              ║
║           Start to apply configs...!         ║
║       This script made for DarsPlus.com      ║
║ *** Attention: Don't run on your servers *** ║
╚══════════════════════════════════════════════╝

EOF
  printf "This script will run in 5 sec. Press Ctrl+C if you want to stop running the script!!!\n\n"
  sleep 5
  
  backup_properties
  apply_properties
  backup_settings
  apply_settings
  vazir_font
  change_default_page

  printf "Apply UFW rules...\n"
  enableUFWRules

cat << EOF

╔═════════════════════════════════════════════╗
║                                             ║
║       All setting done successfully         ║
║                                             ║
╚═════════════════════════════════════════════╝
EOF

}

# Apply config to BBB
apply_config