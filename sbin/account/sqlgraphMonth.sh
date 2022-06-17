#!/bin/bash
. /wikk/etc/wikk.conf

#Link Balance
#
theDay=`date "+%d"`
accountDate=`date "+%Y-%m-01 00:00:00"`

${SBIN_DIR}/account/sqlplot_rate.rb --start_when="${accountDate}" ${TMP_PLOT_DIR}/usage_asofnow.plot ${TMP_PLOT_DIR}/wikkpT3D.png > ${TMP_PLOT_DIR}/1s.plot
${GNUPLOT} < ${TMP_PLOT_DIR}/1s.plot

${SBIN_DIR}/account/transpose_and_sum_rate.rb ${TMP_PLOT_DIR}/wikkpT3D_excel.txt ${TMP_PLOT_DIR}/bill_asofnow.tsv

${RM} ${TMP_PLOT_DIR}/wikkpT3D_excel.txt

${MV} ${TMP_PLOT_DIR}/usage_asofnow.plot ${WWW_DIR}/netstat/tsv/asofnow.tsv
${MV} ${TMP_PLOT_DIR}/bill_asofnow.tsv ${WWW_DIR}/netstat/tsv/bill_asofnow.tsv
${CHOWN} www:www ${WWW_DIR}/netstat/tsv/asofnow.tsv ${WWW_DIR}/netstat/tsv/bill_asofnow.tsv

${MV} ${TMP_PLOT_DIR}/wikkpT3D.png ${WWW_DIR}/netstat
${MV} ${TMP_PLOT_DIR}/wikkpT3D_link.png ${WWW_DIR}/netstat
${CHOWN} www:www ${WWW_DIR}/netstat/wikkpT3D.png ${WWW_DIR}/netstat/wikkpT3D_link.png
