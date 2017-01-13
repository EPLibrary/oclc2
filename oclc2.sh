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
# default milestone 7 days ago.
MILESTONE=$(transdate -d-7)
TODAY=$(transdate -d-0)
# Stores the ANSI date of the last run. All contents are clobbered when script re-runs.
LAST_RUN_DATE=`pwd`/last.run.date.txt

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
		printf "*** failed to read password file.\n" >&2
		exit 1
	fi
}

# Collects all the deleted records from history files.
run_cancels()
{
	printf "running cancels...\n" >&2
	return 0
}

# Collects all the bib records that were added or modified since the last time it was run.
run_mixed()
{
	get_password
	printf ">>>%s\n" $PASSWORD### TEST
	printf "running mixed...\n" >&2
	return 0
}

# Tests and sets the last run date to a specific value. Used when user wants to run
# the report from a specific period. Saves the date into $LAST_RUN_DATE (in the current directory).
# The next time the script is run it will use this date as the last run date.
# param:  Number string ANSI date 'YYYYMMDD'.
# return: 1 if the date is not an 8 digit value as in an ANSI date, and 0 otherwise.
test_set_date()
{
	# If a value was supplied test it.
	if [ "$1" ] && [ $1 > 0 ]; then
		size=${#1}
		printf "arg size set to %s\n" $size >&2 ### TEST
		if [ $size -ne 8 ]; then
			printf "** invalid date %s\n" $1 >&2
			return 1
		else
			MILESTONE=$1
			printf "milestone set to %s date.\n" $MILESTONE >&2
		fi
	else # No date was given as a parameter.
		# Test for last run date. If there is one use the date inside.
		if [ -s "$LAST_RUN_DATE" ]; then
			MILESTONE=$(head -1 "$LAST_RUN_DATE")
		fi
	fi
	# Now rewrite the last run date to reflect today's date.
	echo $TODAY > $LAST_RUN_DATE
	return 0;
}

# Usage message then exits.
# param:  none.
# return: exits with status 99
show_usage()
{
	printf "Usage: $0 collects and uploads DataSync Collections bib record metadata.\n" >&2
	printf "  Can be run with 0, arguments and you will be prompted for a type of\n" >&2
	printf "  action like mixed or cancels and the default date of %s will be used.\n" $MILESTONE >&2
	printf "  Example: $0 \n"                              >&2
	printf "  \n"                              >&2
	printf "  Using a single param controls report type, but default date will be %s.\n" $MILESTONE >&2
	printf "  Example: $0 [cC|mM|eExX|help]\n"             >&2
	printf "  \n"             >&2
	printf "  Using a 2 params allows selection of report type and milestone since last submission.\n" >&2
	printf "  Example: $0 [cC|mM|eExX] [YYYYMMDD|help]\n"  >&2
	printf "  \n" >&2
	printf "  Once the report is done it will save today's date into a file $LAST_RUN_DATE and use\n" >&2
	printf "  this date as the last milestone submission. If the file can't be found the last submission\n" >&2
	printf "  date defaults to $MILESTONE and a new file with $TODAY will be created.\n" >&2
	printf "  Note that all dates must be in ANSI format (YYYYMMDD).\n" >&2
	exit 99
}

# Allow the user to enter a specific operation if one isn't supplied on the command line.
if [ $# -eq 0 ] ; then
	printf "Enter desired operation: [c]ancels, [m]ixed, [b]oth, or [e]xit: [exit]" >&2
	read operation
	case "$operation" in
		[cC])
			test_set_date
			run_cancels
			;;
		[mM])
			test_set_date
			run_mixed
			;;
		[bB])
			test_set_date
			run_cancels
			run_mixed
			;;
		[eExX])
			printf "ok, exiting\n" >&2
			;;
		[help])
			show_usage
			;;
		*)
			printf "** error don't understand '%s'.\n" $1 >&2
			show_usage
			;;
	esac
elif [ $# -eq 1 ]; then
	case "$1" in
		[cC])
			test_set_date
			run_cancels
			;;
		[mM])
			test_set_date
			run_mixed
			;;
		[bB])
			test_set_date
			run_cancels
			run_mixed
			;;
		[eExX])
			printf "ok, exiting" >&2
			;;
		[help])
			show_usage
			;;
		*)
			printf "** error don't understand '%s'.\n" $1 >&2
			show_usage
			;;
	esac
elif [ $# -eq 2 ]; then
	# The second value on the command line is supposed to be an ANSI date like YYYYMMDD.
	date_check_result=test_set_date $2
	if [ $date_check_result == 1 ]; then # Fail date check
		printf "** error invalid date '%s'.\n" $2 >&2
		show_usage
	fi 
	case "$1" in
		[cC])
			test_set_date $2
			run_cancels
			;;
		[mM])
			test_set_date $2
			run_mixed
			;;
		[bB])
			test_set_date $2
			run_cancels
			run_mixed
			;;
		[eExX])
			printf "ok, exiting" >&2
			;;
		[help])
			show_usage
			;;
		*)
			printf "** error don't understand'%s'.\n" $1 >&2
			show_usage
			;;
	esac
else  # more than 2 arguments suggests user may not be familiar with this application.
	show_usage
fi
printf "done\n\n" >&2
exit 0
# EOF
