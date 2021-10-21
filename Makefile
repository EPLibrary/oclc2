####################################################
# Makefile for project oclc2 
# Created: 2016-12-12
#
# Manages the distribution of oclc2.pl.
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
# Written by Andrew Nisbet at Edmonton Public Library
#  
####################################################
# Change comment below for appropriate server.
PRODUCTION_SERVER=edpl.sirsidynix.net
TEST_SERVER=edpltest.sirsidynix.net
USER=sirsi
ILS_REMOTE=/software/EDPL/Unicorn/EPLwork/cronjobscripts/OCLC2
EPL_ILS_REMOTE=/home/ils/oclc
LOCAL=~/projects/oclc2
APP=oclc2.sh
APP_DRIVER=oclc2driver.sh
README=Readme.md

.PHONY: test production epl-ils

test: ${APP}
	scp ${LOCAL}/${APP} ${USER}@${TEST_SERVER}:${ILS_REMOTE}
	scp ${LOCAL}/${README} ${USER}@${TEST_SERVER}:${ILS_REMOTE}

production: test epl-ils
	scp ${LOCAL}/${APP} ${USER}@${PRODUCTION_SERVER}:${ILS_REMOTE}
	scp ${LOCAL}/${README} ${USER}@${PRODUCTION_SERVER}:${ILS_REMOTE}

epl-ils:
	scp ${LOCAL}/${APP_DRIVER} ils@epl-ils.epl.ca:${EPL_ILS_REMOTE}/bin
	scp ${LOCAL}/${README} ils@epl-ils.epl.ca:${EPL_ILS_REMOTE}
	scp ${LOCAL}/oclc2.password.txt ils@epl-ils.epl.ca:${EPL_ILS_REMOTE}
