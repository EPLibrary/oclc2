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
PASSWORD_FILE=`pwd`/oclc2.password.txt
PASSWORD=''
# default milestone 7 days ago.
START_DATE=$(transdate -d-7)
# That is for all users, but on update we just want the user since the last time we did this. In that case
# we will save the date last run as a zero-byte file.
END_DATE=$(transdate -d-0)
HISTORY_DIRECTORY=`getpathname hist`
HISTORY_FILE_SELECTION=`pwd`/oclc2.history.file.lst
CANCEL_FLEX_OCLC_FILE=`pwd`/oclc2.flexkeys.OCLCnumber.lst
UNFOUND_FLEXKEYS=`pwd`/oclc2.unfound.flexkeys.lst
CANCEL_DIFF_FILE=`pwd`/oclc2.diff.lst
ERROR_LOG=`pwd`/err.log
FINAL_CANCEL_FLAT_FILE=`pwd`/oclc2.final.flat
### TODO: check spec to find out what optimal name is.
FINAL_CANCEL_MARC_FILE=`pwd`/oclc2.final.mrc
### Variables specially for 'mixed' projects.
NOT_THESE_TYPES="PAPERBACK,JPAPERBACK,BKCLUBKIT,COMIC,DAISYRD,EQUIPMENT,E-RESOURCE,FLICKSTOGO,FLICKTUNE,JFLICKTUNE,JTUNESTOGO,PAMPHLET,RFIDSCANNR,TUNESTOGO,JFLICKTOGO,PROGRAMKIT,LAPTOP,BESTSELLER,JBESTSELLR"
NOT_THESE_LOCATIONS="BARCGRAVE,CANC_ORDER,DISCARD,EPLACQ,EPLBINDERY,EPLCATALOG,EPLILL,INCOMPLETE,LONGOVRDUE,LOST,LOST-ASSUM,LOST-CLAIM,LOST-PAID,MISSING,NON-ORDER,ON-ORDER,BINDERY,CATALOGING,COMICBOOK,INTERNET,PAMPHLET,DAMAGE,UNKNOWN,REF-ORDER,BESTSELLER,JBESTSELLR,STOLEN"
MIXED_CATKEYS_FILE=`pwd`/oclc2.mixed.catkeys.lst
### TODO: check spec to find out what optimal name is.
FINAL_MIXED_MARC_FILE=`pwd`/oclc2.mixed.mrc ##### Rename this file for submission.
# Stores the ANSI date of the last run. All contents are clobbered when script re-runs.
# This script features the ability to collect new users since the last time it ran.
# We save a file with today's date, and then use that with -f on seluser.
DATE_FILE=`pwd`/oclc2.last.run
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
# param:  The record is a flex key and oclcNumber separated by a pipe: 'AAN-1945|(OCoLC)3329882'
# output: flat MARC record as a string.
printFlatMARC()
{
	# the date in 'yymmdd' format. Example: 120831
	local date=$(date +%y%m%d)
	local flexKey=$(echo "$1" | pipe.pl -oc0)
	if [[ -z "${flexKey// }" ]]; then
		printf "* warning no flex key provided, skipping record %s.\n" $record >&2
		return 1
	fi
	local oclcNumber=$(echo "$1" | pipe.pl -oc1)
	if [[ -z "${oclcNumber// }" ]]; then
		printf "* warning no OCLC number found in record %s, skipping.\n" $record >&2
		return 1
	fi
	echo "*** DOCUMENT BOUNDARY ***" >>$FINAL_CANCEL_FLAT_FILE
	echo "FORM=MARC" >>$FINAL_CANCEL_FLAT_FILE
	echo ".000. |aamI 0d" >>$FINAL_CANCEL_FLAT_FILE
	echo ".001. |a$flexKey"  >>$FINAL_CANCEL_FLAT_FILE
	echo ".008. |a"$date"nuuuu    xx            000 u und u" >>$FINAL_CANCEL_FLAT_FILE
	echo ".035.   |a$oclcNumber"  >>$FINAL_CANCEL_FLAT_FILE # like (OCoLC)32013207
	echo ".852.   |aCNEDM"   >>$FINAL_CANCEL_FLAT_FILE
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
		printf "searching history file %s/%s for deleted titles.\n" $HISTORY_DIRECTORY $h_file >&2
		# E201405271803190011R ^S75FVFFADMIN^FEEPLMNA^FcNONE^NQ31221079015892^NOY^NSEPLJPL^IUa554837^tJ554837^aA(OCoLC)56729751^^O00099
		# Extract the cat key and Flex key from the history logs.
		if [ -s "$HISTORY_DIRECTORY/$h_file" ]; then
			zcat $HISTORY_DIRECTORY/$h_file | egrep -e "FVFF" | egrep -e "NOY" | pipe.pl -W'\^' -g"any:IU|aA" -5 2>$CANCEL_FLEX_OCLC_FILE >/dev/null
		else
			local this_month=$(echo $h_file | pipe.pl -m'c0:###########_') # remove the .Z for this month.
			if [ -s "$HISTORY_DIRECTORY/$this_month" ]; then
				cat $HISTORY_DIRECTORY/$this_month | egrep -e "FVFF" | egrep -e "NOY" | pipe.pl -W'\^' -g'any:IU|aA' -5 2>$CANCEL_FLEX_OCLC_FILE >/dev/null
			else
				printf "omitting %s\n" $h_file
			fi
		fi
	done
	# Now we should have a file like this.
	# IUa1848301|aAocn844956543
	# Clean it for the next selection.
	if [ -s "$CANCEL_FLEX_OCLC_FILE" ]; then
		cat $CANCEL_FLEX_OCLC_FILE | pipe.pl -m'c0:__#,c1:__#' -tc1 -zc0,c1 >tmp.$$
		mv tmp.$$ $CANCEL_FLEX_OCLC_FILE
		# Should now look like this.
		# a1870593|ocm71780540
		# LSC2923203|(OCoLC)932576987
		# Pass these Flex keys to selcatalog and collect the error 111. 
		# These are truely removed titles - not just removed items from 
		# a title, or a title that has been replaced.
		cat $CANCEL_FLEX_OCLC_FILE | pipe.pl -oc0 -P | selcatalog -iF 2>$UNFOUND_FLEXKEYS
		# **error number 111 on catalog not found, key=526625 flex=ADI-7542
		# Snag the flex key and save it then diff.pl to get the canonical list of missing flex keys.
		# The trailing pipe will be useful to sep values in the following diff.pl command.
		cat $UNFOUND_FLEXKEYS | pipe.pl -W'flex=' -zc1 -oc1 -P >tmp.$$
		mv tmp.$$ $UNFOUND_FLEXKEYS
		echo "echo \"$UNFOUND_FLEXKEYS and $CANCEL_FLEX_OCLC_FILE\" | diff.pl -ec0 -fc0 -mc1"
		echo "$UNFOUND_FLEXKEYS and $CANCEL_FLEX_OCLC_FILE" | diff.pl -ec0 -fc0 -mc1 >$CANCEL_DIFF_FILE
		# a809658|(OCoLC)320195792
		# Create the brief delete MARC file of all the entries.
		# If one pre-exists we will delete it now so we can just keep appending in the loop.
		if [[ -s "$FINAL_CANCEL_FLAT_FILE" ]]; then
			rm $FINAL_CANCEL_FLAT_FILE
		fi
		while read -r file_line
		do
			if ! printFlatMARC $file_line
			then
				printf "** error '%s' malformed.\n" $CANCEL_DIFF_FILE >&2
				exit 1
			fi
		done <$CANCEL_DIFF_FILE
		# Now to make the MARC output from the flat file.
		printf "creating marc file.\n" >&2
		cat $FINAL_CANCEL_FLAT_FILE | flatskip -aMARC -if -om > $FINAL_CANCEL_MARC_FILE 2>>$ERROR_LOG
	fi
	return 0
}

