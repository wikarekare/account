#!/bin/sh
. /wikk/etc/wikk.conf

LOCK_PID_FILE=${TMP_DIR}/graphLastMonth.lock
${LOCKFILE} ${LOCK_PID_FILE} $$
if [ $? != 0 ] ; then  exit 0 ; fi

#Link Balance
#
accountDate_start=`date -v "-1m" "+%Y-%m-01 00:00:00"`
accountDate_stop=`date "+%Y-%m-01 00:00:00"`

year1=`date -v "-1m" "+%Y"`
month1=`date -v "-1m" "+%m"`

year2=`date -v "-2m" "+%Y"`
month2=`date -v "-2m" "+%m"`

${SBIN_DIR}/account/sqlplot_rate.rb --start_when="${accountDate_start}" --stop_when="${accountDate_stop}" ${TMP_PLOT_DIR}/usage_1m_${year1}_${month1}.plot ${TMP_PLOT_DIR}/wikkpT3D_${year1}_${month1}.png | ${GNUPLOT}

${SBIN_DIR}/account/transpose_and_sum_rate.rb ${TMP_PLOT_DIR}/wikkpT3D_${year1}_${month1}_excel.txt ${TMP_PLOT_DIR}/bill_1m_${year1}_${month1}.tsv

${MV} ${TMP_PLOT_DIR}/usage_1m_${year1}_${month1}.plot ${WWW_DIR}/netstat/tsv/usage_1m_${year1}_${month1}.tsv
${MV} ${TMP_PLOT_DIR}/bill_1m_${year1}_${month1}.tsv ${WWW_DIR}/netstat/tsv/bill_1m_${year1}_${month1}.tsv
${CHOWN} www:www ${WWW_DIR}/netstat/tsv/usage_1m_${year1}_${month1}.tsv ${WWW_DIR}/netstat/tsv/bill_1m_${year1}_${month1}.tsv
${RM} ${TMP_PLOT_DIR}/wikkpT3D_${year1}_${month1}_excel.txt

${MV} ${TMP_PLOT_DIR}/wikkpT3D_${year1}_${month1}.png ${WWW_DIR}/netstat/monthly/wikkpT3D_${year1}_${month1}.png
${MV} ${TMP_PLOT_DIR}/wikkpT3D_${year1}_${month1}_link.png ${WWW_DIR}/netstat/monthly/wikkpT3D_${year1}_${month1}_link.png
${CHOWN} www:www ${WWW_DIR}/netstat/monthly/wikkpT3D_${year1}_${month1}.png ${WWW_DIR}/netstat/monthly/wikkpT3D_${year1}_${month1}_link.png

#
${RM} -f ${LOCK_PID_FILE}
