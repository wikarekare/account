class Graph_3D < Graph_Parent
  attr_accessor :hosts
  
  def initialize(mysql_conf, dist_host, links, start_time, end_time)
    @mysql_conf = mysql_conf
    @images = ""
    hosts = ["Total"]
    if (my = Mysql::new(@mysql_conf.host, @mysql_conf.dbuser, @mysql_conf.key, @mysql_conf.db)) != nil
      if(dist_host == 'all' || dist_host == 'dist')
        if links == true || dist_host == 'dist' #Transition. Will remove links test
          #Get list of active links from backbone table.
          #Combine with list of distribution towers, from distribution table.
          res = my.query("(SELECT site_name, 1 as rank from backbone where site_name like 'link%' and active = 1)" +
                         " UNION " +
                         " (SELECT site_name, 2 as rank from distribution where distribution.active = 1 ) " +
                         " order by rank,site_name")
        else
          #Get list of customer sites
          res = my.query("SELECT customer.site_name as wikk from distribution, customer, customer_distribution " +
                         " where distribution.active = 1  " + 
                         " and distribution.distribution_id = customer_distribution.distribution_id " +
                         " and customer_distribution.customer_id = customer.customer_id order by wikk")
        end
      else
        #Get list of customer sites feed from a specific distrubiton tower
        res = my.query("select customer.site_name as wikk from distribution, customer, customer_distribution where distribution.site_name = '#{dist_host}' and distribution.distribution_id = customer_distribution.distribution_id and customer_distribution.customer_id = customer.customer_id order by wikk")
      end

      if(res == nil || res.num_rows == 0)
        raise("No Host #{dist_host}")
      end

      res.each do |row|
        hosts << row[0]
      end
      res.free
      my.close
    end
    t = Time.now
    temp_filename_base = "#{TMP_DIR}/#{NETSTAT_DIR}/#{dist_host}_t#{t.tv_sec}#{t.tv_usec}"
    temp_filename_txt = temp_filename_base + ".txt"
    temp_filename_plot = temp_filename_base + ".plot"
    TmpFile.open(temp_filename_plot, "w") do |plot_fd|
      #plot_fd.no_unlink
      TmpFile.open(temp_filename_txt,'w') do |txt_fd|
        #txt_fd.no_unlink
        z_max = fetch_data(txt_fd, dist_host, links, hosts, start_time, end_time)
        gen_graph_instructions(plot_fd, dist_host, hosts, temp_filename_txt, start_time, end_time, z_max)
        plot_fd.flush
        txt_fd.flush
        TmpFile.exec(GNUPLOT, temp_filename_plot)
      end
    end
    
    @images = "<p><img width=\"90%\" src=\"/#{NETSTAT_DIR}/tmp/#{dist_host}_traffic.png?start_time=#{start_time.xmlschema}&end_time=#{end_time.xmlschema}\"></p>\n"
  end
  
  def self.graph_parent(mysql_conf, host, links, start_time, end_time)
    if host == 'all' || host == 'dist'
      g = Graph_3D.new(mysql_conf, host, links, start_time, end_time)
      g.hosts = [host]
      return g
    end
    begin
      if (my = Mysql::new(mysql_conf.host, mysql_conf.dbuser, mysql_conf.key, mysql_conf.db)) != nil
      res = my.query("( select distribution.site_name from distribution, customer, customer_distribution " +
                    "where customer.site_name = '#{host}' " +
                    " and customer.customer_id = customer_distribution.customer_id "  + 
                    " and customer_distribution.distribution_id = distribution.distribution_id ) union " +
                    " ( select site_name from distribution where site_name = '#{host}' ) limit 1  "
                    )
      raise("No Host #{host}") if(res == nil || res.num_rows == 0)
      parent = res.fetch_row[0]
      g = Graph_3D.new(mysql_conf, parent, links, start_time, end_time) 
      g.hosts = [parent]
    end
    ensure
      res.free if res != nil
      my.close if my != nil
    end
    return g
  end
  
  private
  
  def gen_graph_instructions(fd, host, hosts, data_file, start_time, end_time, z_max)
#set key below Left
			fd.print <<-EOF
