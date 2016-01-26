#!/bin/bash
#########################################################################
# Backup script for minecraft servers with SCP to another site.		#
# Stops and starts specified minecraft server for 100% backups.		#
# Supports multiple minecraft servers on the same machine		#
#									#
# Author								#
# Pierre Christoffersen, www.nahaz.se					#
# Feel free to redistribute, change or improve, but leave original	#
# authors and contributers in comments.					#
# http://github.com/Nahaz/Minecraft-Backup-Bash-Script			#
#									#
# Exitcodes:								#
# 0=Completed with no errors						#
# 1=Backupd done, server not restarted					#
# 2=Failed								#
# 									#
# Variables used:							#
#									#
# Minecraft-server related:						#
# MCDIR=/Dir/to/minecraft/server					#
# MCSRV=Name of server.jar used						#
# JXMS=512M #Amount of minimum ram for JVM 				#
# JXMX=3072M #Amount of maximum ram for JVM				#
# GUI=nogui #nogui, don't change, only a var for future purposes	#
# WORLDNAME=Name of minecraft world					#
# SCREEN=Screen name minecraft server is running in			#
#									#
# Server restart/stop timer and message					#
# TIME=60 #Countdown in seconds to shutdown server			#
# MSG="Server restarting in "$TIME" seconds, back in a minute!"		#
# TRIES=3 #Number of tries to start/stop server before giving up	#
#									#
# Temporary directory and remote site for backup			#
# TMPDIR=/dir/to/tmp							#
# BCKSRV=HOSTNAME #Hostname of backupserver				#
# BCKDIR=/dir/on/backupserver/to/store/in				#
#									#
# Don't change these unless you understand what you're doing		#
# LOG=$TMP/mc.$WORLDNAME.fullbck.log					#
# OF=/tmp/$FILE								#
# BUDIR=$MCDIR/$WORLDNAME						#
# FILE=$WORLDNAME.$TIMESTAMP.fullbck.tar.gz				#
# TIMESTAMP=$(date +%y%m%d.%T)						#
# LOGSTAMP=$(date +%y%m%d\ %T)						#
#########################################################################

#Minecraft properties
MCDIR=
MCSRV=
JXMS=
JXMX=
GUI=nogui
WORLDNAME=world
SCREEN=mc

#Restart properties
TIME=30
MSG="Server restarting in "$TIME" seconds, back in a minute!"
TRIES=3

#Backup vars
TMPDIR=
BCKSRV=
BCKDIR=

#no need to change these
TIMESTAMP=$(date +%y%m%d.%T)
LOGSTAMP=$(date +%y%m%d\ %T)

LOGFILE=$TMPDIR/mc.$WORLDNAME.fullbck.log
BUDIR=$MCDIR/$WORLDNAME
FILE=$WORLDNAME.$TIMESTAMP.fullbck.tar.gz
OF=$TMPDIR/$FILE

#nifty functions, don't edit anything below

#Check if minecraft server is running, ONLINE == 1 if offline, ONLINE == 2 if running
function srv_check () {
	ONLINE=$(ps aux | grep "java -Xms$JXMS -Xmx$JXMX -jar $MCSRV $GUI" | wc -l)
}

function log () {
	echo "[${LOGSTAMP}] ${@}" >> $LOGFILE
}

