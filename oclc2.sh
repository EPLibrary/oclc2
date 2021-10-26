#!/bin/bash
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
. /software/EDPL/Unicorn/EPLwork/cronjobscripts/setscriptenvironment.sh
###############################################
VERSION="2.06.04"
SHELL=/usr/bin/bash
# default milestone 7 days ago.
START_DATE=$(transdate -d-7)
# That is for all users, but on update we just want the user since the last time we did this. In that case
# we will save the date last run as a zero-byte file.
END_DATE=$(transdate -d-0)
HISTORY_DIRECTORY=$(getpathname hist)
WORKING_DIR=/software/EDPL/Unicorn/EPLwork/cronjobscripts/OCLC2
## Set up logging.
LOG_FILE="$WORKING_DIR/oclc2.log"
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
## cd into working directory and create all files relative to there.
if [ -d "$WORKING_DIR" ]; then
	cd $WORKING_DIR
else
	logit "**error: unable to move to the working directory $WORKING_DIR. Exiting" 
	exit 1
fi
CANCELS_HISTORY_FILE_SELECTION=oclc2.cancels.history.file.lst
CANCELS_FLEX_OCLC_FILE=oclc2.cancels.flexkeys.OCLCnumber.lst
CANCELS_UNFOUND_FLEXKEYS=oclc2.cancels.unfound.flexkeys.lst
CANCELS_DIFF_FILE=oclc2.cancels.diff.lst

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

