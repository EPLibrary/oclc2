#!/usr/bin/bash
####################################################
#
# Bash shell script for project oclc2
#
# Collect and submit Data Sync Collections data for OCLC.
#    Copyright (C) 2020  Andrew Nisbet
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
#          0.13.01 - Remove ON-ORDER from exclusion list.
#          0.13.00 - Make oclc2driver.sh update the last run file.
#          0.12.01 - Change NSK output file name to include end date, and made variable
#                    names more meaningful N_MIXED => MIXED_PROJECT_NUMBER and 
#                    CANCELS_FINAL_FILE => CANCELS_FINAL_FILE_PRE_NSK.
#          0.12.00 - Fix ugly tarring of submission process.
#          0.11.00 - Use NSK cancel holdings protocol.
#          0.10.02 - Optimization of sorting and uniqing cat keys on item selection
#                    for mixed projects.
#          0.10.01 - Guard for unfound flexkey.
#          0.10.00 - Change cancels submission file name as per OCLC recommendations.
#          0.9.05 - Add more detail to logging.
#          0.9.04 - Remove mrc files so they don't get resubmitted.
#          0.9.03 - Remove flex key file before starting. Improved logging.
#          0.9.02 - Change log directory to home directory.
#          0.9.01 - Cleaned log output.
#          0.9 - Introduced time stamp logging of processes for profiling performance.
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
# checks a file oclc2.last.run, and adjusts its selection date based on the 
# ANSI date found there. If you want just the last 7 days, delete the file. It 
# will be created again with today's date. If you run the script again in 2 days
# only altered records from the last 2 days will be noted and uploaded.
# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
###############################################
# *** Edit these to suit your environment *** #
source /s/sirsi/Unicorn/EPLwork/cronjobscripts/setscriptenvironment.sh
###############################################
VERSION="0.13.00"
# using /bin/sh causes cron to 'nice' the process at '10'!
SHELL=/usr/bin/bash
# default milestone 7 days ago.
START_DATE=$(transdate -d-7)
# That is for all users, but on update we just want the user since the last time we did this. In that case
# we will save the date last run as a zero-byte file.
END_DATE=$(transdate -d-0)
HISTORY_DIRECTORY=$(getpathname hist)
WORKING_DIR=/s/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC2
## cd into working directory and create all files relative to there.
if [ -d "$WORKING_DIR" ]; then
	cd $WORKING_DIR
else
	echo "**error: unable to move to the working directory $WORKING_DIR. Exiting"
	exit 1
