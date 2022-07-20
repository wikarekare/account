class Graph_3D < Graph_Parent
  attr_accessor :hosts

  def initialize(mysql_conf, dist_host, links, start_time, end_time)
    super
    @mysql_conf = mysql_conf
    @images = ''
    hosts = [ 'Total' ]
    WIKK::SQL.connect(@mysql_conf) do |sql|
      query = if dist_host == 'all' || dist_host == 'dist'
                if links == true || dist_host == 'dist' # Transition. Will remove links test
                  # Get list of active links from backbone table.
                  # Combine with list of distribution towers, from distribution table.
                  <<~SQL
                    (SELECT site_name as wikk, 1 AS rank FROM backbone WHERE site_name LIKE 'link%' AND active = 1)
                    UNION
                    (SELECT site_name as wikk, 2 AS rank FROM distribution WHERE distribution.active = 1 )
                    ORDER BY rank,wikk
                  SQL
                else
                  # Get list of customer sites
                  <<~SQL
                    SELECT customer.site_name AS wikk
                    FROM distribution, customer, customer_distribution
                    WHERE distribution.active = 1
                    AND distribution.distribution_id = customer_distribution.distribution_id
                    AND customer_distribution.customer_id = customer.customer_id
                    ORDER BY wikk
                  SQL
                end
              else
                # Get list of customer sites feed from a specific distrubiton tower
                <<~SQL
                  SELECT customer.site_name AS wikk
                  FROM distribution, customer, customer_distribution
                  WHERE distribution.site_name = '#{dist_host}'
                  AND distribution.distribution_id = customer_distribution.distribution_id
                  AND customer_distribution.customer_id = customer.customer_id
                  ORDER BY wikk
                SQL
              end

      sql.each_hash(query) do |row|
        hosts << row['wikk']
      end

      if hosts.empty?
        raise("No Host #{dist_host}")
      end
    end
    t = Time.now
    temp_filename_base = "#{TMP_DIR}/#{NETSTAT_DIR}/#{dist_host}_t#{t.tv_sec}#{t.tv_usec}"
    temp_filename_txt = temp_filename_base + '.txt'
    temp_filename_plot = temp_filename_base + '.plot'
    TmpFileMod::TmpFile.open(temp_filename_plot, 'w') do |plot_fd|
      # plot_fd.no_unlink
      TmpFileMod::TmpFile.open(temp_filename_txt, 'w') do |txt_fd|
        # txt_fd.no_unlink
        z_max = fetch_data(txt_fd, dist_host, links, hosts, start_time, end_time)
        gen_graph_instructions(plot_fd, dist_host, hosts, temp_filename_txt, start_time, end_time, z_max)
        plot_fd.flush
        txt_fd.flush
        TmpFileMod::TmpFile.exec(GNUPLOT, temp_filename_plot)
      end
    end

    @images = "<p><img width=\"90%\" src=\"/#{NETSTAT_DIR}/tmp/#{dist_host}_traffic.png?start_time=#{start_time.xmlschema}&end_time=#{end_time.xmlschema}\"></p>\n"
  end

  def self.graph_parent(mysql_conf, host, links, start_time, end_time)
    if host == 'all' || host == 'dist'
      g = Graph_3D.new(mysql_conf, host, links, start_time, end_time)
      g.hosts = [ host ]
      return g
    end
    WIKK::SQL.connect(mysql_conf) do |sql|
      query = <<~SQL
        ( SELECT distribution.site_name AS site
          FROM distribution, customer, customer_distribution
          WHERE customer.site_name = '#{host}'
          AND customer.customer_id = customer_distribution.customer_id
          AND customer_distribution.distribution_id = distribution.distribution_id
        )
        UNION
        ( SELECT site_name AS site
          FROM distribution
          WHERE site_name = '#{host}'
        )
        LIMIT 1
      SQL

      res = sql.query_hash(query)
      parent = res.first['site']
      g = Graph_3D.new(mysql_conf, parent, links, start_time, end_time)
      g.hosts = [ parent ]
      return g
    end
    raise("No Host #{host}")
  end

  private def gen_graph_instructions(fd, host, hosts, data_file, start_time, end_time, z_max)
    # set key below Left
    fd.print <<~EOF
      set output "#{WWW_DIR}/#{NETSTAT_DIR}/tmp/#{host}_traffic.png"
      set terminal png truecolor font "Monoco,12" size 1000,650 small
      set title '#Mb/s (10s Avg) #{start_time.strftime('%Y-%m-%d %H:%M:%S')}:#{end_time.strftime('%Y-%m-%d %H:%M:%S')}'
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
      set xrange [0:#{hosts.length - 1}]
      set ydata time
      set format y "%H:%M"
      set ylabel 'Time'
      set yrange ["#{start_time.strftime('%Y-%m-%d %H:%M:%S')}":"#{end_time.strftime('%Y-%m-%d %H:%M:%S')}"]
      set zlabel 'Traffic (Mb/s)'
      set zlabel  offset character 6, 0, 0 font "" textcolor lt -1 rotate by 90
      #set zrange [0:#{z_max * 0.9}]
      set zrange [0:35]
      set multiplot
    EOF

    fd.print "splot \"#{data_file}\" using (0):1:($#{2 + hosts.length} * 0.8) t '0: #{hosts[0]}' w impulses lc rgb \"green\""
    hosts[1..-1].each_with_index do |h, i|
      fd.print ", \"#{data_file}\" using (#{i + 1}):1:($#{i + 3 + hosts.length} * 0.8) t '#{i + 1}: #{h}' w impulses lc rgb \"green\""
    end
    fd.print "\n\n"

    colours = [ '#FF3300', '#993300', '#FFFF00', '#663300', '#FF3399', '#FF00FF', '#9933FF', '#0000FF', '#33CCFF', '#3300CC' ]
    fd.print "splot \"#{data_file}\" using (0):1:($2 * 0.8) t '0: #{hosts[0]}' w impulses lc rgb \"black\""
    hosts[1..-1].each_with_index do |h, i|
      fd.print ", \"#{data_file}\" using (#{i + 1}):1:($#{i + 3} * 0.8) t '#{i + 1}: #{h}' w impulses lc rgb \"#{colours[i % 10]}\""
    end
    fd.print "\n"
  end

  # Print a line into data file for plot.
  private def print_hosts_line(fd, line, total_in, total_in_out)
    line[1] = total_in
    line[(line.length - 1) / 2 + 1] = total_in_out
    fd.puts line.join("\t")
  end

  # MariaDB is currently really slow, if the log_summary
  # table is joined with another table (mysql 5.7 wasn't)
  # Doing two queries, and the join in code, is hundreds of times faster
  def fetch_dist_data(dist_site, links, start_time, end_time)
    link_query = <<~SQL
      SELECT site_name FROM line WHERE active=1 ORDER BY site_name
    SQL
    dist_query = if dist_site == 'all' || dist_site == 'dist'
                   links = true
                   <<~SQL
                     SELECT d.site_name AS dist_site, c.site_name AS cust_site
                     FROM distribution AS d
                     JOIN customer_distribution USING (distribution_id)
                     JOIN customer AS c USING (customer_id)
                     WHERE d.active = 1
                     AND c.active = 1
                   SQL
                 else
                   <<~SQL
                     SELECT d.site_name AS dist_site, c.site_name AS cust_site
                     FROM distribution AS d
                     JOIN customer_distribution USING (distribution_id)
                     JOIN customer AS c USING (customer_id)
                     WHERE d.site_name = '#{dist_site}'
                     AND c.active=1
                   SQL
                 end
    log_query = <<~SQL
      SELECT log_timestamp, hostname, bytes_in, bytes_out
      FROM log_summary
      WHERE log_timestamp >= '#{start_time.to_sql}'
      AND log_timestamp <= '#{end_time.to_sql}'
      ORDER BY log_timestamp
    SQL
    WIKK::SQL.connect(@mysql_conf) do |sql|
      dist_sites = {}
      if links
        # Get the active line names
        sql.each_hash(link_query) do |row|
          dist_sites[row['site_name']] = row['site_name']
        end
      end

      # Get the customer site names associate with each distribution site
      sql.each_hash(dist_query) do |row|
        dist_sites[row['cust_site']] = row['dist_site']
      end

      # Get the log data, for the period, along with the site_names
      result = {}
      sql.each_hash(log_query) do |row|
        result[row['log_timestamp']] ||= {}
        dist_site = dist_sites[row['hostname']]
        next if dist_site.nil?

        result[row['log_timestamp']][dist_site] ||= [ 0, 0 ]
        result[row['log_timestamp']][dist_site][0] += row['bytes_in']
        result[row['log_timestamp']][dist_site][1] += row['bytes_out']
      end

      result.each do |timestamp, dist_records|
        dist_records.each do |dist_site, traffic|
          row = {
            'log_timestamp' => timestamp,
            'site' => dist_site,
            'b_in' => traffic[0] / (1024 * 1024.0),
            'b_out' => traffic[1] / (1024 * 1024.0),
            'total' => (traffic[0] + traffic[1]) / (1024 * 1024.0)
          }
          yield row
        end
      end
    end
  end

  # Retrieve traffic for either a list of towers, or a list of sites.
  # @param dist_host [String] all, if every tower
  # @param links [Boolean] true, if provided with list of towers
  # @param hosts [Array, String] site_names of either the towers or the actual client sites
  # @param start_time [Time] specify from when
  # @param end_time [Time] specify to when
  private def fetch_data(fd, dist_host, links, hosts, start_time, end_time)
    z_max = 35.0 # Default maximum z value for plot graph. Might grow, but wont reduce.
    # WIKK::SQL.connect(@mysql_conf) do |sql|
    begin
      query = if dist_host == 'all' || dist_host == 'dist'
                if links == true || dist_host == 'dist' # summarize by distribution tower.
                  # Query traffic logs, grouping clients by distribution tower
                  # And query traffic log entries by link, adding to previous query
                  <<~SQL
                    ( SELECT log_timestamp,
                            distribution.site_name AS site,
                            sum(bytes_in)/(1024*1024.0) AS b_in,
                            sum(bytes_in + bytes_out)/(1024*1024.0) AS total
                      FROM log_summary, distribution, customer, customer_distribution
                      WHERE log_timestamp >= '#{start_time.to_sql}'
                      AND log_timestamp <= '#{end_time.to_sql}'
                      AND distribution.distribution_id = customer_distribution.distribution_id
                      AND customer_distribution.customer_id = customer.customer_id
                      AND customer.site_name = log_summary.hostname
                      GROUP BY log_timestamp, distribution.site_name
                    )
                    UNION
                    ( SELECT log_timestamp,
                            hostname AS site,
                            bytes_in/(1024*1024.0) AS b_in,
                            (bytes_in + bytes_out)/(1024*1024.0) AS total
                      FROM log_summary
                      WHERE log_timestamp >= '#{start_time.to_sql}'
                      AND log_timestamp <= '#{end_time.to_sql}'
                      AND hostname LIKE 'link%'
                    )
                    ORDER BY log_timestamp, site
                  SQL
                else
                  # Query traffic logs by client site_name.
                  <<~SQL
                    SELECT log_timestamp,
                            hostname AS site,
                            bytes_in/(1024*1024.0) AS b_in,
                            (bytes_in + bytes_out)/(1024*1024.0) AS total
                    FROM log_summary, distribution, customer, customer_distribution
                    WHERE log_timestamp >= '#{start_time.to_sql}'
                    AND log_timestamp <= '#{end_time.to_sql}'
                    AND distribution.distribution_id = customer_distribution.distribution_id
                    AND customer_distribution.customer_id = customer.customer_id
                    AND customer.site_name = log_summary.hostname
                    ORDER BY log_timestamp, site
                  SQL
                end
              else
                # Query traffic logs, for a specific distribution tower's clients
                <<~SQL
                  SELECT log_timestamp,
                          hostname as site,
                          bytes_in/(1024*1024.0) AS b_in,
                          (bytes_in + bytes_out)/(1024*1024.0) AS total
                  FROM log_summary, distribution, customer, customer_distribution
                  WHERE log_timestamp >= '#{start_time.to_sql}'
                  AND log_timestamp <= '#{end_time.to_sql}'
                  AND distribution.site_name = '#{dist_host}'
                  AND distribution.distribution_id = customer_distribution.distribution_id
                  AND customer_distribution.customer_id = customer.customer_id
                  AND customer.site_name = log_summary.hostname
                  ORDER BY log_timestamp,site
                SQL
              end

      # Set up references, by site_name, using a hash to the array of hosts
      hostmap = {}
      hosts.each_with_index do |h, i|
        hostmap[h] = i + 1
      end

      # Graph Title
      fd.print "\#Clients connected to #{dist_host}\n\#datetime\t#{hosts.join("\t")}\t#{hosts.join("\t")}\n"
      fd.print "#{(start_time - 1).strftime('%Y-%m-%d %H:%M:%S')}"

      # first line has 0.0 entries.
      (1..hosts.length).each { |_h| fd.print "\t0.0\t0.0" }
      fd.print "\n"

      line = Array.new(hosts.length * 2 + 1, '-') # init to no data. '-' indicates no data, and gets overwriten if we get data
      total_in = total_in_out = 0.0 # Totals for this time stamp
      fetch_dist_data(dist_host, links, start_time, end_time) do |row|
        # sql.each_hash(query) do |row| # Process each traffic log row returned from the query above.
        next if row['site'] == 'TERMINATED'
        raise "Unexpected host: #{row['site']} not in #{hosts.join(',')}" if hostmap[row['site']].nil?

        if line[0] == '-' # Starting a new line
          line[0] = row['log_timestamp']  # Record the timestamp, so we know when we get a new one
          total_in = total_in_out = 0.0 # Totals for this time stamp
        elsif line[0] != row['log_timestamp'] # Got a new timestamp, so dump stats to plot file, and reset.
          print_hosts_line(fd, line, total_in, total_in_out) # Output last record for gnuplot to use later on.
          line.collect! { '-' } # Reset to no data. '-' indicates no data, and gets overwriten if we get data
          line[0] = row['log_timestamp'] # Record the timestamp, so we know when we get a new one
          total_in = total_in_out = 0.0 # Reset Total for this time stamp
        end
        # Processing log entries for this time stamp.
        line[hostmap[row['site']]] = row['b_in'] # in
        line[hostmap[row['site']] + hosts.length] = row['total'] # in + out
        next unless row['site'] !~ /^link/ # Not traffic summarized by link, so add to in/out totals for this timestamp.

        total_in += row['b_in'].to_f
        total_in_out += row['total'].to_f
        z_max = total_in_out if total_in_out > z_max # Recording the maximum value seen for sizing plot scale
      end
      print_hosts_line(fd, line, total_in, total_in_out) if line[0] != '-' # Catch all, for the last line.
    end
    return z_max # Return maximum z value seen, so plot scale can be set (mostly ignore this now)
  end
end
