class Graph_Ports < Graph_Parent
  def initialize(host, starttime, endtime)
    super
    @host = host
    @start = starttime
    @end = endtime
    @images = ''
    genfilename
    run_neato
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

  def gen_dot
    target = ip_address_to_subnet
    ports = {}
    total = 0
    File.open( @filename ).each do |line|
      next unless line[0, 1] != '#'

      tokens = line.chomp.strip.split(/\t/)
      next unless tokens[7] == target && !ignore?(tokens[8]) && (t = Time.parse(tokens[0])) >= @start && t <= @end

      total += (tokens[13].to_i + tokens[14].to_i )
      ports[tokens[10]] = if ports[tokens[10]].nil? # no existing entry for this port
                            tokens[13].to_i + tokens[14].to_i
                          else
                            (ports[tokens[10]] + tokens[13].to_i + tokens[14].to_i )
                          end
    end

    g = <<~GNUPLOT
      graph g {
          ranksep=1.2;
         ratio=auto;
         root="#{target}"
         overlap=scale;
        "#{target}" [ shape=ellipse, style=filled, fillcolor=blue ];
    GNUPLOT
    i = 1
    ports.sort.each do |p, value|
      g << "\"#{i}\" [ label=\"#{p}\", style=filled, fillcolor=#{port_color(p)}];\n"
      g << "\"#{target}\" -- \"#{i}\" [style=\"setlinewidth(#{(value.to_f / total.to_f) * 8.0})\" len=1.0];\n"
      i += 1
    end

    g << "}\n"

    return g
  end

  def run_neato
    t = Time.now
    image_filename = "#{WWW_DIR}/#{NETSTAT_DIR}/tmp/#{@host}_ports.png"
    temp_filename_base = "#{TMP_DIR}/#{NETSTAT_DIR}/#{@host}_n#{t.tv_sec}#{t.tv_usec}"
    temp_filename_dot = temp_filename_base + '.dot'
    TmpFileMod::TmpFile.open(temp_filename_dot, 'w') do |plot_fd|
      plot_fd.print gen_dot
      plot_fd.flush
      TmpFileMod::TmpFile.exec(TWOPI, '-Tpng', '-o', image_filename, temp_filename_dot)
    end

    @images = "<p><img src=\"/#{NETSTAT_DIR}/tmp/#{@host}_ports.png?start_time=#{@start.xmlschema}&end_time=#{@end.xmlschema}\" width=\"90%\"></p>\n"
  end

  private def port_color(port)
    case port.to_i
    when 80, 443 then 'green' # Wed
    when 25, 993, 143, 220, 585, 109, 110, 473, 995 then 'yellow' # Mail
    when 1194, 1723, 500 then 'gold'
    when 22, 23, 2022 then 'pink' # ssh
    when 6881..6999 then 'red' # BT
    when 53, 123 then 'aquamarine' # Ntp, DNS
    when 21, 20 then 'magenta' # ftp
    else 'grey'
    end
  end
end
