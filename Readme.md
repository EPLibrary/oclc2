=== 2016-12-12, (updated Mon Sep 11 10:02:29 MDT 2017) ===

Project Notes
-------------

Instructions for Running
--
This script comes in 2 parts, the first is run on EPLAPP, and is called ```oclc2.sh```. It 
performs the selection of records that need to be updated at OCLC. There is a bug in
the process that is difficult to diagnose. When the script runs as a cronjob, it takes
almost 7 days. We have tried a number of solutions, but none work, and the staff at 
the U of A help desk are at a dead end. If the script is run by hand it should finishA
in 20 minutes, give or take, which is what we will have to do until a fix is found.

The second script, ```oclc2driver.sh```, is used to SFTP the results from EPLAPP to OCLC. 
This is done because the ILS does not have modern FTP services on it, and SFTP can 
be done securely from ilsdev1.epl.ca. When cron on that machine runs, it SCPs the 
MARC file from the ILS (```/s/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC2/```), and saves 
it to:
```
/home/ilsdev/projects/oclc2/s/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC2
```

By default the script will collect mixed and cancel project data and submit to OCLC.

The replacement is to accomodate OCLC's DataSync Collections which is a replacement 
for BatchLoad.

Usage: oclc2.sh [c|m|b[YYYYMMDD]][x]
oclc2.sh collects modified (created or modified) and/or deleted bibliograhic
metadata for OCLC's DataSync Collection service. This script does not upload to OCLC.
(See oclc2driver.sh for more information about loading bib records to DataSync Collections.

If run with no arguments both mixed and cancels will be run from the last run date
or for the period covering the last 7 calendar days if there's no last-run-date file
in the working directory.
Example: oclc2.sh

Using a single param controls report type, but default date will be %s and $START_DATE
you will be asked to confirm the date before starting.
Example: oclc2.sh [c|m|b][x]
  * c - Run cancels report.
  * m - Run mixed project report.
  * b - Run both cancel and mixed projects (default action).
  * x - Show usage, then exit.

Using a 2 params allows selection of report type and milestone since last submission.
Example: oclc2.sh [c|m|b] 20170101
(See above for explaination of flags). The date value is not checked and
will throw an error if not a valid ANSI date (YYYMMDD format).

Once the report is done it will save today's date into a file $LAST_RUN_DATE and use
this date as the last milestone for the next submission. If the file can't be found
the last submission date defaults to 7 days ago, and a new file with today's date will be created.
Note that all dates must be in ANSI format (YYYYMMDD), must be the only value on the line,
and only the last listed, non-commented '#' line value will be used when selecting records.
The last-run-date file is not essential and will be recreated if it is deleted.

Workflow
--------
The oclc2.sh script runs from the ILS and is cron'ed. It creates a 'submission.tar' file that
contains the MARC files from each process that runs. There may be more than one MARC file if
the cancels and mixed projects ran. There could also be multiple dates if the sister script
'oclc2driver.sh' failed to run. No matter, the oclc2.sh will continue to accumulate the MARC
files until 'oclc2driver.sh' removes the submission tarball.

'oclc2driver.sh' is cron'ed on ilsdev1.epl.ca to run after 'oclc2.sh'. It coordinates the uploading
of files to OCLC via SFTP.

Product Description:
Bash shell script written by Andrew Nisbet for Edmonton Public Library, distributable by the enclosed license.

Repository Information:
This product is under version control using Git.

Dependencies:
None

Known Issues:
None
