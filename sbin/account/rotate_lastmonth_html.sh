#!/bin/sh
. /wikk/etc/wikk.conf

LOCK_PID_FILE=${TMP_DIR}/graphLastMonth.lock
${LOCKFILE} ${LOCK_PID_FILE} $$
if [ $? != 0 ] ; then  exit 0 ; fi

year1=`date -v "-1m" "+%Y"`
month1=`date -v "-1m" "+%m"`

year2=`date -v "-2m" "+%Y"`
month2=`date -v "-2m" "+%m"`

#Shuffle the html files, so they point to the newest last two months
${RM} -f ${WWW_DIR}/netstat/lastmonth.html
${RM} -f ${WWW_DIR}/netstat/month-2.html
${LN} -s ${WWW_DIR}/netstat/wikk-month-${year1}-${month1}.html ${WWW_DIR}/netstat/lastmonth.html
${LN} -s ${WWW_DIR}/netstat/wikk-month-${year2}-${month2}.html ${WWW_DIR}/netstat/month-2.html
${CHOWN} -h www:www ${WWW_DIR}/netstat/lastmonth.html ${WWW_DIR}/netstat/month-2.html

${CAT} > ${WWW_DIR}/netstat/lastmonthx.html <<EOF
<html>
<head>
<title>Last Month Network Stats</title>
<META HTTP-EQUIV=Pragma CONTENT=no-cache>
<META HTTP-EQUIV="CACHE-CONTROL" CONTENT="NO-CACHE">
</head>
<body>
<h2>Usage Last Month's Billing Period Per Site</h2>
<a href="month-2.html">Two Months ago</a> <a href="wikkPerSiteGraphs.html">This Month</a><br>

<table>
        <tr> <td> <img src="monthly/wikkpT3D_${year1}_${month1}.png"></td> </tr>
        <tr> <td> <img src="monthly/wikkpT3D_${year1}_${month1}_link.png"></td> </tr>
</table><br>
<a href="tsv/usage_1m_${year1}_${month1}.tsv">Download</a> <a href="tsv/bill_1m_${year1}_${month1}.tsv">Bill</a>
<p>

</body>
</html>
EOF

#
${RM} -f ${LOCK_PID_FILE}
