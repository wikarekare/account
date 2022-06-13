#!/usr/local/bin/ruby
load '/wikk/etc/wikk.conf'

TARGET_DIR = "#{WWW_DIR}/#{NETSTAT_DIR}"
START_YEAR = 2006
END_YEAR = 2030

def output_leadin(fd, year, month)
  fd.print <<-HTML
    <html>
    <head>
    <title>Network Stats #{year}-#{'%02d' % month} </title>
    <META HTTP-EQUIV=Pragma CONTENT=no-cache>
    <META HTTP-EQUIV="CACHE-CONTROL" CONTENT="NO-CACHE">
    <script type="text/javascript">
    function doSubmit() {
      theForm=document.getElementById("theForm");
      target = "wikk-month-" + theForm.year.value + "-" + theForm.month.value + ".html";
      document.location = target;
    }
    </script>
    </head>
    <body>
    <h2>Usage for Month starting #{year}-#{'%02d' % month} Billing Period Per Site</h2>
    <form id="theForm"  method="post" action="some_fake_address.php">
    <table>
      <tr>
  HTML
end

def output_year_selector(fd, year)
  fd.print <<-HTML
      <td>
        <select name="year">
  HTML

  (START_YEAR..END_YEAR).each do |y|
    if year == y
      fd.puts "          <option value=\"#{y}\" selected=\"selected\">#{y}</option>"
    else
      fd.puts "          <option value=\"#{y}\">#{y}</option>"
    end
  end

  fd.print <<-HTML
          </select>
        </td>
  HTML
end

def output_month_selector(fd, month)
  fd.print <<-HTML
      <td>
        <select name="month">
  HTML

  (1..12).each do |m|
    if month == m
      fd.puts "          <option value=\"#{'%02d' % m}\" selected=\"selected\">#{'%02d' % m}</option>"
    else
      fd.puts "          <option value=\"#{'%02d' % m}\">#{'%02d' % m}</option>"
    end
  end

  fd.print <<-HTML
        </select>
    </td>
  HTML
end

def output_trailer(fd, year, month)
  fd.print <<-HTML
        <td><input  type="button" value="Submit" onclick="javascript:doSubmit();"/></td>
      </tr>
    </table>

    <table>
            <tr> <td> <img src="monthly/wikkpT3D_#{year}_#{'%02d' % month}.png"></td> </tr>
            <tr> <td> <img src="monthly/wikkpT3D_#{year}_#{'%02d' % month}_link.png"></td> </tr>
    </table><br>
    <a href="tsv/usage_1m_#{year}_#{'%02d' % month}.tsv"> Download </a>
    &nbsp;&nbsp;&nbsp;&nbsp;
    <a href="tsv/bill_1m_#{year}_#{'%02d' % month}.tsv"> Bill </a>
    <p>

    </body>
    </html>
  HTML
end

(START_YEAR..END_YEAR).each do |year|
  (1..12).each do |month|
    File.open("#{TARGET_DIR}/wikk-month-#{year}-#{'%02d' % month}.html", 'w+') do |fd|
      output_leadin(fd, year, month )
      output_year_selector(fd, year)
      output_month_selector(fd, month)
      output_trailer(fd, year, month)
    end
  end
end
