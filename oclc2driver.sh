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
#          0.1 - Updated to mail results on completion.
#          0.0 - Dev.
#
#################################################################
# Manon Barbeau
# OCLC � Training & Implementation Specialist-Sp�cialiste en formation & implantation, OCLC Canada
# 9955 Chateauneuf, Suite 135, Brossard, Qu�bec Canada J4Z 3V5
# T +1-888-658-6583 / 450-656-8955
## Note: there are no comments allowed in this file because the password may include a '#'. 
##       The script will however read only the last line of the file
export PATH=$PATH:/usr/bin:/bin:/home/ilsdev/projects/oclc2
export SHELL=/bin/bash
export SFTP_USER=cnedm
export SFTP_SERVER=scp-toronto.oclc.org
export REMOTE_DIR=/xfer/metacoll/in/bib
export HOME=/home/ilsdev/projects/oclc2
export PASSWORD_FILE=$HOME/oclc2.password.txt
PASSWORD=''
export EMAILS="anisbet@epl.ca"
FILE='submission.tar' 
################### Functions.
# Reads the password file for the SFTP site.
get_password()
{
	# Tests, then reads the password file which is expected to be in the current working directory.
	if [ ! -s "$PASSWORD_FILE" ]; then
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s %s\n" $DATE_TIME "SCP: ** error unable to SFTP results becaues I can't find the password file:" $PASSWORD_FILE >> $HOME/load.log
		exit 1
	fi
	PASSWORD=$(cat "$PASSWORD_FILE" | pipe.pl -zc0 -L-1)
	if [ ! "$PASSWORD" ]; then
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "SCP: *** failed to read password file." >> $HOME/load.log
		exit 1
	fi
}
################ end Functions
DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
printf "[%s] %s\n" $DATE_TIME "INIT:init" >> $HOME/load.log
REMOTE=s/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC2
# Include '/' because when the mrc files are untarred, the directory tree starts in the $HOME or '/home/ilsdev/projects/oclc2'.
DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
printf "[%s] %s\n" $DATE_TIME "SCP: copying submission tarball to this server." >> $HOME/load.log
scp sirsi\@eplapp.library.ualberta.ca:/$REMOTE/$FILE $HOME
if [ -f "$HOME/$FILE" ]
then
	cd $HOME
	tar xvf $FILE
	# The files will be in a sub-directory of 's/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC2/' because of the way they were tarred.
	if mv $REMOTE/*.mrc $HOME
	then
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "TAR: un-tarring MRC files from EPLAPP." >> $HOME/load.log
	else
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "TAR: failed to un-tar MRC files from EPLAPP." >> $HOME/load.log
		results=$(cat $HOME/load.log)
		echo "Uhoh, something went wrong $results" | mailx -a'From:ilsdev@ilsdev1.epl.ca' -s"OCLC2 Upload failed" $EMAILS
		exit 1
	fi
	# $REMOTE should now be empty.
	get_password
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s %s\n" $DATE_TIME "sftp to " $SFTP_SERVER >> $HOME/load.log
	export SSHPASS="$PASSWORD"
	# If this technique doesn't work try the one below.
	# if sshpass -p password sftp -oBatchMode=no user@serveraddress  << !
	# put file*
	# bye
	# !
	sshpass -e sftp -oBatchMode=no $SFTP_USER\@$SFTP_SERVER << !
   cd $REMOTE_DIR
   put $HOME/*.mrc
   bye
!
	if [[ $? ]]; then
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "done sftp." >> $HOME/load.log
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s %s\n" $DATE_TIME "removing tarball..." $HOME/$FILE >> $HOME/load.log
		rm $HOME/$FILE
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "removing tarball from EPLAPP." >> $HOME/load.log
		ssh sirsi\@eplapp.library.ualberta.ca "rm /s/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC2/$FILE" >&2 >> $HOME/load.log
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "removing mrc files." >> $HOME/load.log
		rm $HOME/*.mrc
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "completed successfully." >> $HOME/load.log
		echo "I ran successfully!" | mailx -a'From:ilsdev@ilsdev1.epl.ca' -s"OCLC2 Upload complete" $EMAILS
	else
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "failed to sftp." >> $HOME/load.log
		results=$(cat $HOME/load.log | pipe.pl -L-25)
		echo "Uhoh, something went wrong $results" | mailx -a'From:ilsdev@ilsdev1.epl.ca' -s"OCLC2 Upload failed" $EMAILS
	fi
else
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s %s\n" $DATE_TIME "**Error: unable to scp" $HOME/$FILE >> $HOME/load.log
fi
DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
printf "[%s] %s\n" $DATE_TIME "######" >> $HOME/load.log
# EOF