#Kill minecraft server, but post $MSG to server $TIME before shutdown and warn 5 seconds before shutdown. If "stop" don't work, kill $PID.
function kill_mc() {
	screen -S $SCREEN -p 0 -X stuff "`printf "say $MSG\r"`"; sleep $TIME
	screen -S $SCREEN -p 0 -X stuff "`printf "say Going down in 10 seconds! Saving world...\r"`"
	screen -S $SCREEN -p 0 -X stuff "`printf "save-all\r"`"; sleep 5
	screen -S $SCREEN -p 0 -X stuff "`printf "stop\r"`"; sleep 5
	srv_check
	if [ $ONLINE == 1 ]; then
		log "Minecraft server shutdown successfully."
	else
		log "Minecraft server did NOT shutdown, will try with force."
		local PID=$(ps -e | grep "java -Xms$JXMS -Xmx$JXMX -jar $MCSRV $GUI" | grep -v grep | awk '{print $1;}')
		local STOP=$TRIES
		while [[ $STOP -gt 0 && $ONLINE == 2 ]]; do
			log "Try #${STOP} of stopping minecraft server."
			kill $PID
			srv_check
			STOP=$(($STOP-1))
		done
		if [ $STOP == 0 ]; then
			log "Could not kill minecraft server, exiting"
			exit 2
		else
			log "Killed minecraft server after ${STOP} number of tries, proceeding with full backup."
		fi
	fi
}
#Start minecraft server with $PARAMS
function start_mc() {
	function java_start() {
		screen -S $SCREEN -p 0 -X stuff "`printf "cd $MCDIR\r"`"; sleep 1
		screen -S $SCREEN -p 0 -X stuff "`printf "java -Xms$JXMS -Xmx$JXMX -jar $MCSRV $GUI\r"`"; sleep 3
	}
	local PARAMS="screen -dmS $SCREEN java -Xms$JXMS -Xmx$JXMX -jar $MCSRV $GUI"
	java_start
	srv_check
	if [ $ONLINE == 2 ]; then
		log "Server started successfully with ${PARAMS}."
	else
		log "Server did not start, trying again."
		local START=0
		local SCREXIST=$(ps aux | grep "SCREEN -dmS $SCREEN" | wc -l)
		while [[ $START -lt 3 && $ONLINE == 1 ]]; do
			log "Try #"$START" of starting minecraft server."
			SCREXIST=$(ps aux | grep "SCREEN -dmS $SCREEN" | wc -l)
			if [ $SCREXIST == 1 ]; then
				log "Screen session not found, starting screen with -dmS ${SCREEN}."
				screen -dmS $SCREEN; sleep 1
				java_start
			else
				java_start
			fi
			srv_check
			START=$(($START+1))
		done
		if [ $START == 3 ]; then
			log "Server did not start after ${START} number of tries, exiting."
			exit 1
		else
			log "Server started after ${START} number of tries with ${PARAMS}"
			log "Backup complete."
			exit 0
		fi
	fi
}
function run_backup() {
#Backup dir, output to $LOG
tar -czf $OF $BUDIR
if [ $? == 0 ]; then
	log "TAR of ${BUDIR} to ${OF} was successful."
elif [ $? == 1 ]; then
	log "TAR of ${BUDIR} to ${OF} was successful, but backup is not 100% of ${BUDIR}, most likely because it was changed during reading."
else
	log "TAR of ${BUDIR} to ${OF} was NOT successful, reason: ${?} FATAL ERROR."
fi
#SCP backup to $BCKSRV, output to $LOG
scp $OF $BCKSRV:$BCKDIR
if [ $? == 0 ]; then
	log "SCP of ${OF} to ${BCKSRV} was successful."
else
	log "SCP of ${OF} to ${BCKSRV} was NOT successful, reason: ${?}:Some error ocurred."
fi

log "Proceeding to start server..."
start_mc
}

#Is minecraft server running? yes - stop then continue, no - continue
log "Beginning full backup of ${BUDIR}"
case "$1" in
	backup)
		srv_check
		if [ $ONLINE == 2 ]; then
			kill_mc
		if [ $ONLINE == 1 ]; then
			run_backup
		fi
		else
			run_backup
		fi
	;;
	restart)
		srv_check
		if [ $ONLINE == 2 ]; then
			kill_mc
		fi
		start_mc
	;;
	stop)
		kill_mc
	;;
	start)
		start_mc
	;;
	status)
		srv_check
		if [ $ONLINE == 2 ]; then
			echo "Server is running"
		elif [ $ONLINE == 1 ]; then
			echo "Server is not running"
		fi
	;;
esac
