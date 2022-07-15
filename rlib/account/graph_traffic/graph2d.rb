class Graph_2D < Graph_Parent
  def initialize(mysql_conf, host, split_in_out, start_time, end_time, url = nil)
    super
    @mysql_conf = mysql_conf
    graph(host, split_in_out, start_time, end_time)
    @images = if url
                "<p><a href=\"#{url}\"><img src=\"/#{NETSTAT_DIR}/tmp/#{host}.png?start_time=#{start_time.xmlschema}&end_time=#{end_time.xmlschema}\"></a></p>\n"
              else
                "<p><img src=\"/#{NETSTAT_DIR}/tmp/#{host}.png?start_time=#{start_time.xmlschema}&end_time=#{end_time.xmlschema}\"></p>\n"
              end
  end

  # All could get large, so we do it in a hierarchy of distribution sites, then client sites.
  def self.graph_all(mysql_conf, split_in_out, start_time, end_time)
    images = Graph_2D.new(mysql_conf, 'Total', split_in_out, start_time, end_time).images

    WIKK::SQL.connect(mysql_conf) do |sql|
      # Get list of active links from backbone table.
      query = <<~SQL
        SELECT site_name
        FROM backbone
        WHERE site_name LIKE 'link%'
        AND active = 1
        ORDER BY site_name
      SQL
      sql.each_hash(query) do |row|
        url = "/admin/traffic.html?host=#{row['site_name']}&graphtype=dist&start=#{start_time.strftime('%Y-%m-%d %H:%M:%S')}&end_time=#{end_time.strftime('%Y-%m-%d %H:%M:%S')}"
        images += Graph_2D.new(mysql_conf, row['site_name'], split_in_out, start_time, end_time, url).images
      end

      query = <<~SQL
        SELECT site_name
        FROM distribution
        WHERE distribution.active = 1
        ORDER BY site_name
      SQL
      sql.each_hash(query) do |row|
        url = "/admin/traffic.html?host=#{row['site_name']}&graphtype=dist&start=#{start_time.strftime('%Y-%m-%d %H:%M:%S')}&end_time=#{end_time.strftime('%Y-%m-%d %H:%M:%S')}"
        images += Graph_2D.new(mysql_conf, row['site_name'], split_in_out, start_time, end_time, url).images
      end
    end
    return images
  end

  def self.graph_border(mysql_conf, split_in_out, start_time, end_time)
    images = Graph_2D.new(mysql_conf, 'Total', split_in_out, start_time, end_time).images
    WIKK::SQL.connect(mysql_conf) do |sql|
      # Get list of active links from backbone table.
      query = <<~SQL
        SELECT site_name
        FROM backbone
        WHERE site_name LIKE 'link%'
        AND active = 1
        ORDER BY site_name
      SQL
      sql.each_hash(query) do |row|
        url = "/admin/traffic.html?host=#{row['site_name']}&graphtype=dist&start=#{start_time.strftime('%Y-%m-%d %H:%M:%S')}&end_time=#{end_time.strftime('%Y-%m-%d %H:%M:%S')}"
        images += Graph_2D.new(mysql_conf, row['site_name'], split_in_out, start_time, end_time, url).images
      end
    end
    return images
  end

  def self.graph_clients(mysql_conf, dist_host, split_in_out, start_time, end_time)
    images = ''
    WIKK::SQL.connect(mysql_conf) do |sql|
      query = <<~SQL
        SELECT customer.site_name AS wikk
        FROM distribution, customer, customer_distribution
        WHERE distribution.site_name = '#{dist_host}'
        AND distribution.distribution_id = customer_distribution.distribution_id
        AND customer_distribution.customer_id = customer.customer_id
        ORDER BY wikk
      SQL
      sql.each_hash(query) do |row|
        url = "/admin/ping.html?host=#{row['wikk']}&start=#{start_time.strftime('%Y-%m-%d %H:%M:%S')}&end_time=#{end_time.strftime('%Y-%m-%d %H:%M:%S')}"
        images += Graph_2D.new(mysql_conf, row['wikk'], split_in_out, start_time, end_time, url ).images
      end
    end
    return images
  end

  # List of graphs for sites on specified link
  def self.graph_link(mysql_conf, link, split_in_out, start_time, end_time)
    link_number = link[-1, 1].to_i # Last digit.
    images = ''
    WIKK::SQL.connect(mysql_conf) do |sql|
      query = <<~SQL
        SELECT customer.site_name AS wikk
        FROM customer
        WHERE link = #{link_number}
        ORDER BY wikk"
      SQL
      sql.each_hash(query) do |row|
        url = "/admin/ping.html?host=#{row['wikk']}&start=#{start_time.strftime('%Y-%m-%d %H:%M:%S')}&end_time=#{end_time.strftime('%Y-%m-%d %H:%M:%S')}"
        images += Graph_2D.new(mysql_conf, row['wikk'], split_in_out, start_time, end_time, url ).images
      end
    end
    return images
  end

  private def graph(host, split_in_out, start_time, end_time)
    t = Time.now
    temp_filename_base = "#{TMP_DIR}/#{NETSTAT_DIR}/#{host}_#{t.tv_sec}#{t.tv_usec}"
    temp_filename_txt = temp_filename_base + '.txt'
    temp_filename_plot = temp_filename_base + '.plot'

    TmpFileMod::TmpFile.open(temp_filename_txt, 'w') do |txt_fd|
      # txt_fd.no_unlink; #uncomment for testing, so we can see what was produced.
      TmpFileMod::TmpFile.open(temp_filename_plot, 'w') do |plot_fd|
        # plot_fd.no_unlink  #uncomment for testing, so we can see what was produced.
        y_max = fetch_data(txt_fd, host, start_time, end_time, split_in_out)
        gen_graph_instructions(plot_fd, split_in_out, temp_filename_txt, host, start_time, end_time, y_max)
        plot_fd.flush
        txt_fd.flush
        TmpFileMod::TmpFile.exec(GNUPLOT, temp_filename_plot )
      end
    end
  end

  # We record packet size in bytes, in 10s intervals, and display in bits per second, so we have to divide by 10 and multiply * 8
  # There will be retrys from the ADSL modems, and 8 byte per packet encoding loss, that will mean that we don't always show what the ISP sees.
  private def gen_graph_instructions(fd, split_in_out, data_file, host, start_time, end_time, y_max)
    fd.print <<~EOF
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
      fd.print <<~EOF
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
      fd.print <<~EOF
        set terminal png truecolor font "Monoco,12" size 640,250 small
        set title "#{host} traffic #Mb/s (10s Avg)\\n#{start_time.to_sql}:#{end_time.to_sql}"
        plot "#{data_file}" using 1:($3 * 0.8) t 'Mb/s out' w impulses  lc rgb "green",  "#{data_file}" using 1:($2 * 0.8)  t 'Mb/s in' w impulses lc rgb "red"
      EOF
    end
  end

  private def fetch_data(fd, host, start_time, end_time, split_in_out)
    y_max = [ 16.0, 1.0 ]

    WIKK::SQL.connect(@mysql_conf) do |sql|
      query = if host == 'Total'
                <<~SQL
                  SELECT log_timestamp, sum(bytes_in)/(1024*1024.0) AS b_in, sum(bytes_in + bytes_out)/(1024*1024.0) AS b_out
                  FROM log_summary
                  WHERE log_timestamp >= '#{start_time.to_sql}'
                  AND log_timestamp <= '#{end_time.to_sql}'
                  AND hostname like 'link%'
                  GROUP BY log_timestamp
                  ORDER BY log_timestamp
                SQL
              elsif host !~ /^wikk/ && host !~ /^link/ && host !~ /^admin[12]/ # The consolidated traffic of each distribution site.
                <<~SQL
                  SELECT log_timestamp, sum(bytes_in)/(1024*1024.0) AS b_in, sum(bytes_in + bytes_out)/(1024*1024.0) AS b_out
                  FROM log_summary, distribution, customer, customer_distribution
                  WHERE log_timestamp >= '#{start_time.to_sql}'
                  AND log_timestamp <= '#{end_time.to_sql}'
                  AND distribution.site_name = '#{WIKK::SQL.escape(host)}'
                  AND  distribution.distribution_id = customer_distribution.distribution_id
                  AND customer_distribution.customer_id = customer.customer_id
                  AND customer.site_name = log_summary.hostname
                  GROUP BY log_timestamp
                  ORDER BY log_timestamp
                SQL
              else # Regular wikk hosts, the links and admin1 & 2
                <<~SQL
                  SELECT log_timestamp, bytes_in/(1024*1024.0) AS b_in, (bytes_in + bytes_out)/(1024*1024.0) AS b_out
                  FROM log_summary
                  WHERE hostname = '#{WIKK::SQL.escape(host)}'
                  AND log_timestamp >= '#{start_time.to_sql}'
                  AND log_timestamp <= '#{end_time.to_sql}'
                  ORDER BY log_timestamp
                SQL
              end
      sql.each_hash(query) do |row|
        if split_in_out
          y_max[0] = row['b_in'].to_f if row['b_in'].to_f > y_max[0] # in bytes
          y_max[1] = (row['b_out'].to_f - row['b_in'].to_f) if (row['b_out'].to_f - row['b_in'].to_f) > y_max[1] # out bytes
        elsif row['b_out'].to_f > y_max[0]
          y_max[0] = row['b_out'].to_f
        end
        fd.puts "#{row['log_timestamp']}\t#{row['b_in']}\t#{row['b_out']}"
      end
    end
    return y_max
  end
end
