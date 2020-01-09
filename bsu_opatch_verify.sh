#!/bin/bash
#set -x
#clear
HOST=`hostname`
PATCHOP="/tmp/patchop.txt"
rm ${PATCHOP} &>/dev/null

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

mw_home
weblogic_home
java_home
wls_version
patch_file_check

export ORACLE_HOME=$MHME
export JAVA_HOME=$JHME

if [[ "$PFC" != "Patch file not found" ]]; then
  if [[ ! -z $(echo $PFC | grep "bsu.sh") ]]; then
    cd $MHME/utils/bsu/
    ./bsu.sh -prod_dir=$WHME -status=applied -view -verbose 2>/dev/null > ${PATCHOP}
    if [[ $(echo $?) == 0 ]]; then
      BSUOPT=$(cat ${PATCHOP} | grep -w "Patch ID:" | awk -F "Patch ID:" '{print $2}' | awk '{print $NF}' | tr '\n' ' ')
      if [[ ! -z $BSUOPT ]]; then
        echo -e "$HOST - $BSUOPT"
      else
        echo -e "$HOST - NO Patch ID Found"
      fi
    else
      clear
      echo -e "\nPlease Edit: $MHME/utils/bsu/bsu.sh\n\nMW_HOME=\"$MHME\"\nWL_HOME=\"$WHME\"\nJAVA_HOME=\"$JHME\"\n"
      cd $MHME/utils/bsu/
      ./bsu.sh -prod_dir=$WHME -status=applied -view -verbose 2>${PATCHOP}
      echo -e "$HOST - Error : $(cat ${PATCHOP})\n\n"
    fi
  elif [[ ! -z $(echo $PFC | grep "opatch") ]]; then
    cd ${MHME}/OPatch
	./opatch lsinventory 2>/dev/null > ${PATCHOP}
	cat ${PATCHOP} | grep applied
  else
    echo "Some issue running patch check"
  fi
else
  echo -e "Invalid domain..."
fi  
#rm ${PATCHOP} &>/dev/null