if [[ -s "$DATE_FILE" ]]; then
	# Grab the last line of the file that doesn't start with a hash '#'.
	START_DATE=$(cat "$DATE_FILE" | pipe.pl -Gc0:^# -L-1)
fi
### The script expects to receive commands of either 'mixed', meaning all additions and
### modifications, or 'cancels', indicating to upload items deleted from the catalog during
### the specified time frame. The other accepted command is 'exit', which will, not surprisingly,
### exit the script.

# Usage message then exits.
# param:  none.
# return: exits with status 99
# Prints out usage message.
usage()
{
    cat << EOFU!
 Usage: $0 [flags]
                  
  $0 collects modified (created or modified) and/or deleted bibliograhic 
  metadata for OCLC's DataSync Collection service. This script does not upload to OCLC. 
  (See oclc2driver.sh for more information about loading bib records to DataSync Collections.) 
                                              
  If run with no arguments both mixed and cancels will be run from the last run date 
  or for the period covering the last 7 calendar days if there's no last-run-date file 
  in the working directory.                                
                                              
  If no paramaters are provided, the start date will be read as the last non-commented line
  in $DATE_FILE. If $DATE_FILE doesn't exist the default will be 7 days ago by default.
  
  Currently the start date would be $START_DATE 
   
  Flags:
    -c, -cancels, --cancels [yyyymmdd] - Run cancels report from a given date.                 
    -m, -mixed, --mixed [yyyymmdd] - Run mixed project report from a given date.           
    -b, -both_mixed_cancels, --both_mixed_cancels [yyyymmdd] - Run both cancel and mixed projects
	  (default action) from a given date.
	-h, -help, --help - print this help message and exit.
	-v, -version, --version - print version and exit.
  
  Examples: 
    $0                     # Run both cancels and mixed starting from 7 days ago.
    $0 -b=20210301         # Run both cancels and mixed back to March 1, 2021.
    $0 --cancels=20200822  # Run cancels back from August 22 2020.
                                              
  The date is not checked as a valid date. 
                                              
  The last run date is appended after all the files have been uploaded to oclc.
  If the file can't be found the last run date defaults to 7 days ago, and a new file 
  with today's date will be created.
  
  Note that all dates must be in ANSI format (YYYYMMDD), must be the only value on the  
  last uncommented line. A comment line starts with '#'. 
                                              
  The last-run-date file is not essential and will be recreated if it is deleted, however 
  it is useful in showing the chronology of times the process has been run.                         
EOFU!
}

# Outputs OCLC numbers in raw NSK format ready for conversion to CSV.
# This subroutine is used in the Cancels process only.
# param:  The record is a flex key and oclcNumber separated by a pipe: 'AAN-1945|(OCoLC)3329882'
# output: flat MARC record as a string.
# return: 1 if there is an waring of nothing to do, and 0 otherwise.
printNumberSearchKeyRawFormat()
{
	local oclcNumber=$(echo "$1" | pipe.pl -oc1)
	if [[ -z "${oclcNumber// }" ]]; then
		logit "* warning no OCLC number found in record %s, skipping."
	else
		echo "|$oclcNumber"  >>$CANCELS_FINAL_FILE_PRE_NSK # like '|(OCoLC)32013207'
	fi
}

# Collects all the deleted records from history files.
# param: none
# return: always returns 0.
run_cancels()
{
	logit "run_cancels()::init"
	logit "running cancels from $START_DATE to $END_DATE"
	if [ -s "$CANCELS_FLEX_OCLC_FILE" ]; then
		rm "$CANCELS_FLEX_OCLC_FILE"
	fi
	local start_date=$(echo $START_DATE | pipe.pl -mc0:######_) # Year and month only or dates won't match file.
	local end_date=$(echo $END_DATE | pipe.pl -mc0:#) # Year and month only or dates won't match file.
	# To get the records of bibs that were deleted, we need to find history files since $start_date
	# and grep out where records were deleted. Let's find those history files first.
	# List all the files in the hist directory, start searching for the string $start_date and once found
	# continue to output until DATE_TODAY is found.
	logit "compiling list of files to search $START_DATE to $END_DATE"
	logit "run_cancels()::egrep."
	# The test server shows that if we don't have an initial file name match for -X, -Y -M fail.
	ls $HISTORY_DIRECTORY | egrep -e "hist(\.Z)?$" | pipe.pl -C"c0:ge$start_date" | pipe.pl -C"c0:le$end_date"  >$CANCELS_HISTORY_FILE_SELECTION
	# Read in the list of history files from $HIST_DIR one-per-line (single string per line)
	for h_file in $(cat $CANCELS_HISTORY_FILE_SELECTION | tr "\n" " ")
	do
		# Search the arg list of log files for entries of remove item (FV) and remove title option (NOY).
		logit "searching history file $HISTORY_DIRECTORY/$h_file for deleted titles."
		logit "run_cancels()::zcat.egrep"
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
		logit "collecting all TCN and OCLC numbers."
		logit "run_cancels()::pipe.pl"
		cat /tmp/oclc2.tmp.zcat.$$ | pipe.pl -W'\^' -m"c0:_########_" | pipe.pl -C"c0:ge$START_DATE" -U | pipe.pl -g"any:IU|aA" -5 2>>$CANCELS_FLEX_OCLC_FILE >/dev/null
		## after:
		# IUa999464|aA(OCoLC)711988979
		logit "run_cancels()::cleaning up"
		rm /tmp/oclc2.tmp.zcat.$$
	done
	# Now we should have a file like this.
	# IUa1848301|aAocn844956543
	# Clean it for the next selection.
	if [ -s "$CANCELS_FLEX_OCLC_FILE" ]; then
		logit "run_cancels()::pipe.pl"
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
		logit "searching catalog for missing catalog keys."
		logit "run_cancels()::selcatalog looking for error 111s"
		cat $CANCELS_FLEX_OCLC_FILE | pipe.pl -oc0 -P | selcatalog -iF >/dev/null 2>$CANCELS_UNFOUND_FLEXKEYS
		# The trailing pipe will be useful to sep values in the following diff.pl command.
		logit "run_cancels()::pipe.pl parse out flex keys"
		cat $CANCELS_UNFOUND_FLEXKEYS | pipe.pl -W'flex=' -zc1 -oc1 -P >/tmp/oclc2.tmp.$$
		mv /tmp/oclc2.tmp.$$ $CANCELS_UNFOUND_FLEXKEYS
		local count=$(cat $CANCELS_UNFOUND_FLEXKEYS | wc -l | pipe.pl -tc0)
		logit "submission includes $count cancelled bib records."  
		logit "run_cancels()::diff.pl"
		# Somehow we can end up with a flex key that can't be found. Probably a catalog error, but guard for it by 
		# not passing flex keys that don't have OCLC numbers, which can't be used anyway.
		echo "$CANCELS_UNFOUND_FLEXKEYS and $CANCELS_FLEX_OCLC_FILE" | diff.pl -ec0 -fc0 -mc1 | pipe.pl -zc1 >$CANCELS_DIFF_FILE
		# a809658|(OCoLC)320195792
		# Create the brief delete MARC file of all the entries.
		# If one pre-exists we will delete it now so we can just keep appending in the loop.
		if [[ -s "$CANCELS_FINAL_FILE_PRE_NSK" ]]; then
			rm $CANCELS_FINAL_FILE_PRE_NSK
		fi
		logit "run_cancels()::printNumberSearchKeyRawFormat.init"
		local dot_count=0
		while read -r file_line
		do
			if ! printNumberSearchKeyRawFormat $file_line
			then
				logit "** error '$CANCELS_DIFF_FILE' malformed."
				dot_count=$((dot_count+1))
			fi
		done <$CANCELS_DIFF_FILE
        logit " there were $dot_count errors while processing."
		logit "run_cancels()::printNumberSearchKeyRawFormat.exit"
		# Now to make the MARC output from the flat file.
		logit "creating marc file."
		logit "run_cancels():pipe output"
		## This converts the cancel flat file into a marc file ready to send to OCLC.
		## $CANCELS_FINAL_FILE_PRE_NSK needs to be a list similar to the following.
		## |(OCoLC) 12345678
		## |(OCoLC) 12345677
		## |(OCoLC) 12345676
		## | ...
		## Adding -gc1:"OCoLC" because non-OCLC numbers appear in the list. 
		cat $CANCELS_FINAL_FILE_PRE_NSK | pipe.pl -gc1:"OCoLC" -TCSV_UTF-8:"LSN,OCLC_Number" > $CANCELS_SUBMISSION 2>>$LOG_FILE
		# Log the rejected numbers.
		logit "the following records were detected but are not valid OCLC numbers."
		logit "-- START REJECT:" 
		cat $CANCELS_FINAL_FILE_PRE_NSK | pipe.pl -Gc1:"OCoLC" >>$LOG_FILE
		logit "-- END REJECT:"
	fi
	logit "run_cancels()::exit"
}

# Collects all the bib records that were added or modified since the last time it was run.
# param: none
# return: always returns 0.
run_mixed()
{
	logit "run_mixed()::init"
	logit "running mixed from $START_DATE to $END_DATE."
	# Since we are selecting all items' catalog keys we should sort and uniq them
	# In testing the number of cat keys drops from 1.4M to 300K keys.
	selitem -t"~$NOT_THESE_TYPES" -l"~$NOT_THESE_LOCATIONS" -oC 2>/dev/null | sort | uniq >/tmp/oclc2.tmp.$$
	logit "run_mixed()::selcatalog.CREATE"
	## select all the records that were created since the start date.
	logit "adding keys that were created since $START_DATE."
	## Select all cat keys that were created after the start date.
	cat /tmp/oclc2.tmp.$$ | selcatalog -iC -p">$START_DATE" -oC >$MIXED_CATKEYS_FILE 2>>$LOG_FILE
	logit "run_mixed()::selcatalog.MODIFIED"
	## Now the modified records.
	logit "adding keys that were modified since $START_DATE."
	cat /tmp/oclc2.tmp.$$ | selcatalog -iC -r">$START_DATE" -oC >>$MIXED_CATKEYS_FILE 2>>$LOG_FILE
	logit "run_mixed()::sort.uniq"
	cat $MIXED_CATKEYS_FILE | sort | uniq >/tmp/oclc2.tmp.$$
	mv /tmp/oclc2.tmp.$$ $MIXED_CATKEYS_FILE
	logit "run_mixed()::catalogdump"
	if [ -s "$MIXED_CATKEYS_FILE" ]; then
		# To remove the 250 tag as Shona reqested, and at the behest of OCLC who were having issues 
		# matching ON-ORDER records. Specifically they are having trouble matching 250 tags that 
		# contain information about on-order release dates. This may be because the 250 was made 
		# repeatable in 2013, and additional 250 tags throw off the matching algorithm used by OCLC.
		#
		# To mitigate that we will remove just 250 tags that start with 'Expected release' as Shona
		# comments:
		# 'It looks like 250s beginning with “Expected release” should be our target.' --October 15, 2021
		# This was agreed to by Larry 'Lar' Wolkan from OCLC.
		local flat_wo_on_order_250_tags=/tmp/oclc2_wo_250.$$.flat
		cat $MIXED_CATKEYS_FILE | catalogdump -kf035 -of | grep -v -i -e '\.250\.[ \t]+\|aExpected release' >$flat_wo_on_order_250_tags
		# With that convert it into marc 21.
		cat $flat_wo_on_order_250_tags | flatskip -if -aMARC -om >$MIXED_FINAL_MARC_FILE 2>>$LOG_FILE
		[ -f "$flat_wo_on_order_250_tags" ] rm $flat_wo_on_order_250_tags
		logit "finished filtering out the on-order 250 tags with release dates, and cleaned up."
	else
		logit "*warning, run_mixed()::$MIXED_CATKEYS_FILE was empty or could not be found."
	fi
	logit "run_mixed()::exit"
}
# Cleans up temp files after process run.
# param:  none.
# return: 0 if everything worked according to plan, and 1 if the final marc file 
#         couldn't be found.
clean_mixed()
{
	logit "clean_mixed()::init.tar"
	if [ -s "$MIXED_FINAL_MARC_FILE" ]; then
		if [ -s "$SUBMISSION_TAR" ]; then
			tar uvf $SUBMISSION_TAR $MIXED_FINAL_MARC_FILE >>$LOG_FILE
		else
			tar cvf $SUBMISSION_TAR $MIXED_FINAL_MARC_FILE >>$LOG_FILE
		fi
		# Once added to the submission tarball get rid of the mrc files so they don't get re-submitted.
		rm "$MIXED_FINAL_MARC_FILE"
	else
		logit "MARC file: '$MIXED_FINAL_MARC_FILE' was not created."
		return 1
	fi
	if [ -s "$MIXED_CATKEYS_FILE" ]; then
		rm $MIXED_CATKEYS_FILE
	fi
	logit "clean_mixed()::exit"
}
# Cleans up temp files after process run.
# param:  none.
# return: 0 if everything worked according to plan, and 1 if the final marc file 
#         couldn't be found.
clean_cancels()
{
	logit "clean_cancels()::init"
	if [ -s "$CANCELS_SUBMISSION" ]; then
		if [ -s "$SUBMISSION_TAR" ]; then
			tar uvf $SUBMISSION_TAR $CANCELS_SUBMISSION >>$LOG_FILE
		else
			tar cvf $SUBMISSION_TAR $CANCELS_SUBMISSION >>$LOG_FILE
		fi
		# Once added to the submission tarball get rid of the mrc files so they don't get re-submitted.
		rm "$CANCELS_SUBMISSION"
	else
		logit "MARC file: '$CANCELS_SUBMISSION' was not created.\n"  
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
	logit "clean_cancels()::exit"
}

### Check input parameters.
# $@ is all command line parameters passed to the script.
# -o is for short options like -v
# -l is for long options with double dash like --version
# the comma separates different long options
# -a is for long options with single dash like -version
options=$(getopt -l "cancels:,both_mixed_cancels:,help,mixed:,version" -o "c:b:hm:v" -a -- "$@")
if [ $? != 0 ] ; then echo "Failed to parse options...exiting." >&2 ; exit 1 ; fi
# set --:
# If no arguments follow this option, then the positional parameters are unset. Otherwise, the positional parameters
# are set to the arguments, even if some of them begin with a ‘-’.
eval set -- "$options"

while true
do
    case $1 in
    -c|--cancels)
        shift
        export START_DATE="$1"
		logit "=== Start ($0, $VERSION)"
		run_cancels
		clean_cancels
		exit 0
		;;
    -b|--both_mixed_cancels)
		shift
        export START_DATE="$1"
		logit "=== Start ($0, $VERSION)"
		run_cancels
		clean_cancels
		run_mixed
		clean_mixed
		exit 0
		;;
    -h|--help)
        usage
        exit 0
        ;;
	-m|--mixed)
        shift
        export START_DATE="$1"
		logit "=== Start ($0, $VERSION)"
		run_mixed
		clean_mixed
		exit 0
		;;
    -v|--version)
        echo "$0 version: $VERSION"
        exit 0
        ;;
    --)
        shift
        break
        ;;
    esac
    shift
done
## To get here there were no command line options, so use defaults.
logit "=== Start ($0, $VERSION)"
run_cancels
clean_cancels
run_mixed
clean_mixed
# The updating of the last run date is done by oclc2driver.sh on ilsdev1.epl.ca when it runs successfully. 
logit "done"
logit "=== End"
exit 0
# EOF
