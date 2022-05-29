require 'open3'
require 'socket'
require_relative '../../ipv4.rb'

class Graph_flow_Host_Hist_trim < Graph_Parent
  NETWORK_MASK_BITS = 27
  GBYTES = 1073741824.0
  MAX_HOST_COUNT = 49

  def initialize(site_name, starttime, endtime, debug = false)
    @debug = debug
    @site_name = site_name
    @site_ip = IPSocket.getaddress(site_name)        # Change to site_name, as this becomes the site local network.
    @ip_net = IPV4.new(@site_ip, IPV4.maskbits_to_i(NETWORK_MASK_BITS))
    @start_time = starttime
    @end_time = endtime

    @images = ''

    collect_data
    prepare_data
    gen_gnu_output
  end

  private def gen_gnu_output
    @image_filename = "#{WWW_DIR}/#{NETSTAT_DIR}/tmp/#{@site_name}_hosts2.png"
    system "rm -f #{@image_filename}"
    t = Time.now
    temp_filename_base = "#{TMP_DIR}/#{NETSTAT_DIR}/#{@site_name}_h#{t.tv_sec}#{t.tv_usec}"
    @temp_filename_gnuplot = temp_filename_base + '.plot'
    @temp_filename_dat = temp_filename_base + '.dat'
    TmpFile.open(@temp_filename_gnuplot, 'w') do |fd_plot|
      # fd_plot.no_unlink  if @debug #Comment out if not debugging
      TmpFile.open(@temp_filename_dat, 'w') do |fd_dat|
        # fd_dat.no_unlink  if @debug  #Comment out if not debugging
        print_gnuplot_dataheader fd_dat
        print_gnuplot_datakey fd_dat
        print_gnu_dataline fd_dat
        fd_dat.flush

        print_gnuplot_cmds fd_plot
        fd_plot.flush

        @images = "<p><img src=\"/#{NETSTAT_DIR}/tmp/#{@site_name}_hosts2.png?start_time=#{@start_time.xmlschema}&end_time=#{@end_time.xmlschema}\" width=\"90%\"></p>\n"
        TmpFile.exec(GNUPLOT, @temp_filename_gnuplot)
      end
    end
  end

  private def print_gnuplot_dataheader(fd_out)
    fd_out.puts "#[GBytes by Host (#{@start_time.to_sql} to #{@end_time.to_sql})]\n"
  end

  private def print_gnuplot_datakey(fd_out)
    fd_out.puts "#{@key_by_index.join("\t")}"
  end

  private def print_gnu_dataline(fd_out)
    fd_out.puts "#{@sum_in.join("\t")}"
    fd_out.puts "#{@sum_out.join("\t")}"
  end

  private def print_gnuplot_cmds(fd_out)
    fd_out.print <<~EOF
      set terminal pngcairo  transparent enhanced font "Monoco,12" fontscale 1.0 size 1500, 750
      set output '#{@image_filename}'
      #set boxwidth 0.75 absolute
      set style fill  solid 1.00 border -1
      set style rectangle back fc lt -3 fillstyle  solid 1.00 border -1
      set key right top vertical Left reverse invert enhanced samplen 4 spacing 1 width 0 height 0 autotitles columnhead box linetype -2 linewidth 1.000
      set style histogram columnstacked title offset 0,0,0
      set datafile missing '-'
      set style data histograms
      #set bmargin at screen 0.1
      set xtics border in scale 0,0 nomirror rotate by -45  offset character 0, 0, 0 autojustify
      set xtics  norangelimit font ",14"
      set xtics   ()
      set format y "%.2f"
      set grid ytics mytics linetype 1 linetype 0 linewidth 1
      set yrange [0:*]
      set ytics nomirror
    EOF
    if @start_time.nil?
      fd_out.print "set title \"Top 50 Hosts Usage for #{@site_name} at (#{Time.new})\"  offset character 0, 0, 0 font \"\" norotate\n"
    elsif @end_time != nil
      fd_out.print "set title \"Top 50 Hosts Usage for #{@site_name} #{@start_time.strftime('%Y-%m-%d')} to #{@end_time.strftime('%Y-%m-%d')} (#{Time.new})\"  offset character 0, 0, 0 font \"\" norotate\n"
    else
      fd_out.print "set title \"Top 50 Hosts Usage for #{@site_name} starting at #{@start.strftime('%Y-%m-%d')} (#{Time.new})\"  offset character 0, 0, 0 font \"\" norotate\n"
    end
    fd_out.print <<~EOF
      set xlabel "Hosts"  offset character 0, 0, 0 font "" textcolor lt -1 norotate
      set ylabel "Giga Bytes"  offset character 0, 0, 0 font "" textcolor lt -1 rotate by 90
      set colorbox vertical origin screen 0.9, 0.2, 0 size screen 0.05, 0.6, 0 bdefault
    EOF

    fd_out.print "plot '#{@temp_filename_dat}' "
    (@key_by_index.length - 2).times { |x| fd_out.print " using #{x + 2} ti col, '' " }
    fd_out.print " using #{@key_by_index.length}:key(1) ti col\n"
  end

  private def collect_data
    @host_traffic = {}
    (@start_time.to_i..@end_time.to_i).step(86400) do |d|
      t = Time.at(d)
      filename = "#{FLOW_LOG_DIR}/log/#{t.year}/#{t.year}-#{'%02d' % t.month}/#{t.year}-#{'%02d' % t.month}-#{'%02d' % t.mday}/*" # All files for that day
      cmd = "#{FLOW_CAT} #{filename} | #{FLOW_NFILTER} -F network -v NETWORK=#{@ip_net} | #{FLOW_PRINT} -f 25"
      puts cmd if @debug
      stdout, _stderr, _status = Open3.capture3(cmd)
      stdout.each_line do |line|
        if line[0, 1] != '#'
          parse_flow_print_25_line(line)
        end
      end
    end
  end

  # flow-cat #{@filename} | flow-nfilter -F network -v NETWORK=#{@network}| flow-print -f 25
  # 0                      1                       2     3              4     5   6                7    8  9   10   11   12     13    14
  # Start	               End	                   Sif	SrcIPaddress	  SrcP	DIf	DstIPaddress	  DstP	P	 Fl	tos	Pkts	Octets	saa	  daa
  # 2013-12-15 16:19:54.032	2013-12-15 16:19:54.262	0	  10.4.2.208     	60334	0	  210.55.204.219 	443	  6	 6	0	  2	   104	    1270	3400

  private def parse_flow_print_25_line(line)
    fields = line.chomp.split("\t")
    fields.map!(&:strip)
    # Convert to time, so we can time bound a query
    # Note, interval time can start before a file timestamp and intervals aren't fixed length.
    fields_start_time = Time.parse(fields[0])
    fields_end_time = Time.parse(fields[1])

    if @end_time > fields_start_time && @start_time < fields_end_time
      # Then the sample (or part of it) is within the wanted time bounds.
      remote_ip, direction = remote_address?(fields[3], fields[6])
      if @host_traffic[remote_ip].nil?
        @host_traffic[remote_ip] = direction ? [ fields[12].to_i, 0 ] : [ 0, fields[12].to_i ]
      elsif ! ignore?(remote_ip)
        if direction
          @host_traffic[remote_ip][0] += fields[12].to_i
        else
          @host_traffic[remote_ip][1] += fields[12].to_i
        end
      end
    end
  end

  private def remote_address?(src_ip, dest_ip)
    if IPV4.new(src_ip, IPV4.maskbits_to_i(NETWORK_MASK_BITS)).ip_address == @ip_net.ip_address
      return dest_ip, true # Outbound
    else
      return src_ip, false # inbound
    end
  end

  private def prepare_data
    @key_by_index = [ 'Direction' ]
    @sum_in = [ 'In' ]
    @sum_out = [ 'Out' ]

    sorted_host_traffic = @host_traffic.sort { |a, b| (b[1][0] + b[1][1]) <=> (a[1][0] + a[1][1]) }
    count = 0
    sorted_host_traffic.each do |k, v|
      count += 1
      if count == MAX_HOST_COUNT # The byte count for all the rest of the hosts, beyond this one.
        @key_by_index << 'theRest'
        @sum_out << v[0].to_f / GBYTES
        @sum_in << v[1].to_f / GBYTES
      elsif count > MAX_HOST_COUNT # The byte count for all the rest of the hosts, beyond this one.
        @sum_out[-1] += v[0].to_f / GBYTES
        @sum_in[-1] += v[1].to_f / GBYTES
      else # The byte count for the hosts upto MAX_HOST_COUNT.
        @key_by_index << k
        @sum_out << v[0].to_f / GBYTES
        @sum_in << v[1].to_f / GBYTES
      end
    end
  end

  def self.debug(site_name, start_time, end_time)
    gfh = Graph_flow_Host_Hist_trim.new(site_name, start_time, end_time, true) # True indicates debug on.
    puts "images=#{gfh.images}"
  end
end