# Collects all the bib records that were added or modified since the last time it was run.
run_mixed()
{
	get_password
	printf ">>>%s\n" $PASSWORD ### TEST
	printf "running mexed from %s to %s\n" $START_DATE $END_DATE >&2
	selitem -t"~$NOT_THESE_TYPES" -l"~$NOT_THESE_LOCATIONS" -oC >tmp.$$
	# select all the records that were created since the start date.
	printf "adding keys that were created since '%s'\n" $START_DATE >&2
	cat tmp.$$ | selcatalog -iC -oC -p">$START_DATE" > $MIXED_CATKEYS_FILE 2>>$ERROR_LOG
	# Now the modified records.
	printf "adding keys that were modified since '%s'\n" $START_DATE >&2
	cat tmp.$$ | selcatalog -iC -oC -r">$START_DATE" >>$MIXED_CATKEYS_FILE 2>>$ERROR_LOG
	cat $MIXED_CATKEYS_FILE | sort | uniq >tmp.$$
	mv tmp.$$ $MIXED_CATKEYS_FILE
	cat $MIXED_CATKEYS_FILE | catalogdump -kf035 -om > $FINAL_MIXED_MARC_FILE 2>>$APILogfilename
	return 0
}
# Ask if for the date if user using no args.
# If the user has not specified any args, they will be asked what action they want to
# do, but we also need to confirm the last milestone date.
# param:  none
# return: 0
ask_mod_date()
{
	printf "Do you want to continue with processing items from the last milestone date: %s? [y]/n " $START_DATE >&2
	read use_date
	case "$use_date" in
		[nN])
			printf "\nEnter new date: " >&2
			read START_DATE
			;;
		*)
			printf "continuing with last milestone date.\n" >&2
			;;
	esac
	printf "Date set to %s\n" $START_DATE >&2
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
			ask_mod_date
			run_cancels
			;;
		[mM])
			ask_mod_date
			run_mixed
			;;
		[bB])
			ask_mod_date
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
elif [ $# -eq 1 ]; then # 1 param or 2.
	case "$1" in
		[cC])
			ask_mod_date
			run_cancels
			;;
		[mM])
			ask_mod_date
			run_mixed
			;;
		[bB])
			ask_mod_date
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
