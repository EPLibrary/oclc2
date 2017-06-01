#!/usr/bin/bash
####################################################
#
# Bash shell script for project oclc2
#
# Collect and submit Data Sync Collections data for OCLC.
#    Copyright (C) 2017  Andrew Nisbet
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
#          0.8 - SHELL updated to use bash because cron running sh is 'nice'd to 10.
#          0.7 - Added absolute pathing for running by cron.
#          0.6 - Tarball all MARC files with standard name 'submission.tar'.
#          0.5 - Cancels tested on Production.
#          0.4 - Bug fix for reading difference between compressed and uncompressed files.
#          0.3 - Tested on Production.
#          0.0 - Dev.
#
####################################################
# This script is the replacement is to accomodate OCLC's DataSync Collections 
# which is a replacement for BatchLoad. Each scheduled cycle the script will 
# collect all the modified (and created), or deleted records and upload the records
# as brief MARC records to the designated SFTP site in Toronto.
#
# By default the script looks at changes made within the last seven days but 
# checks a file $WORKING_DIR/oclc2.last.run, and adjusts its selection date based on the 
# ANSI date found there. If you want just the last 7 days, delete the file. It 
# will be created again with today's date. If you run the script again in 2 days
# only altered records from the last 2 days will be noted and uploaded.
# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
###############################################
# *** Edit these to suit your environment *** #
source /s/sirsi/Unicorn/EPLwork/cronjobscripts/setscriptenvironment.sh
###############################################
export VERSION=0.8
# using /bin/sh causes cron to 'nice' the process at '10'!
export SHELL=/usr/bin/bash
# default milestone 7 days ago.
export START_DATE=$(transdate -d-7)
# That is for all users, but on update we just want the user since the last time we did this. In that case
# we will save the date last run as a zero-byte file.
export END_DATE=$(transdate -d-0)
export HISTORY_DIRECTORY=`getpathname hist`
export WORKING_DIR=/s/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC2
export CANCELS_HISTORY_FILE_SELECTION=$WORKING_DIR/oclc2.cancels.history.file.lst
export CANCELS_FLEX_OCLC_FILE=$WORKING_DIR/oclc2.cancels.flexkeys.OCLCnumber.lst
export CANCELS_UNFOUND_FLEXKEYS=$WORKING_DIR/oclc2.cancels.unfound.flexkeys.lst
export CANCELS_DIFF_FILE=$WORKING_DIR/oclc2.cancels.diff.lst
export ERROR_LOG=$WORKING_DIR/err.log
export CANCELS_FINAL_FLAT_FILE=$WORKING_DIR/oclc2.cancels.final.flat
### Variables specially for 'mixed' projects.
export NOT_THESE_TYPES="PAPERBACK,JPAPERBACK,BKCLUBKIT,COMIC,DAISYRD,EQUIPMENT,E-RESOURCE,FLICKSTOGO,FLICKTUNE,JFLICKTUNE,JTUNESTOGO,PAMPHLET,RFIDSCANNR,TUNESTOGO,JFLICKTOGO,PROGRAMKIT,LAPTOP,BESTSELLER,JBESTSELLR"
export NOT_THESE_LOCATIONS="BARCGRAVE,CANC_ORDER,DISCARD,EPLACQ,EPLBINDERY,EPLCATALOG,EPLILL,INCOMPLETE,LONGOVRDUE,LOST,LOST-ASSUM,LOST-CLAIM,LOST-PAID,MISSING,NON-ORDER,ON-ORDER,BINDERY,CATALOGING,COMICBOOK,INTERNET,PAMPHLET,DAMAGE,UNKNOWN,REF-ORDER,BESTSELLER,JBESTSELLR,STOLEN"
export MIXED_CATKEYS_FILE=$WORKING_DIR/oclc2.mixed.catkeys.lst
### Submission file names.
# collectionid.symbol.bibholdings.n.mrc where ‘collectionid’ is the data sync collection
# ID number; ‘symbol’ is escaped as per the login; ‘n’ is a number to make the file
# name unique
export COLLECTION_ID=1023505
export SYMBOL=cnedm
# These are ints that represent the date in ANSI with a '0' for cancels and '1' for mixed on the end.
export N_CANCELS=`date +%Y%m%d`0
export N_MIXED=`date +%Y%m%d`1
export CANCELS_FINAL_MARC_FILE=$WORKING_DIR/$COLLECTION_ID.$SYMBOL.bibholdings.$N_CANCELS.mrc
export MIXED_FINAL_MARC_FILE=$WORKING_DIR/$COLLECTION_ID.$SYMBOL.bibholdings.$N_MIXED.mrc
export SUBMISSION_TAR=$WORKING_DIR/submission.tar
# Stores the ANSI date of the last run. All contents are clobbered when script re-runs.
# This script features the ability to collect new users since the last time it ran.
# We save a file with today's date, and then use that with -f on seluser.
export DATE_FILE=$WORKING_DIR/oclc2.last.run
if [[ -s "$DATE_FILE" ]]; then
	# Grab the last line of the file that doesn't start with a hash '#'.
	START_DATE=$(cat "$DATE_FILE" | pipe.pl -Gc0:^# -L-1)
fi
### The script expects to receive commands of either 'mixed', meaning all additions and
### modifications, or 'cancels', indicating to upload items deleted from the catalog during
### the specified time frame. The other accepted command is 'exit', which will, not surprisingly,
### exit the script.
# Outputs a well-formed flat MARC record of the argument record and date string.
# This subroutine is used in the Cancels process.
# param:  The record is a flex key and oclcNumber separated by a pipe: 'AAN-1945|(OCoLC)3329882'
# output: flat MARC record as a string.
# return: always returns 0.
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
	echo "*** DOCUMENT BOUNDARY ***" >>$CANCELS_FINAL_FLAT_FILE
	echo "FORM=MARC" >>$CANCELS_FINAL_FLAT_FILE
	echo ".000. |aamI 0d" >>$CANCELS_FINAL_FLAT_FILE
	echo ".001. |a$flexKey"  >>$CANCELS_FINAL_FLAT_FILE
	echo ".008. |a"$date"nuuuu    xx            000 u und u" >>$CANCELS_FINAL_FLAT_FILE
	echo ".035.   |a$oclcNumber"  >>$CANCELS_FINAL_FLAT_FILE # like (OCoLC)32013207
	echo ".852.   |aCNEDM"   >>$CANCELS_FINAL_FLAT_FILE
	return 0
}

