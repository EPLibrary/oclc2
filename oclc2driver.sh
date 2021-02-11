#!/bin/bash
#################################################################
#
# Bash shell script uploading data from OCLC Data Sync project.
#
# Collect and submit Data Sync Collections data for OCLC.
#    Copyright (C) 2016  Andrew Nisbet
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# Author:  Andrew Nisbet, Edmonton Public Library
# Rev:
#          1.6.00 - This script now updates the oclc2.last.run file once the 
#                   submission has successfully been sftp'd.   
#                   File found in /s/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC2.
#          1.5.03 - Added more detailed reporting.  
#          1.5.02 - Fix redirect error that stopped script from completing.  
#          1.5.01 - Limit error log output in emails to 25 lines.  
#          1.5 - Change testing and don't exit if there wasn't an mrc and nsk,  
#                it run in cancel or mixed mode their may not be one or the other.
#          1.0 - Marc files from EPLAPP are no longer deeply nested.
#          0.1 - Updated to mail results on completion.
#          0.0 - Dev.
#
#################################################################
# Manon Barbeau
# OCLC - Training & Implementation Specialist-Specialiste en formation & implantation, OCLC Canada
# 9955 Chateauneuf, Suite 135, Brossard, Quebec Canada J4Z 3V5
# T +1-888-658-6583 / 450-656-8955
## Note: there are no comments allowed in this file because the password may include a '#'. 
##       The script will however read only the last line of the file
## This script assumes that both a mixed (.mrc file) and cancel (.nsk file) were produced on EPLAPP.
PATH=$PATH:/usr/bin:/bin:/home/ilsdev/projects/oclc2
SHELL=/bin/bash
SFTP_USER=fx_cnedm
SFTP_SERVER=filex-r3.oclc.org
REMOTE_DIR=/xfer/metacoll/in/bib
WORK_DIR_AN=/home/ilsdev/projects/oclc2
PASSWORD_FILE=$WORK_DIR_AN/oclc2.password.txt
PASSWORD=''
EMAILS="ilsadmins@epl.ca"
SUBMISSION_TAR_FILE='submission.tar' 
################### Functions.
# Reads the password file for the SFTP site.
get_password()
{
	# Tests, then reads the password file which is expected to be in the current working directory.
	if [ ! -s "$PASSWORD_FILE" ]; then
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s %s\n" $DATE_TIME "SCP: ** error unable to SFTP results becaues I can't find the password file:" $PASSWORD_FILE >> $WORK_DIR_AN/load.log
		exit 1
	fi
	PASSWORD=$(cat "$PASSWORD_FILE" | pipe.pl -zc0 -L-1)
	if [ ! "$PASSWORD" ]; then
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "SCP: *** failed to read password file." >> $WORK_DIR_AN/load.log
		exit 1
	fi
}
################ end Functions
DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
printf "[%s] %s\n" $DATE_TIME "INIT:init" >> $WORK_DIR_AN/load.log
REMOTE=s/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC2
# Include '/' because when the mrc files are untarred, the directory tree starts in the $WORK_DIR_AN or '/home/ilsdev/projects/oclc2'.
DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
hostname=$(hostname)
printf "[%s] %s\n" $DATE_TIME "SCP: copying submission tarball to $hostname." >> $WORK_DIR_AN/load.log
scp sirsi\@eplapp.library.ualberta.ca:/$REMOTE/$SUBMISSION_TAR_FILE $WORK_DIR_AN
if [ -f "$WORK_DIR_AN/$SUBMISSION_TAR_FILE" ]; then
	cd $WORK_DIR_AN
	# Untar the .mrc and .nsk files.
	tar xvf $SUBMISSION_TAR_FILE
	if ls *.mrc 2>&1>/dev/null; then
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "TAR: un-tarring MRC file from EPLAPP." >> $WORK_DIR_AN/load.log
	else
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "TAR: failed to un-tar MRC file from EPLAPP. Did you run oclc2.sh in mix mode?" >> $WORK_DIR_AN/load.log
	fi
	# Test for NSK file
	if ls *.nsk 2>&1>/dev/null; then
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "TAR: un-tarring nsk file from EPLAPP." >> $WORK_DIR_AN/load.log
	else
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "TAR: failed to un-tar nsk file from EPLAPP. Did you run oclc.sh in cancel mode?" >> $WORK_DIR_AN/load.log
	fi
    if ! ls *.nsk 2>&1>/dev/null; then
        if ! ls *.mrc 2>&1>/dev/null; then
            results=$(echo -e "\n--snip tail of log file--\n"; tail -25 $WORK_DIR_AN/load.log)
            echo -e "**error no files found in $SUBMISSION_TAR_FILE..\n $results \n Check for $SUBMISSION_TAR_FILE on EPLAPP." | mailx -a'From:ilsdev@ilsdev1.epl.ca' -s"OCLC2 failed!" $EMAILS
            exit 1
        fi
    fi
	# Start the SFTP process.
	get_password
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s %s\n" $DATE_TIME "sftp to " $SFTP_SERVER >> $WORK_DIR_AN/load.log
    printf "[%s] sending nsk file: " $DATE_TIME >> $WORK_DIR_AN/load.log
    echo $(ls -l $WORK_DIR_AN/*.nsk) >> $WORK_DIR_AN/load.log
    printf "[%s] sending mrc file: " $DATE_TIME >> $WORK_DIR_AN/load.log
    echo $(ls -l $WORK_DIR_AN/*.mrc) >> $WORK_DIR_AN/load.log
	export SSHPASS="$PASSWORD"
	# If this technique doesn't work try the one below.
	# if sshpass -p password sftp -oBatchMode=no user@serveraddress  << !
	# put file*
	# bye
	# !
    ### Comment out the next 6 lines to test without sending files to OCLC.
	sshpass -e sftp -oBatchMode=no $SFTP_USER\@$SFTP_SERVER << !END_OF_COMMAND
   cd $REMOTE_DIR
   put $WORK_DIR_AN/*.mrc
   put $WORK_DIR_AN/*.nsk
   bye
!END_OF_COMMAND
    ### Comment out above to test without sending files to OCLC.
    # Post processing and reporting.
	if [[ $? ]]; then
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "done sftp." >> $WORK_DIR_AN/load.log
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s %s\n" $DATE_TIME "removing tarball..." $WORK_DIR_AN/$SUBMISSION_TAR_FILE >> $WORK_DIR_AN/load.log
		rm $WORK_DIR_AN/$SUBMISSION_TAR_FILE
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "removing tarball from EPLAPP." >> $WORK_DIR_AN/load.log
        ### Commented out the next line if you don't want to remove submission.tar file from production.
		ssh sirsi\@eplapp.library.ualberta.ca "rm /s/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC2/$SUBMISSION_TAR_FILE" >&2 >> $WORK_DIR_AN/load.log
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "removing mrc files." >> $WORK_DIR_AN/load.log
		rm $WORK_DIR_AN/*.mrc 2>&1>/dev/null # there may not be a mrc if only cancels were run.
		rm $WORK_DIR_AN/*.nsk 2>&1>/dev/null # there may not be a nsk if only mixed were run.
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "completed successfully." >> $WORK_DIR_AN/load.log
		echo "Files successfully sent to OCLC." | mailx -a'From:ilsdev@ilsdev1.epl.ca' -s"OCLC2 Upload complete" $EMAILS
        DATE=$(date +%Y%m%d)
        echo "$DATE" | ssh sirsi\@eplapp.library.ualberta.ca 'cat - >> /s/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC2/oclc2.last.run'
	else
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "failed to sftp." >> $WORK_DIR_AN/load.log
		results=$(echo -e "\n--snip tail of log file--\n"; tail -25 $WORK_DIR_AN/load.log)
		echo -e "Uhoh, something went wrong while SFTP'ing to OCLC.\n$results" | mailx -a'From:ilsdev@ilsdev1.epl.ca' -s"OCLC2 Upload failed" $EMAILS
	fi
else
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s %s\n" $DATE_TIME "**Error: unable to scp" $WORK_DIR_AN/$SUBMISSION_TAR_FILE >> $WORK_DIR_AN/load.log
fi
DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
printf "[%s] %s\n" $DATE_TIME "######" >> $WORK_DIR_AN/load.log
# EOF
