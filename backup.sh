#!/bin/bash

# 18/08/29 note: add mpack command to send a backup mail attached log file.

# ======================== CHANGE THESE VALUES ========================
function stopServices 
{
	echo -e "Stopping services before backup" | tee -a $DIR/backup.log
    	sudo service cron stop
    	sudo service ssh stop
    	sudo service apache2 stop
    	sudo service smbd stop
    	sudo service nmbd stop
}

function startServices 
{
	echo -e "Starting the stopped services$" | tee -a $DIR/backup.log
	sudo service cron start
	sudo service ssh start
	sudo service apache2 start
	sudo service smbd start
	sudo service nmbd start
}

# Setting up directories
SUBDIR=pi-backup
MOUNTPOINT=/media/usb-drive
DIR=$MOUNTPOINT/$SUBDIR	
RETENTIONPERIOD=0 		# don't keep old backup file
POSTPROCESS=1 			# 1 to use a postProcessSucess function after successfull backup
GZIP=0 				# whether to gzip the backup or not

# Setting for mail
MAILRECEIVER=aa774281@gmail.com

# Function which tries to mount MOUNTPOINT
function mountMountPoint 
{
    # mount all drives in fstab (that means MOUNTPOINT needs an entry there)
    mount -a
}


function postProcessSucess {
	# Update Packages and Kernel
	echo -e "Update Packages and Kernel" | tee -a $DIR/backup.log
    	sudo apt-get update
    	sudo apt-get upgrade -y
    	sudo apt-get autoclean

    	#echo -e "${yellow}Update Raspberry Pi Firmware${NC}${normal}" | tee -a $DIR/backup.log
    	#sudo rpi-update
    	#sudo ldconfig

    	# Reboot now
    	#echo -e "${yellow}Reboot now ...${NC}${normal}" | tee -a $DIR/backup.log
    	#sudo reboot
}

# =====================================================================

# setting up echo fonts
red='\e[0;31m'
green='\e[0;32m'
cyan='\e[0;36m'
yellow='\e[1;33m'
purple='\e[0;35m'
NC='\e[0m' #No Color
bold=`tput bold`
normal=`tput sgr0`

# Check if mount point is mounted, if not quit!
if ! mountpoint -q "$MOUNTPOINT" ; then
    echo -e "Destination is not mounted; attempting to mount ..."
    mountMountPoint
    if ! mountpoint -q "$MOUNTPOINT" ; then
        echo -e "Unable to mount $MOUNTPOINT; Aborting!"
        exit 1
    fi
    echo -e "Mounted $MOUNTPOINT; Continuing backup"
fi


#LOGFILE="$DIR/backup_$(date +%Y%m%d_%H%M%S).log"

# Check if backup directory exists
if [ ! -d "$DIR" ];
   then
      mkdir $DIR
	  echo -e "Backup directory $DIR didn't exist, I created it"  | tee -a $DIR/backup.log
fi

echo -e "Starting RaspberryPI backup process!" | tee -a $DIR/backup.log
echo "____ BACKUP ON $(date +%Y/%m/%d_%H:%M:%S)" | tee -a $DIR/backup.log
echo ""
# First check if pv package is installed, if not, install it first
PACKAGESTATUS=`dpkg -s pv | grep Status`;

if [[ $PACKAGESTATUS == S* ]]
   then
      echo -e "Package 'pv' is installed" | tee -a $DIR/backup.log
      echo ""
   else
      echo -e "Package 'pv' is NOT installed" | tee -a $DIR/backup.log
      echo -e "Installing package 'pv' + 'pv dialog'. Please wait..." | tee -a $DIR/backup.log
      echo ""
      sudo apt-get -y install pv && sudo apt-get -y install pv dialog
fi

# Remove previous backup img files
cd $DIR
sudo /bin/rm *.img
echo -e "${yellow}Remove previous image file.....done!" 

# Create a filename with datestamp for our current backup
OFILE="$DIR/backup_$(hostname)_$(date +%Y%m%d_%H%M%S)".img

# First sync disks
sync; sync

# Shut down some services before starting backup process
stopServices

# Begin the backup process, should take about 45 minutes hour from 8Gb SD card to HDD
echo -e "Backing up SD card to img file on HDD" | tee -a $DIR/backup.log
SDSIZE=`sudo blockdev --getsize64 /dev/mmcblk0`;
if [ $GZIP = 1 ];
	then
		echo -e "${green}Gzipping backup${NC}${normal}"
		OFILE=$OFILE.gz # append gz at file
        	sudo pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd  bs=1M conv=sync,noerror iflag=fullblock | gzip > $OFILE
	else
		echo -e "${green}No backup compression${NC}${normal}"
		sudo pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd of=$OFILE bs=1M conv=sync,noerror iflag=fullblock
fi

# Wait for DD to finish and catch result
BACKUP_SUCCESS=$?

# Start services again that where shutdown before backup process
startServices

# If command has completed successfully, delete previous backups and exit
if [ $BACKUP_SUCCESS =  0 ];
then
      	echo -e "RaspberryPI backup process completed! FILE: $OFILE" | tee -a $DIR/backup.log
      	echo -e "Removing backups older than $RETENTIONPERIOD days" | tee -a $DIR/backup.log
      	sudo find $DIR -maxdepth 1 -name "*.img" -o -name "*.gz" -mtime +$RETENTIONPERIOD -exec rm {} \;
	echo -e "If any backups older than $RETENTIONPERIOD days were found, they were deleted" | tee -a $DIR/backup.log
      	#echo "Hello I'm pi, ur backup data is copied to usb flash device." | mail -s Backup $MAILRECEIVER
	mpack -s BackupIsSuccessfully. -d /home/mermaid/cronjobs/backup-message.txt /media/usb-drive/pi-backup/backup.log $MAILRECEIVER
	
	if [ $POSTPROCESS = 1 ] ;
	then
		postProcessSucess
	fi
	exit 0
else 
     # Else remove attempted backup file
     	echo -e "Backup failed!" | tee -a $DIR/backup.log
     	sudo rm -f $OFILE
     	echo -e "Last backups on HDD:" | tee -a $DIR/backup.log
     	sudo find $DIR -maxdepth 1 -name "*.img" -exec ls {} \;
     	#echo "Hello I'm pi, ur backup data is failed, please check all configs in backup process." | mail -s Backup aa774281@gmail.com
	mpack -s BackupIsUnsuccessfully. -d /home/mermaid/cronjobs/backup-message.txt /media/usb-drive/pi-backup/backup.log $MAILRECEIVER
     	exit 1
fi
