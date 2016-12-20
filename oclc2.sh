#!/bin/bash
####################################################
#
# Bash shell script for project oclc2
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
####################################################

# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
###############################################
# *** Edit these to suit your environment *** #
source /s/sirsi/Unicorn/EPLwork/cronjobscripts/setscriptenvironment.sh
###############################################
VERSION=0
PASSWORD_FILE=`pwd`/password.txt
PASSWORD=''
MILESTONE=$(transdate -d-7) # default milestone 7 days ago.

### The script expects to receive commands of either 'mixed', meaning all additions and
### modifications, or 'cancels', indicating to upload items deleted from the catalog during
### the specified time frame. The other accepted command is 'exit', which will surprisingly
### exit the script.

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
		printf "*** failed to read password file." >&2
		exit 1
	fi
}

# Collects all the deleted records from history files.
run_cancels()
{
	printf "running cancels..." >&2
	return 0
}

# Collects all the bib records that were added or modified since the last time it was run.
run_mixed()
{
	get_password
	echo ">>> $PASSWORD" ### TEST
	printf "running mixed..." >&2
	return 0
}

# Tests and sets the last run date to a specific value.
test_set_date()
{
	size=${#1}
	echo "arg size set to $size" >&2 ### TEST
	if [ $size -ne 8 ]; then
		echo "** invalid date $1" >&2
		exit 1
	else
		MILESTONE=$1
		echo "milestone set to $MILESTONE date." >&2
	fi
}

# Allow the user to enter a specific operation if one isn't supplied on the command line.
if [ $# -eq 0 ] ; then
	printf "Enter desired operation: [c]ancels, [m]ixed, [e]xit: [exit]" >&2
	read operation
	case "$operation" in
		[cC])
			run_cancels
			;;
		[mM])
			run_mixed
			;;
		[eExX])
			printf "ok, exiting" >&2
			;;
		*)
			printf "?? don't understand '$operation'." >&2
			exit 1
			;;
	esac
	printf "done" >&2
	exit 0
elif [ $# -eq 1 ]; then
	case "$1" in
		[cC])
			run_cancels
			;;
		[mM])
			run_mixed
			;;
		[eExX])
			printf "ok, exiting" >&2
			;;
		*)
			printf "?? don't understand '$operation'." >&2
			exit 1
			;;
	esac
	printf "done" >&2
	exit 0
elif [ $# -eq 2 ]; then
	# The second value on the command line is supposed to be an ANSI date like YYYYMMDD.
	test_set_date $2 
	case "$1" in
		[cC])
			run_cancels
			;;
		[mM])
			run_mixed
			;;
		[eExX])
			printf "ok, exiting" >&2
			;;
		*)
			printf "?? don't understand '$operation'." >&2
			exit 1
			;;
	esac
	printf "done" >&2
	exit 0
else
	printf "Usage: $0 collects and uploads DataSync Collections bib record metadata." >&2
	printf "  $0 "                        >&2
	printf "  $0 [cC|mM|eExX]"            >&2
	printf "  $0 [cC|mM|eExX] [YYYYMMDD]" >&2
	exit 0
fi
# EOF
