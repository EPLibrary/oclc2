## Project update Fri Oct 16 08:27:50 MDT 2020
Removed ON-ORDER from exclude locations list.

## Project update Mon Sep 14 12:41:48 MDT 2020
/s/sirsi/Unicorn/EPLwork/cronjobscripts/OCLC2/oclc2.last.run is now 
updated by oclc2driver.sh when it has finally finished submitting 
files. This will ensure that if it fails to run, oclc2.sh will go 
back in time to the point where submissions started to fail.

== Project update Wed August 11 2020
There are some changes to the way that cancels are processed from now on.
Based on the recommendations of Larry Wolkan of OCLC.org, we will now 
submit a Number Search Key (NSK) file, which is a UTF-8 CSV with '.nsk'
extension.

Identification of holdings to cancel will remain the same, however the 
script now makes NSK CSV UTF-8 files, not flat and MARC files.

Many records have multiple entries in the 035 field, but turns out you 
only need the first one. The remainder are separated by a 'z' sub-field
and can be ingored.

Pipe.pl is used to extract the 035 from flat files. I use pipe.pl again
to format the OCLC numbers into the NSK file format as follows.

=== Non-MARC Numeric Search Key (NSK) production instructions

Data must be sent as a CSV UTF-8 (Comma delimited) file, containing two columns.

The first column is labeled ```LSN```, and is essentially an empty column. 
Processing of the data will add an arbitrary value so that local bibliographic 
data (LDBs) can be created and WorldCat records can be output. I don't know
what this means but the first column can be left empty and does process.

The second column should be labeled, ```OCLC_Number``` and contains the OCLC 
control numbers. The prefix (OCoLC) should be added to each OCLC control number. 

Example: ```(OCoLC)198765401```

=== Submitting NSK files

The site and user name have changed, but the password remains the same.

HOST: filex-r3.oclc.org
USER_NAME: fx_cnedm
PASSWORD: <no change>
PATH:  /xfer/metacoll/in/bib 
FILE_NAME: 1013230.cnedm.20200811.nsk (File name change for cancels only)

Upload directory is:
 /xfer/metacoll/in/bib

Continue to use this new NSK method for your cancels Collection ID: 1013230

Continue to use the regular way for your set holdings Collection ID: 1023505

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

Usage: oclc2.sh [flags{yyyymmdd}]
oclc2.sh collects modified (created or modified) and/or deleted bibliograhic 
  metadata for OCLC's DataSync Collection service. This script does not upload to OCLC. 
  (See oclc2driver.sh for more information about loading bib records to DataSync Collections.) 
                                              
  If run with no arguments both mixed and cancels will be run from the last run date 
  or for the period covering the last 7 calendar days if there's no last-run-date file 
  in the working directory.                                
                                              
  If no paramaters are provided, the start date will be read as the last non-commented line
  in $DATE_FILE. If $DATE_FILE doesn't exist the default will be 7 days ago by default.
  
  Currently the start date would be TODAY -7. 
   
  Flags:
    -c, -cancels, --cancels [yyyymmdd] - Run cancels report from a given date.                 
    -m, -mixed, --mixed [yyyymmdd] - Run mixed project report from a given date.           
    -b, -both_mixed_cancels, --both_mixed_cancels [yyyymmdd] - Run both cancel and mixed projects
	  (default action) from a given date.
  
  Examples: 
    oclc2.sh                     # Run both cancels and mixed starting from 7 days ago.
    oclc2.sh -b=20210301         # Run both cancels and mixed back to March 1, 2021.
    oclc2.sh --cancels=20200822  # Run cancels back from August 22 2020.
                                              
  The date is not checked as a valid date. 
                                              
  The last run date is appended after all the files have been uploaded to oclc.
  If the file can't be found the last run date defaults to 7 days ago, and a new file 
  with today's date will be created.
  
  Note that all dates must be in ANSI format (YYYYMMDD), must be the only value on the  
  last uncommented line. A comment line starts with '#'. 
                                              
  The last-run-date file is not essential and will be recreated if it is deleted, however 
  it is useful in showing the chronology of times the process has been run.

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
Reported: September 22, 2017
---
The brief records represent just 'cancels' and the other two files would be for your set holdings, correct?  If so, the brief records will have to have their own cancels collection with some slightly adjusted parameters.

After checking Collection Manager, I see there is a delete collection for CNEDM already in place (1013230).  This could be used with a few adjustments:
Once the new collection was created you would have to make the Collection Type as 'Delete WorldCat Holdings'
The collection type is already set correctly

And then they would need to be resubmitted with the cancels collection ID 1013230 and remamed

```1023505.cnedm.bibholdings.201709110.mrc``` would need to become  ```1023505,cnedm.bibcancles.20170922.mrc``` or something named like that, just as long as the cancels ID was used 1st in the name.

Fixed, Fri Sep 22 12:30:21 MDT 2017


