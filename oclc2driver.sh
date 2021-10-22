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
#
#################################################################
# Manon Barbeau
# OCLC - Training & Implementation Specialist-Specialiste en formation & implantation, OCLC Canada
# 9955 Chateauneuf, Suite 135, Brossard, Quebec Canada J4Z 3V5
# T +1-888-658-6583 / 450-656-8955
## Note: there are no comments allowed in this file because the password may include a '#'. 
##       The script will however read only the last line of the file
## This script assumes that both a mixed (.mrc file) and cancel (.nsk file) were produced on ILS.
PATH=$PATH:/usr/bin:/bin:/home/ils/oclc/bin:
SERVER="sirsi@edpl.sirsidynix.net"
SFTP_USER=fx_cnedm
SFTP_SERVER=filex-r3.oclc.org
REMOTE_DIR=/xfer/metacoll/in/bib
WORK_DIR_AN=/home/ils/oclc
PASSWORD_FILE=$WORK_DIR_AN/oclc2.password.txt
PASSWORD=''
EMAILS="ilsadmins@epl.ca"
SUBMISSION_TAR_FILE='submission.tar'
REMOTE=/software/EDPL/Unicorn/EPLwork/cronjobscripts/OCLC2
VERSION="1.0.01"
################### Functions.


## Set up logging.
LOG_FILE="$WORK_DIR_AN/load.log"
# Logs messages to STDOUT and $LOG_FILE file.
# param:  Message to put in the file.
# param:  (Optional) name of a operation that called this function.
logit()
{
    local message="$1"
    local time=$(date +"%Y-%m-%d %H:%M:%S")
    if [ -t 0 ]; then
        # If run from an interactive shell message STDOUT and LOG_FILE.
        echo -e "[$time] $message" | tee -a $LOG_FILE
    else
        # If run from cron do write to log.
        echo -e "[$time] $message" >>$LOG_FILE
    fi
}

# Reads the password file for the SFTP site.
get_password()
{
	# Tests, then reads the password file which is expected to be in the current working directory.
	if [ -s "$PASSWORD_FILE" ]; then
		PASSWORD=$(cat "$PASSWORD_FILE" | /home/ils/bin/pipe.pl -zc0 -L-1)
		if [ -z "${PASSWORD}" ]; then
			logit "*** error, the PASSWORD variable is unset, exiting."
			exit 1
		fi
	else
		logit "** error, password file '$PASSWORD_FILE' missing or empty!"
		exit 1
	fi
}
################ end Functions
logit "== Starting $0 version $VERSION"
hostname=$(hostname)
logit "changing to '$WORK_DIR_AN' on '$hostname'"
cd $WORK_DIR_AN || exit 1
# Include '/' because when the mrc files are untarred, the directory tree starts in the $WORK_DIR_AN or '/home/ils/oclc/bin'.
logit "SCP: copying submission tarball from $REMOTE to $hostname."
scp $SERVER:/$REMOTE/$SUBMISSION_TAR_FILE .
if [ -f "$SUBMISSION_TAR_FILE" ]; then
	# Untar the .mrc and .nsk files.
	if tar xvf $SUBMISSION_TAR_FILE >> $WORK_DIR_AN/load.log 2>&1; then
		logit "$SUBMISSION_TAR_FILE un-tarred successfully"
	else
		logit "TAR: failed to un-tar MRC file from ILS. Did you run oclc2.sh in mix mode?"
		exit 1
	fi
    if ! ls *.nsk >/dev/null 2>&1; then
        if ! ls *.mrc >/dev/null  2>&1; then
            results=$(echo -e "\n--snip tail of log file--\n"; tail -25 $WORK_DIR_AN/load.log)
            echo -e "**error no files found in $SUBMISSION_TAR_FILE..\n $results \n Check for $SUBMISSION_TAR_FILE on ILS." | mailx -a'From:ils@epl-ils.epl.ca' -s"OCLC2 failed!" $EMAILS
            exit 1
        fi
    fi
	# Start the SFTP process.
	get_password
	logit "sending nsk and mrc file(s) to $SFTP_SERVER"
	export SSHPASS="${PASSWORD}"
    ### Comment out the next 6 lines to test without sending files to OCLC.
	sshpass -e sftp -oBatchMode=no $SFTP_USER\@$SFTP_SERVER << !END_OF_COMMAND >> $WORK_DIR_AN/load.log 2>&1
cd $REMOTE_DIR
put *.mrc
put *.nsk
bye
!END_OF_COMMAND
	### lines below for testing.
# 	sshpass -e sftp -oBatchMode=no $SFTP_USER\@$SFTP_SERVER << !END_OF_COMMAND
# cd $REMOTE_DIR
# dir
# bye
# !END_OF_COMMAND
    ### Comment out above to test without sending files to OCLC.
    # Post processing and reporting.
	if [[ $? ]]; then
		logit "sftp successful"
		logit "cleaning up '$WORK_DIR_AN/$SUBMISSION_TAR_FILE'"
		rm $WORK_DIR_AN/$SUBMISSION_TAR_FILE
		logit "removing tarball from ILS."
        ### Commented out the next line if you don't want to remove submission.tar file from production.
		ssh $SERVER "rm $REMOTE/$SUBMISSION_TAR_FILE" >> $WORK_DIR_AN/load.log 2>&1
		rm *.mrc >> $WORK_DIR_AN/load.log 2>&1 # there may not be a mrc if only cancels were run.
		rm *.nsk >> $WORK_DIR_AN/load.log 2>&1 # there may not be a nsk if only mixed were run.
		logit "completed successfully."
		echo "Files successfully sent to OCLC." | mailx -a'From:ils@epl-ils.epl.ca' -s"OCLC2 Upload complete" $EMAILS
        DATE=$(date +%Y%m%d)
        echo "$DATE" | ssh $SERVER "cat - >> $REMOTE/oclc2.last.run"
	else
		logit "failed to sftp."
		results=$(echo -e "\n--snip tail of log file--\n"; tail -25 $WORK_DIR_AN/load.log)
		echo -e "Uhoh, something went wrong while SFTP'ing to OCLC.\n$results" | mailx -a'From:ils@epl-ils.epl.ca' -s"OCLC2 Upload failed" $EMAILS
	fi
else
	logit "**Error: unable to scp '$WORK_DIR_AN/$SUBMISSION_TAR_FILE'"
fi
logit "== End =="
# EOF
