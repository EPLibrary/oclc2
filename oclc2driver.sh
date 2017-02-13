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
#          0.0 - Dev.
#
#################################################################
# Manon Barbeau
# OCLC · Training & Implementation Specialist-Spécialiste en formation & implantation, OCLC Canada
# 9955 Chateauneuf, Suite 135, Brossard, Québec Canada J4Z 3V5
# T +1-888-658-6583 / 450-656-8955
SFTP_USER=cnedm
SFTP_SERVER=scp-toronto.oclc.org
REMOTE_DIR=/xfer/metacoll/in/bib
PASSWORD_FILE=`pwd`/oclc2.password.txt
PASSWORD=''
HOME=/home/ilsdev/projects/oclc2
FILE='' ###### TODO: finish me.
################### Functions.
# Reads the password file for the SFTP site.
get_password()
{
	# Tests, then reads the password file which is expected to be in the current working directory.
	if [ ! -s "$PASSWORD_FILE" ]; then
		printf "** error unable to SFTP results becaues I can't find the password file %s.\n" $PASSWORD_FILE >&2
		exit 1
	fi
	PASSWORD=$(cat "$PASSWORD_FILE" | pipe.pl -Gc0:^# -L-1)
	if [ ! "$PASSWORD" ]; then
		printf "*** failed to read password file.\n" >&2
		exit 1
	fi
}
################ end Functions
get_password
printf ">>>%s\n" $PASSWORD ### TEST
printf `date` >&2 >$HOME/load.log
# scp sirsi\@eplapp.library.ualberta.ca:/s/sirsi/Unicorn/EPLwork/ #### TODO: FINISH ME.
printf "scp data from EPLAPP" >&2 >> $HOME/load.log
if [ -s $HOME/$FILE ]
then
	cd $HOME
	printf "sftp to %s..." $SFTP_SERVER >&2 >> $HOME/load.log
	export SSHPASS="$PASSWORD"
	# If this technique doesn't work try the one below.
	# if sshpass -p password sftp -oBatchMode=no user@serveraddress  << !
	# put file*
	# bye
	# !
	sshpass -e sftp -oBatchMode=no $SFTP_USER\@$SFTP_SERVER << !
   cd $REMOTE_DIR
   put $HOME/$FILE
   bye
!
	if [[ $? ]]; then
		printf "done sftp." >&2 >> $HOME/load.log
		# rm $HOME/$FILE
	else
		printf "failed to sftp." >&2 >> $HOME/load.log
	fi
else
	printf "**Error: unable to scp $HOME/$FILE" >&2 >> $HOME/load.log
fi
# EOF
