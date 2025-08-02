class Graph_Ports_Hist < Graph_Parent
  def initialize(host, starttime, endtime)
    super
    @host = host
    @start = starttime
    @end = endtime
    @images = ''
    genfilename
    gen_gnu_output
  end

  def genfilename
    # test case, ignore start and end times
    fileDateStamp = Time.local(@start.year, @start.month, @start.mday, (@start.hour / 4).to_i * 4, 0, 0)
    @filename = "#{NTM_LOG_DIR}/wikk.#{fileDateStamp.strftime('%Y-%m-%d_%H:00:00')}.fdf.out"
  end

  def ip_address_to_subnet
    # special case for tracking admin2 and admin1
    return IPSocket.getaddress('admin2') if @host == 'admin2' || @host == 'admin2-net'
    return IPSocket.getaddress('admin1-net') if @host == 'admin1' || @host == 'admin1-net'

    # return IPSocket.getaddress('wikk003-net') if ( @host == 'wikk003'|| @host == 'wikk003-net' ) && @start < Time.parse('2015-02-03 21:40:00')
    return IPSocket.getaddress(@host)
  end

  def gen_gnu_output
    @image_filename = "#{WWW_DIR}/#{NETSTAT_DIR}/tmp/#{@host}_ports2.png"
    system "rm #{@image_filename}"
    t = Time.now
    temp_filename_base = "#{TMP_DIR}/#{NETSTAT_DIR}/#{@host}_n#{t.tv_sec}#{t.tv_usec}"
    @temp_filename_gnuplot = temp_filename_base + '.plot'
    @temp_filename_dat = temp_filename_base + '.dat'
    TmpFileMod::TmpFile.open(@temp_filename_gnuplot, 'w') do |fd_plot|
      # fd_plot.no_unlink  #Comment out if not debugging
      TmpFileMod::TmpFile.open(@temp_filename_dat, 'w') do |fd_dat|
        # fd_dat.no_unlink  #Comment out if not debugging
        gen_gnu_plot_datafile
        print_gnuplot_dataheader fd_dat
        print_gnuplot_datakey fd_dat
        print_gnu_dataline fd_dat
        fd_dat.flush

        print_gnuplot_cmds fd_plot
        fd_plot.flush

        @images = "<p><img src=\"/#{NETSTAT_DIR}/tmp/#{@host}_ports2.png?start_time=#{@start.xmlschema}&end_time=#{@end.xmlschema}\" width=\"90%\"></p>\n"
        TmpFileMod::TmpFile.exec(GNUPLOT, @temp_filename_gnuplot)
      end
    end
  end

  def print_gnuplot_dataheader(fd_out)
    fd_out.puts "#[GBytes by Port (#{@start.strftime('%Y-%m-%d %H:%M:%S')} to #{@end.strftime('%Y-%m-%d %H:%M:%S')})]\n"
  end

  def print_gnuplot_datakey(fd_out)
    fd_out.puts "#{@key_by_index.join("\t")}"
  end

  def print_gnu_dataline(fd_out)
    fd_out.puts "#{@sum_in.join("\t")}"
    fd_out.puts "#{@sum_out.join("\t")}"
  end

  def gen_gnu_plot_datafile
    target = ip_address_to_subnet
    ports = {}
    File.open( @filename ).each do |line|
      next unless line[0, 1] != '#'

      tokens = line.chomp.strip.split("\t")
      if tokens[7] == target && !ignore?(tokens[8]) && (t = Time.parse(tokens[0])) >= @start && t <= @end
        if ports[tokens[10]].nil? # no existing entry for this port
          ports[tokens[10]] =  [  tokens[14].to_i, tokens[13].to_i, tokens[6].to_i ] # As array of in, out
        else
          ports[tokens[10]][1] += tokens[13].to_i # in
          ports[tokens[10]][0] += tokens[14].to_i # out
          ports[tokens[10]][2] = tokens[6].to_i # protocol
        end
      end
    end
    @key_by_index = [ 'Direction' ]
    @sum_in = [ 'In' ]
    @sum_out = [ 'Out' ]

    sp = ports.sort_by { |_k, v| v[0] + v[1] }
    count = 0
    sp.reverse.each do |k, v|
      count += 1
      break if count == 50 # just plot top 100 ports

      @key_by_index << port_name(k, v[2])       # Replace port numbers with names.
      @sum_in << v[0].to_f / 1073741824.0   # Record GBytes
      @sum_out << v[1].to_f / 1073741824.0  # Record GBytes
    end
    if @key_by_index.length == 1
      raise "gen_gnu_plot_datafile: No data in #{@filename} for #{@start} #{@end}"
    end
  end

  def print_gnuplot_cmds(fd_out)
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
      #set xtics border out nomirror rotate by 0-90  offset character 0,0-3, 0 autofreq
      set xtics border in scale 0,0 nomirror rotate by -45  offset character 0, 0, 0 autojustify
      set xtics  norangelimit font ",14"
      set xtics   ()
      set format y "%.2f"
      set grid ytics mytics linetype 1 linetype 0 linewidth 1
      set yrange [0:*]
      set ytics nomirror
    EOF
    if @start
      if @stop
        fd_out.print "set title \"Top 50 Ports: Usage for #{@host} #{@start.strftime('%Y-%m-%d')} to #{@stop.strftime('%Y-%m-%d')} (#{Time.new})\"  offset character 0, 0, 0 font \"\" norotate\n"
      else
        fd_out.print "set title \"Top 50 Ports: Usage for #{@host} starting at #{@start.strftime('%Y-%m-%d')} (#{Time.new})\"  offset character 0, 0, 0 font \"\" norotate\n"
      end
    else
      fd_out.print "set title \"Top 50 Ports: Usage for #{@host} (#{Time.new})\"  offset character 0, 0, 0 font \"\" norotate\n"
    end
    fd_out.print <<~EOF
      set xlabel "Ports"  offset character 0, 0, 0 font "" textcolor lt -1 norotate
      set ylabel "Giga Bytes"  offset character 0, 0, 0 font "" textcolor lt -1 rotate by 90
      set colorbox vertical origin screen 0.9, 0.2, 0 size screen 0.05, 0.6, 0 bdefault
    EOF

    fd_out.print "plot '#{@temp_filename_dat}' "
    (@key_by_index.length - 2).times { |x| fd_out.print " using #{x + 2} ti col, '' " }
    fd_out.print " using #{@key_by_index.length}:key(1) ti col\n"
  end

  private def port_name(port, protocol)
    case protocol.to_i
    when 47 then "GRE-#{port}"
    when 1 then "ICMP-#{port}"
    when 6, 17
      case port.to_i
      when 80 then 'http'
      when 443 then 'https' # Web
      when 25 then 'smtp'
      when 993 then 'imap-ssl'
      when 143 then 'imap'
      when 220 then 'imap3'
      when 585 then 'imap4-ssl'
      when 109 then 'pop2'
      when 110 then 'pop3'
      when 473 then 'hybrid-pop'
      when 995 then 'spop' # Mail
      when 1723 then 'pptp'
      when 500 then 'isakmp'
      when 465 then 'TLS-snmp'
      when 636 then 'sldap'
      when 22 then 'ssh'
      when 23 then 'telnet'
      when 6881..6999 then "BT-#{port}" # BT
      when 53 then 'DNS'
      when 123 then 'ntp' # Ntp, DNS
      when 115 then 'sftp'
      when 21 then 'ftp'
      when 20 then 'ftp-data' # ftp
      when 161 then 'snmp'
      when 162 then 'snmptrap'
      when 514 then 'syslog'
      # when 0...1024 then "#{port}"
      else "#{port}"
      end
    else
      "#{protocol}-#{port}"
    end
  end
end
