#!/bin/bash

#[[ $(id -u) -ne 0 ]] && echo "$0 needs to run as root to read SMART data." && exit 3

DEVS=`find /dev/disk/by-id/ -iname '*ata*' -and -not -iname '*part*' -and -not -iname '*QEMU_DVD-ROM*' -ls | gawk  '{print $13}' | cut -f3 -d/ | sed -e 's/\(.*\)/\/dev\/\1/'|sort -u`
DEVS=`echo $DEVS`

if [ -f /etc/nagios/check_smart_devs ]
then
	. /etc/nagios/check_smart_devs
	# Example for SATA disks on MeraRaid
	# DEVS="/dev/sda /dev/sdb /dev/sdc /dev/sdd /dev/sde /dev/sdf /dev/sdg /dev/sdh"
	
	# Example for cciss devices:
	# DEVS=/dev/disk/by-id/scsi-3600508b1001ca3f8143d49dd19bd2e1d
	# DEVS="$DEVS /dev/disk/by-id/scsi-3600508b1001ca3f8143d49dd19bd2e1d"
	# DEVS="$DEVS /dev/disk/by-id/scsi-3600508b1001ca3f8143d49dd19bd2e1d"
	# DEVS="$DEVS /dev/disk/by-id/scsi-3600508b1001ca3f8143d49dd19bd2e1d"
	# DEVS="$DEVS /dev/disk/by-id/scsi-3600508b1001ca3f8143d49dd19bd2e1d"
	# DEVS="$DEVS /dev/disk/by-id/scsi-3600508b1001ca3f8143d49dd19bd2e1d"
	# DEVS="$DEVS /dev/disk/by-id/scsi-3600508b1001ca3f8143d49dd19bd2e1d"
	# DEVS="$DEVS /dev/disk/by-id/scsi-3600508b1001ca3f8143d49dd19bd2e1d"
	# 
	# RAIDDEVS=8
	# RAIDTYPE=cciss

fi
#DEVS=/dev/sda
OUT=`mktemp`
ERRORDEVICES=''
NAGIOS_OUTPUT=`mktemp`
SMARTCTL=smartctl

function check_ata_error_count()
{
	$SMARTCTL --quietmode=errorsonly --log=error $1 > $OUT

	if [[ `cat $OUT | wc -l` -eq 0 ]]
	then
		echo 0
	else
		echo "" >> $NAGIOS_OUTPUT
		echo "ATA Error log: $1 [$devcnt]" >> $NAGIOS_OUTPUT
		cat $OUT >> $NAGIOS_OUTPUT
		NUM=`cat $OUT | grep 'ATA Error Count:'| sed -e 's/^ATA Error Count: \([0-9]\+\) .*/\1/g'`
		#device_info $1
		echo $NUM
	fi
	
}

function check_health() 
{
	RET=`$SMARTCTL -H $1 | grep -vq ": PASSED"`
	echo $?
}

function check_attribute()
{
	LINE=`$SMARTCTL -A $1 | grep "$2"`
	RET=`echo $LINE | gawk '{print $10}'`
	if [[ $RET -gt 0 ]]
	then
		echo "" >> $NAGIOS_OUTPUT
		echo $1 [$devcnt] $LINE >> $NAGIOS_OUTPUT
		#device_info $1 >> $NAGIOS_OUTPUT
	fi
	echo $RET
}

function device_info() 
{
	echo ""
	echo $1 [$devcnt]
	$SMARTCTL -a $1 | egrep "Device Model|Serial Number|User Capacity|Power_On_Hours"
}

if [ -z "$DEVS" ]
then
	echo "OK, No ATA/SATA devices found (virtual? hw-raid?)"
	/bin/rm $OUT $NAGIOS_OUTPUT
	exit 0
fi

let devcnt=0
for dev in $DEVS
do

	if [[ x$RAIDTYPE != "x" ]]
	then
		SMARTCTL="smartctl --device=$RAIDTYPE,$devcnt"
	fi

	errors=`check_ata_error_count $dev`
	health=`check_health`
	attr1=`check_attribute $dev "Offline_Uncorrectable"`
	attr2=`check_attribute $dev "Reported_Uncorrect"`
	#attr3=`check_attribute $dev "Seek_Error_Rate"`
	#attr4=`check_attribute $dev "UDMA_CRC_Error_Count"`
	#attr5=`check_attribute $dev "Hardware_ECC_Recovered"`
	attr6=`check_attribute $dev "Reallocated_Sector_Ct"`
	attr7=`check_attribute $dev "Current_Pending_Sector"`
	#attr8=`check_attribute $dev "Media_Wearout_Indicator"`
	attr9=`check_attribute $dev "End-to-End_Error"`

    let RESULTS[$devcnt]=0
	if [ ! -z $errors ]; then let RESULTS[$devcnt]=${RESULTS[$devcnt]}+$errors; fi
	if [ ! -z $health  ]; then let RESULTS[$devcnt]=${RESULTS[$devcnt]}+$health; fi
	if [ ! -z $attr1  ]; then let RESULTS[$devcnt]=${RESULTS[$devcnt]}+$attr1; fi
	if [ ! -z $attr2  ]; then let RESULTS[$devcnt]=${RESULTS[$devcnt]}+$attr2; fi
	#if [ ! -z $attr3  ]; then let RESULTS[$devcnt]=${RESULTS[$devcnt]}+$attr3; fi
	#if [ ! -z $attr4  ]; then let RESULTS[$devcnt]=${RESULTS[$devcnt]}+$attr4; fi
	#if [ ! -z $attr5  ]; then let RESULTS[$devcnt]=${RESULTS[$devcnt]}+$attr5; fi
	if [ ! -z $attr6  ]; then let RESULTS[$devcnt]=${RESULTS[$devcnt]}+$attr6; fi
	if [ ! -z $attr7  ]; then let RESULTS[$devcnt]=${RESULTS[$devcnt]}+$attr7; fi
	#if [ ! -z $attr8  ]; then let RESULTS[$devcnt]=${RESULTS[$devcnt]}+$attr8; fi
	if [ ! -z $attr9  ]; then let RESULTS[$devcnt]=${RESULTS[$devcnt]}+$attr9; fi

	if [[ ${RESULTS[$devcnt]} -gt 0 ]]
	then
		ERRORDEVICES="$ERRORDEVICES $dev [$devcnt]"
	fi
	let TOTAL=$TOTAL+${RESULTS[$devcnt]}
    let devcnt++
done


if [[ $TOTAL -gt 0 ]];
then
	echo "WARNING: SMART Errors found on disks $ERRORDEVICES [TOTAL: $TOTAL]"
	cat $NAGIOS_OUTPUT
	echo ""
	echo "Device info:"
	for disk in `cat $NAGIOS_OUTPUT | grep ^/dev | cut -f1 -d" " | sort -u`
	do
		device_info $disk
	done
	/bin/rm $OUT $NAGIOS_OUTPUT
	exit 1
else
	/bin/rm $OUT $NAGIOS_OUTPUT 
	echo "OK, no SMART errors found on $DEVS"
fi
