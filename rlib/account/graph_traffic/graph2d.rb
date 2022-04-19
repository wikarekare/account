class Graph_2D < Graph_Parent

  def initialize(mysql_conf, host, split_in_out, start_time,end_time, url=nil)
    @mysql_conf = mysql_conf
    graph(host, split_in_out, start_time,end_time)
    if(url)
      @images = "<p><a href=\"#{url}\"><img src=\"/#{NETSTAT_DIR}/tmp/#{host}.png?start_time=#{start_time.xmlschema}&end_time=#{end_time.xmlschema}\"></a></p>\n";
    else
      @images = "<p><img src=\"/#{NETSTAT_DIR}/tmp/#{host}.png?start_time=#{start_time.xmlschema}&end_time=#{end_time.xmlschema}\"></p>\n";
    end
  end
  
  #All could get large, so we do it in a hierarchy of distribution sites, then client sites.
  def self.graph_all(mysql_conf, split_in_out, start_time, end_time)
    images = Graph_2D.new(mysql_conf, 'Total', split_in_out, start_time, end_time).images
    
    if (my = Mysql::new(mysql_conf.host, mysql_conf.dbuser, mysql_conf.key, mysql_conf.db)) != nil
      #Get list of active links from backbone table.
      res = my.query("select site_name from backbone where site_name like 'link%' and active = 1 order by site_name ")
      if res != nil
        res.each do |row|
          url = "/admin/traffic.html?host=#{row[0]}&graphtype=dist&start=#{start_time.strftime("%Y-%m-%d %H:%M:%S")}&end_time=#{end_time.strftime("%Y-%m-%d %H:%M:%S")}"
          images += Graph_2D.new(mysql_conf, row[0], split_in_out, start_time, end_time, url).images
        end
        res.free
      end

      res = my.query("select site_name from distribution where distribution.active = 1 order by site_name")
      if res != nil
        res.each do |row|
          url = "/admin/traffic.html?host=#{row[0]}&graphtype=dist&start=#{start_time.strftime("%Y-%m-%d %H:%M:%S")}&end_time=#{end_time.strftime("%Y-%m-%d %H:%M:%S")}"
          images += Graph_2D.new(mysql_conf, row[0], split_in_out, start_time, end_time, url).images
        end
        res.free 
     end
      my.close
    end
    return images
  end
 
  def self.graph_border(mysql_conf, split_in_out, start_time, end_time)
    images = Graph_2D.new(mysql_conf, 'Total', split_in_out, start_time, end_time).images
    if (my = Mysql::new(mysql_conf.host, mysql_conf.dbuser, mysql_conf.key, mysql_conf.db)) != nil
      #Get list of active links from backbone table.
      res = my.query("select site_name from backbone where site_name like 'link%' and active = 1 order by site_name ")
      if res != nil
        res.each do |row|
          url = "/admin/traffic.html?host=#{row[0]}&graphtype=dist&start=#{start_time.strftime("%Y-%m-%d %H:%M:%S")}&end_time=#{end_time.strftime("%Y-%m-%d %H:%M:%S")}"
          images += Graph_2D.new(mysql_conf, row[0], split_in_out, start_time, end_time, url).images
        end
        res.free
      end
       
      my.close
    end
    return images
  end

  def self.graph_clients(mysql_conf, dist_host, split_in_out, start_time, end_time)
    images = ""
    if (my = Mysql::new(mysql_conf.host, mysql_conf.dbuser, mysql_conf.key, mysql_conf.db)) != nil
      res = my.query("select customer.site_name as wikk from distribution, customer, customer_distribution " +
                     " where distribution.site_name = '#{dist_host}' and " +
                     " distribution.distribution_id = customer_distribution.distribution_id " +
                     " and customer_distribution.customer_id = customer.customer_id order by wikk")
      if res != nil
        res.each do |row|
          url = "/admin/ping.html?host=#{row[0]}&start=#{start_time.strftime("%Y-%m-%d %H:%M:%S")}&end_time=#{end_time.strftime("%Y-%m-%d %H:%M:%S")}"
          images += Graph_2D.new(mysql_conf, row[0], split_in_out, start_time, end_time, url ).images
        end
        res.free
      end
      my.close
    end
    return images
  end
  
  #List of graphs for sites on specified link
  def self.graph_link(mysql_conf, link, split_in_out, start_time, end_time)
    link_number = link[-1,1].to_i #Last digit.
    images = ""
    if (my = Mysql::new(mysql_conf.host, mysql_conf.dbuser, mysql_conf.key, mysql_conf.db)) != nil
      res = my.query("select customer.site_name as wikk from customer " +
                     " where link = #{link_number} order by wikk")
      if res != nil
        res.each do |row|
          url = "/admin/ping.html?host=#{row[0]}&start=#{start_time.strftime("%Y-%m-%d %H:%M:%S")}&end_time=#{end_time.strftime("%Y-%m-%d %H:%M:%S")}"
          images += Graph_2D.new(mysql_conf, row[0], split_in_out, start_time, end_time, url ).images
        end
        res.free
      end
      my.close
    end
    return images
  end

  private

  def graph(host, split_in_out, start_time,end_time)
    t = Time.now
    temp_filename_base = "#{TMP_DIR}/#{NETSTAT_DIR}/#{host}_#{t.tv_sec}#{t.tv_usec}"
    temp_filename_txt = temp_filename_base + ".txt"
    temp_filename_plot = temp_filename_base + ".plot"

    TmpFile.open(temp_filename_txt, "w") do |txt_fd|
      #txt_fd.no_unlink; #uncomment for testing, so we can see what was produced.
  		TmpFile.open(temp_filename_plot,'w') do |plot_fd|
  		#plot_fd.no_unlink  #uncomment for testing, so we can see what was produced.
        y_max = fetch_data(txt_fd, host, start_time, end_time, split_in_out)
        gen_graph_instructions(plot_fd, split_in_out, temp_filename_txt, host, start_time, end_time, y_max)
        plot_fd.flush
        txt_fd.flush
        TmpFile.exec(GNUPLOT, temp_filename_plot )
      end
    end
  end
  
  #We record packet size in bytes, in 10s intervals, and display in bits per second, so we have to divide by 10 and multiply * 8
  #There will be retrys from the ADSL modems, and 8 byte per packet encoding loss, that will mean that we don't always show what the ISP sees.
  def gen_graph_instructions(fd, split_in_out, data_file, host, start_time, end_time, y_max)
			fd.print <<-EOF
