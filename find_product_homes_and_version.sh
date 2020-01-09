#!/bin/bash
#set -x
#clear
HOST=`hostname`

mw_home() {              #MHME      #/opt/ dependency
  MOPS=$(find /opt/ -type f -maxdepth 4 -name "registry.xml" 2>/dev/null | sort -u)
  for i in $MOPS; do
    if [[ ! -z $(cat $i | grep -i "WebLogic Server") ]]; then MOP=$i; fi
  done
  if [[ ! -z $(echo $MOP | grep "inventory") ]]; then
    MHME=`echo ${MOP%/*/*}`
  else
    MHME=`echo ${MOP%/*}`
  fi
}

weblogic_home() {        #WHME      #Dependency MHME
  if [[ ! -z $MHME ]]; then
    WHMEs=$(find "$MHME" -type d -maxdepth 1 -iname "*wlserver*" 2>/dev/null | sort -u)
    for WH in $WHMEs; do
      if [[ -f "$WH/server/bin/setWLSEnv.sh" ]]; then WHME=$WH; fi
    done
    if [[ -z $WHME ]]; then WHME=$(cat $MOP | grep "WebLogic Server" | awk -F 'InstallDir=' '{print $2}' | cut -d '"' -f2 | grep -v "^$"); fi
  else
    WHME=""
  fi
}

java_home() {            #JHME      #/opt/oracle dependency
  JOPS=$(find /opt/oracle -maxdepth 4 -type f -name "java" 2>/dev/null | sort -u)
  if [[ $(echo $JOPS | wc -w) -gt 1 ]]; then
    for j in $JOPS; do 
      if [[ ! -z $(ps -ef | grep java | grep "weblogic.Server" | grep -v grep | grep $j) ]]; then JOP=$j; fi 
    done
  else
    JOP=$JOPS
  fi
  if [[ -z $JOP ]]; then JOP=$JOPS; fi
  JHME1=$(echo $JOP | awk -F '/bin/java' '{print $1}')
  JHME2=$(cat $WHME/common/bin/commEnv.sh 2>/dev/null | grep -w "JAVA_HOME=" | cut -d'"' -f2)
  if [[ -z $JHME1 ]]; then
    JHME=$JHME2
  elif [[ -z $JHME2 ]]; then
    JHME=$JHME1
  elif [[ "$JHME1" == "$JHME2" ]]; then 
    JHME=$JHME1
  elif [[ "$JHME1" != "$JHME2" ]]; then 
    JHME=$JHME1
  else 
    JHME=$JHME1
  fi
}

wls_version() {          #WLSVER    #Dependency MHME, JHME
  c=1
  while [[ $c -le 3 ]]; do
  export WL_HOME=$WHME
  export JAVA_HOME=$JHME
  . $WL_HOME/server/bin/setWLSEnv.sh &>/dev/null
  WLSVER=$($JAVA_HOME/bin/java weblogic.version 2>/dev/null | grep "WebLogic Server" | grep -iv "Patch" | grep [0-9] | awk '{print $3}' | tr '\n' ' ')
  ((++c))
  done
}

patch_file_check() {     #PFC       #Dependency MHME, WLSVER
  if [ ! -z $WLSVER ]; then
    WLVER=$(echo $WLSVER | awk -F "." '{print $1}')
    if [ $(bc <<< "$WLVER >= 10") -eq 1 ] && [ $(bc <<< "$WLVER < 11") -eq 1 ]; then
      export WLVER=11
      if [[ -f ${MHME}/utils/bsu/bsu.sh ]]; then
        PFC=$(echo "${WLVER}g - ${MHME}/utils/bsu/bsu.sh")
      else
        PFC=$(echo "Patch file not found")
      fi
    elif [ $(bc <<< "$WLVER >= 11") -eq 1 ] && [ $(bc <<< "$WLVER < 13") -eq 1 ]; then
      export WLVER=12
      if [[ -f ${MHME}/OPatch/opatch ]]; then
        PFC=$(echo "${WLVER}c - ${MHME}/OPatch/opatch")
      else
        PFC=$(echo "Patch file not found")
      fi
    else
      PFC=$(echo -e "Invalid version $WLSVER")
    fi
  else
    PFC=$(echo -e "Not a valid domain")
  fi
}

MHME_owner_group() {     #Dependency MHME
  if [[ -z $MHME ]]; then
    echo -e "  owner: "
    echo -e "  group: "
  else
    echo -e "  owner: $(ls -ld $MHME | awk '{print $3}')"
    echo -e "  group: $(ls -ld $MHME | awk '{print $4}')"
  fi
}

ohs_home_ver() {         #OHS_HOME OHS_VER WIH
  export OHS_HOME=$(echo `find /opt/oracle -name "httpd" 2>/dev/null | grep -v "patch_storage" | head -1` | awk -F "/bin" '{print $1}')
  if [[ ! -z $OHS_HOME ]]; then
    export LD_LIBRARY_PATH=$OHS_HOME/lib:$OHS_HOME/../lib:$OHS_HOME/../oracle_common/lib
    OHS_VER=$($OHS_HOME/bin/httpd -version | grep "Server version" | cut -d ':' -f2)
    WIH=$(find $OHS_HOME/ -type f -name "cwallet.sso" 2>/dev/null  | grep "/webgate/config/" | awk -F "/webgate/config/" '{print $1}')
  fi	
}

mw_home
weblogic_home
java_home
wls_version
patch_file_check
ohs_home_ver

#output_print
echo -e "\e[1m                Host :\e[0m $HOST"
echo -e "\e[1m            java_home:\e[0m $JHME"
echo -e "\e[1m              mw_home:\e[0m $MHME"
echo -e "\e[1m              wl_home:\e[0m $WHME"
echo -e "\e[1m           wl_version:\e[0m $WLSVER"
echo -e "\e[1m       patch_file_loc:\e[0m $PFC"
echo -e "\e[1m             ohs_home:\e[0m $OHS_HOME"
echo -e "\e[1m          ohs_version:\e[0m $OHS_VER"
echo -e "\e[1mWebgate_Instance_Home:\e[0m $WIH"
