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
VERSION=0.0
PASSWORD_FILE=`pwd`/password.txt
PASSWORD=''
# default milestone 7 days ago.
START_DATE=$(transdate -d-7)
# That is for all users, but on update we just want the user since the last time we did this. In that case
# we will save the date last run as a zero-byte file.
END_DATE=$(transdate -d-0)
HISTORY_DIRECTORY=`getpathname hist`
HISTORY_FILE_SELECTION=`pwd`/history.file.lst
# Stores the ANSI date of the last run. All contents are clobbered when script re-runs.
# This script features the ability to collect new users since the last time it ran.
# We save a file with today's date, and then use that with -f on seluser.
DATE_FILE=last.run
if [[ -s "$DATE_FILE" ]]; then
	START_DATE=$(cat "$DATE_FILE" | pipe.pl -Gc0:^# -L-1)
fi
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

# Outputs a well-formed flat MARC record of the argument record and date string.
# This subroutine is used in the Cancels process.
# param:  The record is a flex key and oclcNumber separated by a pipe: AAN-1945|(OCoLC)3329882|
# param:  The date is, well, the date in 'yymmdd' format. Example: 120831
# output: flat MARC record as a string.
printFlatMARC()
{
	local record=$1
	local date=$2
	local flexKey=$(echo $record | pipe.pl -oc0)
	local oclcNumber=$(echo $record | pipe.pl -oc1)
	printf "*** DOCUMENT BOUNDARY ***\n"
	printf "FORM=MARC\n"
	printf ".000. |aamI 0d\n"
	printf ".001. |a%s\n" $flexKey
	printf ".008. |a%snuuuu    xx            000 u und u\n" $date
	printf ".035.   |a%s\n" $oclcNumber # like (OCoLC)32013207
	printf ".852.   |aCNEDM\n"
	return 0
}

# Collects all the deleted records from history files.
run_cancels()
{
	get_password
	printf ">>>%s\n" $PASSWORD ### TEST
	printf "running cancels from %s to %s\n" $START_DATE $END_DATE >&2
	local start_date=$(echo $START_DATE | pipe.pl -mc0:######_) # Year and month only or dates won't match file.
	local end_date=$(echo $END_DATE | pipe.pl -mc0:######_) # Year and month only or dates won't match file.
	# To get the records of bibs that were deleted, we need to find history files since $start_date
	# and grep out where records were deleted. Let's find those history files first.
	# List all the files in the hist directory, start searching for the string $start_date and once found
	# continue to output until DATE_TODAY is found.
	printf "compiling list of files to search %s and %s\n" $start_date $end_date >&2
	# The test server shows that if we don't have an initial file name match for -X, -Y -M fail.
	ls $HISTORY_DIRECTORY | egrep -e "hist(.Z)?$" | pipe.pl -C"c0:ge$start_date" | pipe.pl -C"c0:le$end_date"  >$HISTORY_FILE_SELECTION
	# Read in the list of history files from $HIST_DIR one-per-line (single string per line)
	for h_file in $(cat $HISTORY_FILE_SELECTION |tr "\n" " ")
	do
		# Search the arg list of log files for entries of remove item (FV) and remove title option (NOY).
		printf "searching history file %s for delted titles.\n" $h_file >&2
		# E201405271803190011R ^S75FVFFADMIN^FEEPLMNA^FcNONE^NQ31221079015892^NOY^NSEPLJPL^IUa554837^tJ554837^aA(OCoLC)56729751^^O00099
		# zcat $h_file | egrep -e "FVFF" | egrep -e "NOY" | pipe.pl -g"any:IU|aA" 2>collected.lst
	done
	return 0
}

# Collects all the bib records that were added or modified since the last time it was run.
run_mixed()
{
	get_password
	printf ">>>%s\n" $PASSWORD ### TEST
	printf "running cancels from %s to %s\n" $START_DATE $END_DATE >&2
	printf "running mixed...\n" >&2
	return 0
}

# Usage message then exits.
# param:  none.
# return: exits with status 99
show_usage()
{
	printf "Usage: $0 collects and uploads DataSync Collections bib record metadata.\n" >&2
	printf "  Can be run with 0, arguments and you will be prompted for a type of\n" >&2
	printf "  action like mixed or cancels and the default date of %s will be used.\n" $START_DATE >&2
	printf "  Example: $0 \n"                              >&2
	printf "  \n"                              >&2
	printf "  Using a single param controls report type, but default date will be %s.\n" $START_DATE >&2
	printf "  Example: $0 [c|m|e|help|x]\n"             >&2
	printf "    * c - Run cancels.\n"             >&2
	printf "    * m - Run mixed project.\n"             >&2
	printf "    * b - Run both cancel and mixed projects.\n"             >&2
	printf "    * e - Exit, last run date is updated.\n"             >&2
	printf "    * x - Show usage.\n"             >&2
	printf "  \n"             >&2
	printf "  Using a 2 params allows selection of report type and milestone since last submission.\n" >&2
	printf "  Example: $0 [c|m|e|help|x] [YYYYMMDD|help]\n"  >&2
	printf "  (See above for explaination of flags).\n"  >&2
	printf "  \n" >&2
	printf "  Once the report is done it will save today's date into a file $LAST_RUN_DATE and use\n" >&2
	printf "  this date as the last milestone submission. If the file can't be found the last submission\n" >&2
	printf "  date defaults to $START_DATE and a new file with $TODAY will be created.\n" >&2
	printf "  Note that all dates must be in ANSI format (YYYYMMDD).\n" >&2
	exit 99
}
if [ $# -eq 2 ]; then
	# The second value on the command line is supposed to be an ANSI date like YYYYMMDD.
	START_DATE=$2
fi
# Allow the user to enter a specific operation if one isn't supplied on the command line.
if [ $# -eq 0 ] ; then
	printf "Enter desired operation: [c]ancels, [m]ixed, [b]oth, or [e]xit: [exit]" >&2
	read operation
	case "$operation" in
		[cC])
			run_cancels
			;;
		[mM])
			run_mixed
			;;
		[bB])
			run_cancels
			run_mixed
			;;
		[eE])
			printf "ok, exiting\n" >&2
			;;
		[helpxX])
			show_usage
			;;
		*)
			printf "** error don't understand '%s'.\n" $1 >&2
			show_usage
			;;
	esac
elif [ $# -ge 1 ]; then # 1 param or 2.
	case "$1" in
		[cC])
			run_cancels
			;;
		[mM])
			run_mixed
			;;
		[bB])
			run_cancels
			run_mixed
			;;
		[eE])
			printf "ok, exiting.\n" >&2
			;;
		[helpxX])
			show_usage
			;;
		*)
			printf "** error don't understand '%s'.\n" $1 >&2
			show_usage
			;;
	esac
else  # more than 2 arguments suggests user may not be familiar with this application.
	show_usage
fi
# That is for all users, but on update we just want the user since the last time we did this.
# echo "$DATE_TODAY" > `pwd`/$DATE_FILE ### Commented out so we can test without a complicated reset.
printf "done\n\n" >&2
exit 0
# EOF