fi
LOG=oclc2.$END_DATE.$$.log
CANCELS_HISTORY_FILE_SELECTION=oclc2.cancels.history.file.lst
CANCELS_FLEX_OCLC_FILE=oclc2.cancels.flexkeys.OCLCnumber.lst
CANCELS_UNFOUND_FLEXKEYS=oclc2.cancels.unfound.flexkeys.lst
CANCELS_DIFF_FILE=oclc2.cancels.diff.lst
ERROR_LOG=err.log
## Output file that is used to convert to NSK. See $CANCELS_SUBMISSION for NSK file name.
CANCELS_FINAL_FILE_PRE_NSK=oclc2.cancels.final.lst
### Variables specially for 'mixed' projects.
NOT_THESE_TYPES="PAPERBACK,JPAPERBACK,BKCLUBKIT,COMIC,DAISYRD,EQUIPMENT,E-RESOURCE,FLICKSTOGO,FLICKTUNE,JFLICKTUNE,JTUNESTOGO,PAMPHLET,RFIDSCANNR,TUNESTOGO,JFLICKTOGO,PROGRAMKIT,LAPTOP,BESTSELLER,JBESTSELLR"
NOT_THESE_LOCATIONS="BARCGRAVE,CANC_ORDER,DISCARD,EPLACQ,EPLBINDERY,EPLCATALOG,EPLILL,INCOMPLETE,LONGOVRDUE,LOST,LOST-ASSUM,LOST-CLAIM,LOST-PAID,MISSING,NON-ORDER,BINDERY,CATALOGING,COMICBOOK,INTERNET,PAMPHLET,DAMAGE,UNKNOWN,REF-ORDER,BESTSELLER,JBESTSELLR,STOLEN"
MIXED_CATKEYS_FILE=oclc2.mixed.catkeys.lst
### Submission file names.
# collectionid.symbol.bibholdings.n.mrc where 'collectionid' is the data sync collection
# ID number; 'symbol' is escaped as per the login; 'n' is a number to make the file
# name unique
MIXED_COLLECTION_ID=1023505
CANCEL_COLLECTION_ID=1013230
SYMBOL=cnedm
# ANSI date with a '1' for mixed, on the end. Cancels used to be the same ANSI date with '0' but
# this changed June 2020. Now we submit NSK files. See Readme.md for more details.
MIXED_PROJECT_NUMBER=`date +%Y%m%d`1
CANCELS_SUBMISSION=$CANCEL_COLLECTION_ID.$SYMBOL.$END_DATE.nsk
MIXED_FINAL_MARC_FILE=$MIXED_COLLECTION_ID.$SYMBOL.bibholdings.$MIXED_PROJECT_NUMBER.mrc
SUBMISSION_TAR=submission.tar
# Stores the ANSI date of the last run. All contents are clobbered when script re-runs.
# This script features the ability to collect new users since the last time it ran.
# We save a file with today's date, and then use that with -f on seluser.
DATE_FILE=oclc2.last.run
DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
printf "[%s] %s\n" $DATE_TIME "INIT:init" >>$LOG 
if [[ -s "$DATE_FILE" ]]; then
	# Grab the last line of the file that doesn't start with a hash '#'.
	START_DATE=$(cat "$DATE_FILE" | pipe.pl -Gc0:^# -L-1)
fi
### The script expects to receive commands of either 'mixed', meaning all additions and
### modifications, or 'cancels', indicating to upload items deleted from the catalog during
### the specified time frame. The other accepted command is 'exit', which will, not surprisingly,
### exit the script.

# Outputs OCLC numbers in raw NSK format ready for conversion to CSV.
# This subroutine is used in the Cancels process only.
# param:  The record is a flex key and oclcNumber separated by a pipe: 'AAN-1945|(OCoLC)3329882'
# output: flat MARC record as a string.
# return: 1 if there is an waring of nothing to do, and 0 otherwise.
printNumberSearchKeyRawFormat()
{
	local oclcNumber=$(echo "$1" | pipe.pl -oc1)
	if [[ -z "${oclcNumber// }" ]]; then
		printf "* warning no OCLC number found in record %s, skipping.\n" $1 >&2
		printf "* warning no OCLC number found in record %s, skipping.\n" $1 >>$ERROR_LOG
		return 1
	fi
	echo "|$oclcNumber"  >>$CANCELS_FINAL_FILE_PRE_NSK # like '|(OCoLC)32013207'
	return 0
}

# Collects all the deleted records from history files.
# param: none
# return: always returns 0.
run_cancels()
{
	local DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "run_cancels()::init" >>$LOG
	printf "running cancels from %s to %s\n" $START_DATE $END_DATE >&2
	if [ -s "$CANCELS_FLEX_OCLC_FILE" ]; then
		rm "$CANCELS_FLEX_OCLC_FILE"
	fi
	local start_date=$(echo $START_DATE | pipe.pl -mc0:######_) # Year and month only or dates won't match file.
	local end_date=$(echo $END_DATE | pipe.pl -mc0:#) # Year and month only or dates won't match file.
	# To get the records of bibs that were deleted, we need to find history files since $start_date
	# and grep out where records were deleted. Let's find those history files first.
	# List all the files in the hist directory, start searching for the string $start_date and once found
	# continue to output until DATE_TODAY is found.
	printf "compiling list of files to search %s to %s\n" $START_DATE $END_DATE >&2
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "run_cancels()::egrep." >>$LOG
	# The test server shows that if we don't have an initial file name match for -X, -Y -M fail.
	ls $HISTORY_DIRECTORY | egrep -e "hist(\.Z)?$" | pipe.pl -C"c0:ge$start_date" | pipe.pl -C"c0:le$end_date"  >$CANCELS_HISTORY_FILE_SELECTION
	# Read in the list of history files from $HIST_DIR one-per-line (single string per line)
	for h_file in $(cat $CANCELS_HISTORY_FILE_SELECTION | tr "\n" " ")
	do
		# Search the arg list of log files for entries of remove item (FV) and remove title option (NOY).
		printf "searching history file %s/%s for deleted titles.\n" $HISTORY_DIRECTORY $h_file >&2
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "run_cancels()::zcat.egrep" >>$LOG
		# E201405271803190011R ^S75FVFFADMIN^FEEPLMNA^FcNONE^NQ31221079015892^NOY^NSEPLJPL^IUa554837^tJ554837^aA(OCoLC)56729751^^O00099
		# Extract the cat key and Flex key from the history logs.
		# Using grep initially is faster then let pipe convert '^' to '|', and grep any field with IU or aA and
		# output just that field.
		# First we can't zcat a regular file so when that breaks, use plain old cat.
		# Note to self: zcat implies the '.Z' extension when it runs. 
		if ! zcat "$HISTORY_DIRECTORY/$h_file" 2>/dev/null | egrep -e "FVF" | egrep -e "NOY" >/tmp/oclc2.tmp.zcat.$$; then
			# zcat didn't find any results, maybe the file isn't compressed. Try cat instead.
			cat "$HISTORY_DIRECTORY/$h_file" 2>/dev/null | egrep -e "FVF" | egrep -e "NOY" >/tmp/oclc2.tmp.zcat.$$
		fi
		## before:
		# 20170401|S44FVFFADMIN|FEEPLMNA|FcNONE|NQ31221105319052|NOY|NSEPLLHL|IUa1113832|tJ1113832|aA(OCoLC)640340037||O00102
		printf "collecting all TCN and OCLC numbers.\n" >&2
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "run_cancels()::pipe.pl" >>$LOG
		cat /tmp/oclc2.tmp.zcat.$$ | pipe.pl -W'\^' -m"c0:_########_" | pipe.pl -C"c0:ge$START_DATE" -U | pipe.pl -g"any:IU|aA" -5 2>>$CANCELS_FLEX_OCLC_FILE >/dev/null
		## after:
		# IUa999464|aA(OCoLC)711988979
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "run_cancels()::cleaning up" >>$LOG
		rm /tmp/oclc2.tmp.zcat.$$
	done
	# Now we should have a file like this.
	# IUa1848301|aAocn844956543
	# Clean it for the next selection.
	if [ -s "$CANCELS_FLEX_OCLC_FILE" ]; then
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "run_cancels()::pipe.pl" >>$LOG
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
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "run_cancels()::selcatalog looking for error 111s" >>$LOG
		cat $CANCELS_FLEX_OCLC_FILE | pipe.pl -oc0 -P | selcatalog -iF >/dev/null 2>$CANCELS_UNFOUND_FLEXKEYS
		# The trailing pipe will be useful to sep values in the following diff.pl command.
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "run_cancels()::pipe.pl parse out flex keys" >>$LOG
		cat $CANCELS_UNFOUND_FLEXKEYS | pipe.pl -W'flex=' -zc1 -oc1 -P >/tmp/oclc2.tmp.$$
		mv /tmp/oclc2.tmp.$$ $CANCELS_UNFOUND_FLEXKEYS
		local count=$(cat $CANCELS_UNFOUND_FLEXKEYS | wc -l | pipe.pl -tc0)
		printf "submission includes %s cancelled bib records.\n" $count >&2
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "run_cancels()::diff.pl" >>$LOG
		# Somehow we can end up with a flex key that can't be found. Probably a catalog error, but guard for it by 
		# not passing flex keys that don't have OCLC numbers, which can't be used anyway.
		echo "$CANCELS_UNFOUND_FLEXKEYS and $CANCELS_FLEX_OCLC_FILE" | diff.pl -ec0 -fc0 -mc1 | pipe.pl -zc1 >$CANCELS_DIFF_FILE
		# a809658|(OCoLC)320195792
		# Create the brief delete MARC file of all the entries.
		# If one pre-exists we will delete it now so we can just keep appending in the loop.
		if [[ -s "$CANCELS_FINAL_FILE_PRE_NSK" ]]; then
			rm $CANCELS_FINAL_FILE_PRE_NSK
		fi
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "run_cancels()::printNumberSearchKeyRawFormat.init" >>$LOG
		local dot_count=0
		while read -r file_line
		do
			if ! printNumberSearchKeyRawFormat $file_line
			then
				printf "** error '%s' malformed.\n" $CANCELS_DIFF_FILE >&2
				printf "** error '%s' malformed.\n" $CANCELS_DIFF_FILE >>$ERROR_LOG
				let dot_count=dot_count+1
			fi
		done <$CANCELS_DIFF_FILE
        printf "[%s] %s\n" $DATE_TIME " there were $dot_count errors while processing." >>$LOG
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "run_cancels()::printNumberSearchKeyRawFormat.exit" >>$LOG
		# Now to make the MARC output from the flat file.
		printf "creating marc file.\n" >&2
		DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
		printf "[%s] %s\n" $DATE_TIME "run_cancels():pipe output" >>$LOG
		## This converts the cancel flat file into a marc file ready to send to OCLC.
		## $CANCELS_FINAL_FILE_PRE_NSK needs to be a list similar to the following.
		## |(OCoLC) 12345678
		## |(OCoLC) 12345677
		## |(OCoLC) 12345676
		## | ...
		## Adding -gc1:"OCoLC" because non-OCLC numbers appear in the list. 
		cat $CANCELS_FINAL_FILE_PRE_NSK | pipe.pl -gc1:"OCoLC" -TCSV_UTF-8:"LSN,OCLC_Number" > $CANCELS_SUBMISSION 2>>$ERROR_LOG
		# Log the rejected numbers.
		echo -e "the following records were detected but are not valid OCLC numbers\n-- START REJECT:\n" >>$ERROR_LOG
		cat $CANCELS_FINAL_FILE_PRE_NSK | pipe.pl -Gc1:"OCoLC" >>$ERROR_LOG
		echo -e "-- END REJECT:\n" >>$ERROR_LOG
	fi
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "run_cancels()::exit" >>$LOG
	return 0
}

# Collects all the bib records that were added or modified since the last time it was run.
# param: none
# return: always returns 0.
run_mixed()
{
	local DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "run_mixed()::init" >>$LOG
	printf "running mixed from %s to %s.\n" $START_DATE $END_DATE >&2
	# Since we are selecting all items' catalog keys we should sort and uniq them
	# In testing the number of cat keys drops from 1.4M to 300K keys.
	selitem -t"~$NOT_THESE_TYPES" -l"~$NOT_THESE_LOCATIONS" -oC 2>/dev/null | sort | uniq >/tmp/oclc2.tmp.$$
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "run_mixed()::selcatalog.CREATE" >>$LOG
	## select all the records that were created since the start date.
	printf "adding keys that were created since %s.\n" $START_DATE >&2
	## Select all cat keys that were created after the start date.
	cat /tmp/oclc2.tmp.$$ | selcatalog -iC -p">$START_DATE" -oC >$MIXED_CATKEYS_FILE 2>>$ERROR_LOG
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "run_mixed()::selcatalog.MODIFIED" >>$LOG
	## Now the modified records.
	printf "adding keys that were modified since %s.\n" $START_DATE >&2
	cat /tmp/oclc2.tmp.$$ | selcatalog -iC -r">$START_DATE" -oC >>$MIXED_CATKEYS_FILE 2>>$ERROR_LOG
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "run_mixed()::sort.uniq" >>$LOG
	cat $MIXED_CATKEYS_FILE | sort | uniq >/tmp/oclc2.tmp.$$
	mv /tmp/oclc2.tmp.$$ $MIXED_CATKEYS_FILE
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "run_mixed()::catalogdump" >>$LOG
	cat $MIXED_CATKEYS_FILE | catalogdump -kf035 -om >$MIXED_FINAL_MARC_FILE 2>>$ERROR_LOG
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "run_mixed()::exit" >>$LOG
	## TODO: Remove return statements.
	return 0
}
# Cleans up temp files after process run.
# param:  none.
# return: 0 if everything worked according to plan, and 1 if the final marc file 
#         couldn't be found.
clean_mixed()
{
	local DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "clean_mixed()::init.tar" >>$LOG
	if [ -s "$MIXED_FINAL_MARC_FILE" ]; then
		if [ -s "$SUBMISSION_TAR" ]; then
			tar uvf $SUBMISSION_TAR $MIXED_FINAL_MARC_FILE >>$ERROR_LOG
		else
			tar cvf $SUBMISSION_TAR $MIXED_FINAL_MARC_FILE >>$ERROR_LOG
		fi
		# Once added to the submission tarball get rid of the mrc files so they don't get re-submitted.
		rm "$MIXED_FINAL_MARC_FILE"
	else
		printf "MARC file: '%s' was not created.\n" $MIXED_FINAL_MARC_FILE >>$ERROR_LOG
		return 1
	fi
	if [ -s "$MIXED_CATKEYS_FILE" ]; then
		rm $MIXED_CATKEYS_FILE
	fi
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "clean_mixed()::exit" >>$LOG
	return 0
}
# Cleans up temp files after process run.
# param:  none.
# return: 0 if everything worked according to plan, and 1 if the final marc file 
#         couldn't be found.
clean_cancels()
{
	local DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "clean_cancels()::init" >>$LOG
	if [ -s "$CANCELS_SUBMISSION" ]; then
		if [ -s "$SUBMISSION_TAR" ]; then
			tar uvf $SUBMISSION_TAR $CANCELS_SUBMISSION >>$ERROR_LOG
		else
			tar cvf $SUBMISSION_TAR $CANCELS_SUBMISSION >>$ERROR_LOG
		fi
		# Once added to the submission tarball get rid of the mrc files so they don't get re-submitted.
		rm "$CANCELS_SUBMISSION"
	else
		printf "MARC file: '%s' was not created.\n" $CANCELS_SUBMISSION >>$ERROR_LOG
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
	if [ -s "$CANCELS_FINAL_FILE_PRE_NSK" ]; then
		rm $CANCELS_FINAL_FILE_PRE_NSK
	fi
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "clean_cancels()::exit" >>$LOG
	return 0
}
# Ask if for the date if user using no args.
# If the user has not specified any args, they will be asked what action they want to
# do, but we also need to confirm the last milestone date.
# param:  none
# return: 0
ask_mod_date()
{
	local DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "ask_mod_date()::init" >>$LOG
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
	DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
	printf "[%s] %s\n" $DATE_TIME "ask_mod_date()::exit" >>$LOG
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
	printf "  (See above for explaination of flags). The date is not checked as a valid date but\n" >&2
	printf "  will throw an error if not a valid ANSI date format of 'YYYYMMDD'.\n" >&2
	printf "  \n"                                            >&2
	printf "  The last run date is appended after all the files have been uploaded to oclc\n  '%s'\n" >&2
	printf "  If the file can't be found\n" >&2
	printf "  the last run date defaults to 7 days ago, and a new file with today's date will be created.\n" >&2
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
elif [ $# -eq 1 ] || [ $# -eq 2 ]; then # .
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
# The updating of the last run date is done by oclc2driver.sh on ilsdev1.epl.ca when it runs successfully. 
printf "done\n\n" >&2
DATE_TIME=$(date +%Y%m%d-%H:%M:%S)
printf "[%s] %s\n" $DATE_TIME "INIT:exit" >>$LOG
exit 0
# EOF
