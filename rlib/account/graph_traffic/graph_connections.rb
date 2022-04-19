class Graph_Connections < Graph_Parent

  def initialize(host, starttime, endtime)
    @host = host
    @start = starttime
    @end = endtime
    @images = ""
    genfilename
    run_neato
  end

  def genfilename
        #test case, ignore start and end times
        fileDateStamp = Time.local(@start.year, @start.month, @start.mday, (@start.hour/4).to_i*4, 0, 0) 
	@filename = "#{NTM_LOG_DIR}/wikk.#{fileDateStamp.strftime("%Y-%m-%d_%H:00:00")}.fdf.out"
  end

  def ip_address_to_subnet
    #special case for tracking admin2 and admin1
    return IPSocket.getaddress('admin2') if(@host == 'admin2' || @host == 'admin2-net' ) 
    return IPSocket.getaddress('admin1-net') if( @host == 'admin1' || @host == 'admin1-net')
    ##return IPSocket.getaddress('wikk003') if ( @host == 'wikk003'|| @host == 'wikk003-net' ) && @start < Time.parse('2015-02-03 21:40:00')
    return IPSocket.getaddress(@host)
  end

  def gen_dot
    target = ip_address_to_subnet
    hosts = {}
    total = 0
    File.open( @filename ).each do |line|
      if line[0,1] != '#'
        tokens = line.chomp.strip.split(/\t/)
        if tokens[7] == target && !ignore?(tokens[8]) && (t = Time.parse(tokens[0])) >= @start && t <= @end
          total += (tokens[13].to_i + tokens[14].to_i )
          if(hosts[tokens[8]] == nil) #no existing entry for this host
            hosts[tokens[8]] = { tokens[10] => [(tokens[13].to_i + tokens[14].to_i ), tokens[6]] }
          elsif (h = hosts[tokens[8]][tokens[10]] ) != nil
            hosts[tokens[8]][tokens[10]][0] = (h[0] + tokens[13].to_i + tokens[14].to_i )
          else
            hosts[tokens[8]][tokens[10]] = [(tokens[13].to_i + tokens[14].to_i),  tokens[6]]
          end
        end
      end
    end

    g = <<-EOF
      graph g {
          ranksep=5.2;
         ratio=auto;
         root="#{target}"
        "#{target}" [ shape=ellipse, style=filled, fillcolor=blue ];
EOF
        hosts.sort.each do |h,value|
          g << "\"#{h}\" [ shape=ellipse, style=filled, fillcolor=orange ];\n"
          g << "\"#{target}\" -- \"#{h}\" [len=2.5];\n"
        end

        i = 1
        sp = hosts.sort_by { |k, v| v.max_by { |k2,v2| v2[0].to_i + v2[1].to_i } }
        sp.reverse.each do |h,value|
          value.each do |k,v|
            g << "\"#{i}\" [ label=\"#{k}\", style=filled, fillcolor=#{port_color(k)} ];\n"
            g << "\"#{h}\" -- \"#{i}\" [style=\"setlinewidth(#{(v[0].to_f/total.to_f)*8.0})\" len=1.0 color=\"#{ protocol_color(v[1].to_i) }\"];\n"
            i += 1
          end
        end

      g << "}\n"

     return g
  end

  def run_neato
    t = Time.now
    image_filename = "#{WWW_DIR}/#{NETSTAT_DIR}/tmp/#{@host}_connections.png"
    temp_filename_base = "#{TMP_DIR}/#{NETSTAT_DIR}/#{@host}_n#{t.tv_sec}#{t.tv_usec}"
    temp_filename_dot = temp_filename_base + ".dot"
    File.open(temp_filename_dot, "w") do |plot_fd|
      plot_fd.print gen_dot
      plot_fd.flush
      TmpFile.exec(NEATO, "-Tpng", "-o", image_filename, temp_filename_dot)
    end
    
    @images = "<p><img src=\"/#{NETSTAT_DIR}/tmp/#{@host}_connections.png?start_time=#{@start.xmlschema}&end_time=#{@end.xmlschema}\" width=\"90%\"></p>\n"
  end
  
  private
  def port_color(port)
    case port.to_i
    when 80,443; 'green'
    when 25,993,143,220,585,109,110,473,995; 'yellow'
    when 1194,1723, 500,1194; 'gold'
    when 22,23,2022; 'pink'
    when 6881..6999; 'red'
    when 53,123; 'aquamarine'
    when 21,20; 'magenta'
    else 'grey'
    end
  end

  def protocol_color(protocol)
    case(protocol)
    when 6; 'blue'
    when 17; 'green'
    when 1; 'red'
    when 47; 'magenta'
    else 'black'
    end
  end

end