set output "#{WWW_DIR}/#{NETSTAT_DIR}/tmp/#{host}_traffic.png"
set terminal png truecolor font "Monoco,12" size 1000,650 small
set title '#Mb/s (10s Avg) #{start_time.strftime("%Y-%m-%d %H:%M:%S")}:#{end_time.strftime("%Y-%m-%d %H:%M:%S")}'
set view 80,15
set lmargin 5
set lmargin at screen 0.12
set rmargin 990
set rmargin at screen 0.8
set tmargin at screen 0.95
set bmargin at screen 0.15
set ticslevel 0
set grid xtics
set key out r t
set timefmt "%Y-%m-%d %H:%M:%S"
set datafile separator '\\t'
set xtics 1
set xrange [0:#{hosts.length-1}]
set ydata time
set format y "%H:%M"
set ylabel 'Time'
set yrange ["#{start_time.strftime("%Y-%m-%d %H:%M:%S")}":"#{end_time.strftime("%Y-%m-%d %H:%M:%S")}"]
set zlabel 'Traffic (Mb/s)'
set zlabel  offset character 6, 0, 0 font "" textcolor lt -1 rotate by 90
#set zrange [0:#{z_max * 0.9}] 
set zrange [0:35] 
set multiplot
EOF

    fd.print "splot \"#{data_file}\" using (0):1:($#{2 + hosts.length} * 0.8) t '0: #{hosts[0]}' w impulses lc rgb \"green\""
    hosts[1..-1].each_with_index do |h,i|
      fd.print ", \"#{data_file}\" using (#{i+1}):1:($#{i+3 + hosts.length} * 0.8) t '#{i+1}: #{h}' w impulses lc rgb \"green\""
    end
    fd.print "\n\n"

    colours = ["#FF3300", "#993300", "#FFFF00", "#663300", "#FF3399", "#FF00FF", "#9933FF", "#0000FF", "#33CCFF", "#3300CC"]
    fd.print "splot \"#{data_file}\" using (0):1:($2 * 0.8) t '0: #{hosts[0]}' w impulses lc rgb \"black\""
    hosts[1..-1].each_with_index do |h,i|
      fd.print ", \"#{data_file}\" using (#{i+1}):1:($#{i+3} * 0.8) t '#{i+1}: #{h}' w impulses lc rgb \"#{colours[i%10]}\""
    end
    fd.print "\n"
  end

  
  #Print a line into data file for plot.
  def print_hosts_line(fd, line, total_in, total_in_out)
    line[1] = total_in
    line[(line.length - 1) / 2 + 1] = total_in_out
    fd.puts line.join("\t")
  end
  
  #Retrieve traffic for either a list of towers, or a list of sites.
  # @param dist_host [String] all, if every tower
  # @param links [Boolean] true, if provided with list of towers
  # @param hosts [Array, String] site_names of either the towers or the actual client sites
  # @param start_time [Time] specify from when
  # @param end_time [Time] specify to when
  def fetch_data(fd, dist_host, links, hosts, start_time, end_time)
    z_max = 35.0 #Default maximum z value for plot graph. Might grow, but wont reduce.
    if (my = Mysql::new(@mysql_conf.host, @mysql_conf.dbuser, @mysql_conf.key, @mysql_conf.db)) != nil
      if(dist_host == 'all' || dist_host == 'dist') 
        if links == true || dist_host == 'dist' #summarize by distribution tower.
          #Query traffic logs, grouping clients by distribution tower
          #And query traffic log entries by link, adding to previous query
          res = my.query("select log_timestamp, distribution.site_name as thename, sum(bytes_in)/(1024*1024.0), sum(bytes_in + bytes_out)/(1024*1024.0)  " +
                        " from log_summary, distribution, customer, customer_distribution where " +
                        " log_timestamp >= '#{start_time.to_sql}' and " +
                         "log_timestamp <= '#{end_time.to_sql}' and " +
                        "  distribution.distribution_id = customer_distribution.distribution_id " +
                        " and customer_distribution.customer_id = customer.customer_id and customer.site_name = log_summary.hostname   " +
                        " group by log_timestamp, distribution.site_name  " +
                        " UNION  " +
                        " select log_timestamp, hostname as thename, bytes_in/(1024*1024.0), (bytes_in + bytes_out)/(1024*1024.0)  from log_summary where " +
                                " log_timestamp >= '#{start_time.to_sql}' and " +
                                 "log_timestamp <= '#{end_time.to_sql}' and " +
                                " hostname like 'link%' " +
                        " order by log_timestamp, thename")
        else
          #Query traffic logs by client site_name.
          res = my.query("select log_timestamp, hostname, bytes_in/(1024*1024.0), (bytes_in + bytes_out)/(1024*1024.0)  from log_summary, distribution, customer, customer_distribution where " + 
          " log_timestamp >= '#{start_time.to_sql}' and " +
           "log_timestamp <= '#{end_time.to_sql}' and " +
          " distribution.distribution_id = customer_distribution.distribution_id and customer_distribution.customer_id = customer.customer_id and customer.site_name = log_summary.hostname  " +
                          " order by log_timestamp, hostname" )
        end
      else
        #Query traffic logs, for a specific distribution tower's clients
        res = my.query("select log_timestamp, hostname, bytes_in/(1024*1024.0), (bytes_in + bytes_out)/(1024*1024.0)  from log_summary, distribution, customer, customer_distribution where " +
        "log_timestamp >= '#{start_time.to_sql}' and " +
         "log_timestamp <= '#{end_time.to_sql}'  and " +
         "distribution.site_name = '#{dist_host}'  and   distribution.distribution_id = customer_distribution.distribution_id and customer_distribution.customer_id = customer.customer_id and customer.site_name = log_summary.hostname  order by log_timestamp,hostname")
      end
      
      #Set up references, by site_name, using a hash to the array of hosts
      hostmap = {}
      hosts.each_with_index do |h,i| 
        hostmap[h] = i + 1
      end
      
      #Graph Title
    	fd.print "\#Clients connected to #{dist_host} (#{res.num_rows})\n\#datetime\t#{hosts.join("\t")}\t#{hosts.join("\t")}\n"
      fd.print "#{(start_time-1).strftime("%Y-%m-%d %H:%M:%S")}"

      #first line has 0.0 entries.
      (1..hosts.length).each { |h| fd.print "\t0.0\t0.0" }
      fd.print "\n"
      
      line = Array.new(hosts.length * 2 + 1, '-') #init to no data. '-' indicates no data, and gets overwriten if we get data
      total_in = total_in_out = 0.0 #Totals for this time stamp
      if res != nil
        res.each do |row| #Process each traffic log row returned from the query above.
          next if row[1] == 'TERMINATED'
          raise "Unexpected host: #{row[1]} not in #{hosts.join(',')}" if hostmap[row[1]] == nil

          if(line[0] == '-') #Starting a new line
            line[0] = row[0]  #Record the timestamp, so we know when we get a new one
            total_in = total_in_out = 0.0 #Totals for this time stamp
          elsif line[0] != row[0] #Got a new timestamp, so dump stats to plot file, and reset.
            print_hosts_line(fd, line, total_in, total_in_out) #Output last record for gnuplot to use later on.
            line.collect! { '-' } #Reset to no data. '-' indicates no data, and gets overwriten if we get data
            line[0] = row[0] #Record the timestamp, so we know when we get a new one
            total_in = total_in_out = 0.0 #Reset Total for this time stamp
          end
          #Processing log entries for this time stamp.
          line[hostmap[row[1]]] = row[2] # in
          line[hostmap[row[1]] + hosts.length] = row[3] # in + out
          if row[1] !~ /^link/ #Not traffic summarized by link, so add to in/out totals for this timestamp.
            total_in += row[2].to_f 
            total_in_out += row[3].to_f 
            z_max = total_in_out if total_in_out > z_max #Recording the maximum value seen for sizing plot scale
          end
        end
        res.free
      end
      print_hosts_line(fd, line, total_in, total_in_out) if line[0] != '-' #Catch all, for the last line.
      
      my.close
    end
    return z_max #Return maximum z value seen, so plot scale can be set (mostly ignore this now)
  end
end



