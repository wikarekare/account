#!/bin/sh
. /wikk/etc/wikk.conf

${SBIN_DIR}/account/graphLastMonth.sh
${SBIN_DIR}/account/rotate_lastmonth_html.sh
${SBIN_DIR}/account/dummy_start_of_month_log.rb