set output "#{WWW_DIR}/#{NETSTAT_DIR}/tmp/#{host}.png"
set key outside right top vertical Right noreverse enhanced autotitles box
set timefmt "%Y-%m-%d %H:%M:%S"
set datafile separator '\\t'
set xdata time
set format x "%H:%M\\n%m/%d"
set xlabel 'Time'
#set xtics 900
set xrange ["#{start_time.to_sql}":"#{end_time.to_sql}"]
set ylabel 'Traffic (Mb/s)'
#set yrange [0:#{y_max[0] * 0.8}]
set yrange [0:35]
set samples 720
EOF

    if split_in_out == true
      fd.print <<-EOF
set terminal png truecolor font "Monoco,12" size 900,250 small
set key off
set multiplot layout 1,2 title "#{host} traffic #Mb/s (10s Avg)\\n#{start_time.to_sql}:#{end_time.to_sql}"
set title '#{host} Traffic In'
plot "#{data_file}" using 1:($2 * 0.8) t 'Mb/s out' w impulses lc rgb "red"
set title '#{host} Traffic Out'
#set yrange [0:#{y_max[1]}]
set yrange [0:35]
plot "#{data_file}" using 1:(($3-$2) * 0.8)  t 'Mb/s in' w impulses lc rgb "green"
EOF
    else
      fd.print <<-EOF
set terminal png truecolor font "Monoco,12" size 640,250 small
set title "#{host} traffic #Mb/s (10s Avg)\\n#{start_time.to_sql}:#{end_time.to_sql}"
plot "#{data_file}" using 1:($3 * 0.8) t 'Mb/s out' w impulses  lc rgb "green",  "#{data_file}" using 1:($2 * 0.8)  t 'Mb/s in' w impulses lc rgb "red"
EOF
    end
	end
	
	def fetch_data(fd, host, start_time, end_time, split_in_out)
	  y_max = [16.0, 1.0]
    
    if (my = Mysql::new(@mysql_conf.host, @mysql_conf.dbuser, @mysql_conf.key, @mysql_conf.db)) != nil
      if(host == "Total")
        res = my.query("select log_timestamp, sum(bytes_in)/(1024*1024.0), sum(bytes_in + bytes_out)/(1024*1024.0)  from log_summary where " +
         "log_timestamp >= '#{start_time.to_sql}' and " +
         "log_timestamp <= '#{end_time.to_sql}' and " +
         " hostname like 'link%'  group by log_timestamp order by log_timestamp") 
      elsif host !~ /^wikk/ && host !~ /^link/ && host !~ /^admin[12]/ #The consolidated traffic of each distribution site.
        res = my.query("select log_timestamp, sum(bytes_in)/(1024*1024.0), sum(bytes_in + bytes_out)/(1024*1024.0)  from log_summary, distribution, customer, customer_distribution where " +
        " log_timestamp >= '#{start_time.to_sql}' and " +
        " log_timestamp <= '#{end_time.to_sql}' and " +
        "  distribution.site_name = '#{my.escape_string(host)}'  and  distribution.distribution_id = customer_distribution.distribution_id and customer_distribution.customer_id = customer.customer_id and customer.site_name = log_summary.hostname   group by log_timestamp order by log_timestamp")
      else #Regular wikk hosts, the links and admin1 & 2
        res = my.query("select log_timestamp, bytes_in/(1024*1024.0), (bytes_in + bytes_out)/(1024*1024.0)  from log_summary where " + 
        " hostname = '#{my.escape_string(host)}' and " +
        " log_timestamp >= '#{start_time.to_sql}' and " +
        " log_timestamp <= '#{end_time.to_sql}' " +
        " order by log_timestamp")
      end
      if res != nil
        res.each do |row|
          if split_in_out
            y_max[0] = row[1].to_f if row[1].to_f > y_max[0] #in bytes
            y_max[1] = (row[2].to_f - row[1].to_f) if (row[2].to_f - row[1].to_f) > y_max[1] #out bytes
          else
            y_max[0] = row[2].to_f  if row[2].to_f  > y_max[0] #single value used
          end
          fd.puts row.join("\t")
        end
        res.free
      end
      my.close
    end
    return y_max
  end
  
end