# Collects all the deleted records from history files.
# param: none
# return: always returns 0.
run_cancels()
{
	printf "running cancels from %s to %s\n" $START_DATE $END_DATE >&2
	local start_date=$(echo $START_DATE | pipe.pl -mc0:######_) # Year and month only or dates won't match file.
	local end_date=$(echo $END_DATE | pipe.pl -mc0:#) # Year and month only or dates won't match file.
	# To get the records of bibs that were deleted, we need to find history files since $start_date
	# and grep out where records were deleted. Let's find those history files first.
	# List all the files in the hist directory, start searching for the string $start_date and once found
	# continue to output until DATE_TODAY is found.
	printf "compiling list of files to search %s to %s\n" $START_DATE $END_DATE >&2
	# The test server shows that if we don't have an initial file name match for -X, -Y -M fail.
	ls $HISTORY_DIRECTORY | egrep -e "hist(\.Z)?$" | pipe.pl -C"c0:ge$start_date" | pipe.pl -C"c0:le$end_date"  >$CANCELS_HISTORY_FILE_SELECTION
	# Read in the list of history files from $HIST_DIR one-per-line (single string per line)
	for h_file in $(cat $CANCELS_HISTORY_FILE_SELECTION | tr "\n" " ")
	do
		# Search the arg list of log files for entries of remove item (FV) and remove title option (NOY).
		printf "searching history file %s/%s for deleted titles.\n" $HISTORY_DIRECTORY $h_file >&2
		# E201405271803190011R ^S75FVFFADMIN^FEEPLMNA^FcNONE^NQ31221079015892^NOY^NSEPLJPL^IUa554837^tJ554837^aA(OCoLC)56729751^^O00099
		# Extract the cat key and Flex key from the history logs.
		# Using grep initially is faster then let pipe convert '^' to '|', and grep any field with IU or aA and
		# output just that field.
		# First we can't zcat a regular file so when that breaks, use plain old cat.
		# Note to self: zcat implies the '.Z' extension when it runs. 
		zcat "$HISTORY_DIRECTORY/$h_file" 2>/dev/null | egrep -e "FVF" | egrep -e "NOY" >/tmp/oclc2.tmp.zcat.$$
		if [ ! -s "/tmp/oclc2.tmp.zcat.$$" ]; then
			# zcat didn't find any results, maybe the file isn't compressed. Try cat instead.
			cat "$HISTORY_DIRECTORY/$h_file" 2>/dev/null | egrep -e "FVF" | egrep -e "NOY" >/tmp/oclc2.tmp.zcat.$$
		fi
		## before:
		# 20170401|S44FVFFADMIN|FEEPLMNA|FcNONE|NQ31221105319052|NOY|NSEPLLHL|IUa1113832|tJ1113832|aA(OCoLC)640340037||O00102
		printf "collecting all TCN and OCLC numbers.\n" >&2
		cat /tmp/oclc2.tmp.zcat.$$ | pipe.pl -W'\^' -m"c0:_########_" | pipe.pl -C"c0:ge$START_DATE" -U | pipe.pl -g"any:IU|aA" -5 2>>$CANCELS_FLEX_OCLC_FILE >/dev/null
		## after:
		# IUepl000002574|aA(OCoLC)759176932
		rm /tmp/oclc2.tmp.zcat.$$
	done
	# Now we should have a file like this.
	# IUa1848301|aAocn844956543
	# Clean it for the next selection.
	if [ -s "$CANCELS_FLEX_OCLC_FILE" ]; then
		cat $CANCELS_FLEX_OCLC_FILE | pipe.pl -m'c0:__#,c1:__#' -tc1 -zc0,c1 >/tmp/oclc2.tmp.$$
		mv /tmp/oclc2.tmp.$$ $CANCELS_FLEX_OCLC_FILE
		# Should now look like this.
		# a1870593|ocm71780540
		# LSC2923203|(OCoLC)932576987
		# Snag the flex key and save it then use diff.pl to get the canonical list of missing flex keys
		# that is, all the flex keys (titles) that are no longer on the ILS.
		# Pass these Flex keys to selcatalog and collect the error 111. 
		# **error number 111 on catalog not found, key=526625 flex=ADI-7542
		# We aren't interested in the ones that are still in the catalog so send them to /dev/null.
		printf "searching catalog for missing catalog keys.\n" >&2
		cat $CANCELS_FLEX_OCLC_FILE | pipe.pl -oc0 -P | selcatalog -iF >/dev/null 2>$CANCELS_UNFOUND_FLEXKEYS
		# The trailing pipe will be useful to sep values in the following diff.pl command.
		cat $CANCELS_UNFOUND_FLEXKEYS | pipe.pl -W'flex=' -zc1 -oc1 -P >/tmp/oclc2.tmp.$$
		mv /tmp/oclc2.tmp.$$ $CANCELS_UNFOUND_FLEXKEYS
		local count=$(cat $CANCELS_UNFOUND_FLEXKEYS | wc -l | pipe.pl -tc0)
		printf "submission includes %s cancelled bib records.\n" $count >&2
		echo "$CANCELS_UNFOUND_FLEXKEYS and $CANCELS_FLEX_OCLC_FILE" | diff.pl -ec0 -fc0 -mc1 >$CANCELS_DIFF_FILE
		# a809658|(OCoLC)320195792
		# Create the brief delete MARC file of all the entries.
		# If one pre-exists we will delete it now so we can just keep appending in the loop.
		if [[ -s "$CANCELS_FINAL_FLAT_FILE" ]]; then
			rm $CANCELS_FINAL_FLAT_FILE
		fi
		while read -r file_line
		do
			if ! printFlatMARC $file_line
			then
				printf "** error '%s' malformed.\n" $CANCELS_DIFF_FILE >&2
				exit 1
			fi
		done <$CANCELS_DIFF_FILE
		# Now to make the MARC output from the flat file.
		printf "creating marc file.\n" >&2
		cat $CANCELS_FINAL_FLAT_FILE | flatskip -aMARC -if -om > $CANCELS_FINAL_MARC_FILE 2>>$ERROR_LOG
	fi
	return 0
}

# Collects all the bib records that were added or modified since the last time it was run.
# param: none
# return: always returns 0.
run_mixed()
{
	printf "running mixed from %s to %s.\n" $START_DATE $END_DATE >&2
	selitem -t"~$NOT_THESE_TYPES" -l"~$NOT_THESE_LOCATIONS" -oC 2>/dev/null >/tmp/oclc2.tmp.$$
	## select all the records that were created since the start date.
	printf "adding keys that were created since %s.\n" $START_DATE >&2
	cat /tmp/oclc2.tmp.$$ | selcatalog -iC -p">$START_DATE" -oC >$MIXED_CATKEYS_FILE 2>>$ERROR_LOG
	## Now the modified records.
	printf "adding keys that were modified since %s.\n" $START_DATE >&2
	cat /tmp/oclc2.tmp.$$ | selcatalog -iC -r">$START_DATE" -oC >>$MIXED_CATKEYS_FILE 2>>$ERROR_LOG
	cat $MIXED_CATKEYS_FILE | sort | uniq >/tmp/oclc2.tmp.$$
	mv /tmp/oclc2.tmp.$$ $MIXED_CATKEYS_FILE
	cat $MIXED_CATKEYS_FILE | catalogdump -kf035 -om >$MIXED_FINAL_MARC_FILE 2>>$ERROR_LOG
	return 0
}
# Cleans up temp files after process run.
# param:  none.
# return: 0 if everything worked according to plan, and 1 if the final marc file 
#         couldn't be found.
clean_mixed()
{
	if [ -s "$MIXED_FINAL_MARC_FILE" ]; then
		if [ -s "$SUBMISSION_TAR" ]; then
			tar uvf $SUBMISSION_TAR $MIXED_FINAL_MARC_FILE >>$ERROR_LOG
		else
			tar cvf $SUBMISSION_TAR $MIXED_FINAL_MARC_FILE >>$ERROR_LOG
		fi
	else
		printf "MARC file: '%s' was not created.\n" $MIXED_FINAL_MARC_FILE >>$ERROR_LOG
		return 1
	fi
	if [ -s "$MIXED_CATKEYS_FILE" ]; then
		rm $MIXED_CATKEYS_FILE
	fi
	return 0
}
# Cleans up temp files after process run.
# param:  none.
# return: 0 if everything worked according to plan, and 1 if the final marc file 
#         couldn't be found.
clean_cancels()
{
	if [ -s "$CANCELS_FINAL_MARC_FILE" ]; then
		if [ -s "$SUBMISSION_TAR" ]; then
			tar uvf $SUBMISSION_TAR $CANCELS_FINAL_MARC_FILE >>$ERROR_LOG
		else
			tar cvf $SUBMISSION_TAR $CANCELS_FINAL_MARC_FILE >>$ERROR_LOG
		fi
	else
		printf "MARC file: '%s' was not created.\n" $CANCELS_FINAL_MARC_FILE >>$ERROR_LOG
		return 1
	fi
	if [ -s "$CANCELS_HISTORY_FILE_SELECTION" ]; then
		rm $CANCELS_HISTORY_FILE_SELECTION
	fi
	if [ -s "$CANCELS_FLEX_OCLC_FILE" ]; then
		rm $CANCELS_FLEX_OCLC_FILE
	fi
	if [ -s "$CANCELS_UNFOUND_FLEXKEYS" ]; then
		rm $CANCELS_UNFOUND_FLEXKEYS
	fi
	if [ -s "$CANCELS_DIFF_FILE" ]; then
		rm $CANCELS_DIFF_FILE
	fi
	if [ -s "$CANCELS_FINAL_FLAT_FILE" ]; then
		rm $CANCELS_FINAL_FLAT_FILE
	fi
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
	printf "Usage: $0 [c|m|b[YYYYMMDD]]\n"                   >&2
	printf "  $0 collects modified (created or modified) and/or deleted bibliograhic\n" >&2
	printf "  metadata for OCLC's DataSync Collection service. This script does not upload to OCLC.\n" >&2
	printf "  (See oclc2driver.sh for more information about loading bib records to DataSync Collections.)\n" >&2
	printf "  \n"                                            >&2
	printf "  If run with no arguments both mixed and cancels will be run from the last run date\n" >&2
	printf "  or for the period covering the last 7 calendar days if there's no last-run-date file\n" >&2
	printf "  in the working directory.\n"                   >&2
	printf "  Example: $0 \n"                                >&2
	printf "  \n"                                            >&2
	printf "  Using a single param controls report type, but default date will be %s and\n" $START_DATE >&2
	printf "  you will be asked to confirm the date before starting.\n" >&2
	printf "  Example: $0 [c|m|b]\n"                         >&2
	printf "    * c - Run cancels report.\n"                 >&2
	printf "    * m - Run mixed project report.\n"           >&2
	printf "    * b - Run both cancel and mixed projects (default action).\n" >&2
	printf "  \n"                                            >&2
	printf "  Using a 2 params allows selection of report type and milestone since last submission.\n" >&2
	printf "  Example: $0 [c|m|b] 20170101\n"                >&2
	printf "  (See above for explaination of flags). The date value is not checked and\n" >&2
	printf "  will throw an error if not a valid ANSI date (YYYMMDD format).\n" >&2
	printf "  \n"                                            >&2
	printf "  Once the report is done it will save today's date into file\n  '%s'\n" $DATE_FILE >&2
	printf "  and use this date as the last milestone for the next submission. If the file can't be found\n" >&2
	printf "  the last submission date defaults to 7 days ago, and a new file with today's date will be created.\n" >&2
	printf "  Note that all dates must be in ANSI format (YYYYMMDD), must be the only value on the \n" >&2
	printf "  last uncommented line. A comment line starts with '#'.\n" >&2
	printf "  \n"                                            >&2
	printf "  The last-run-date file is not essential and will be recreated if it is deleted, however\n" >&2
	printf "  it is useful in showing the chronology of times the process has been run.\n" >&2
	printf "  \n"                                            >&2
	printf "  Version: %s\n" $VERSION                        >&2
	exit 99
}
if [ $# -eq 2 ]; then
	# The second value on the command line is supposed to be an ANSI date like YYYYMMDD.
	START_DATE=$2
fi
# Run all functions. This allows the process to be cronned and not require user input to run.
if [ $# -eq 0 ] ; then
	run_cancels
	clean_cancels
	run_mixed
	clean_mixed
elif [ $# -eq 1 ]; then # 1 param or 2.
	case "$1" in
		[cC])
			ask_mod_date
			run_cancels
			clean_cancels
			;;
		[mM])
			ask_mod_date
			run_mixed
			clean_mixed
			;;
		[bB])
			ask_mod_date
			run_cancels
			clean_cancels
			run_mixed
			clean_mixed
			;;
		*)
			printf "** error unsupported option '%s'.\n" $1 >&2
			show_usage
			;;
	esac
else  # more than 2 arguments suggests user may not be familiar with this application.
	show_usage
fi
# That is for all users, but on update we just want the user since the last time we did this.
# Commented out so we can test without a complicated reset.
echo $END_DATE >> $DATE_FILE 
printf "done\n\n" >&2
exit 0
# EOF
