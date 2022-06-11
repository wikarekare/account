# With data from the log_summary table, graph usage with  GnuPlot
class Graph_Host_Usage < Graph_Parent
  attr_reader :start_when, :stop_when, :host

  def initialize(mysql_conf, host = nil, start_when = nil, stop_when = nil)
    super
    @mysql_conf = mysql_conf
    t = Time.now
    @images = ''
    @host = host
    # default to the start of the billing period, which is the start of the 23rd of the previous month.
    @start_when = start_when.nil? ? t.start_of_billing : start_when
    # default to the end of the billing period, which is the start of the 23rd of this month.
    @stop_when = stop_when.nil? ? @start_when.end_of_billing : stop_when
    @image_file = "wikkp_#{@host}_#{@start_when.year}_#{@start_when.month}_#{@start_when.day}.png"

    temp_filename_base = "#{TMP_DIR}/#{NETSTAT_DIR}/totals_#{t.tv_sec}#{t.tv_usec}"
    @tmp_stats_file = temp_filename_base + '.txt'
    @gplot_filename = temp_filename_base + '.plot'
    TmpFile.open(@gplot_filename, 'w') do |plot_fd|
      # plot_fd.no_unlink
      TmpFile.open(@tmp_stats_file, 'w') do |txt_fd|
        # txt_fd.no_unlink
        fetch_data(txt_fd)
        gen_graph_instructions(plot_fd)
        plot_fd.flush
        txt_fd.flush
        TmpFile.exec(GNUPLOT, @gplot_filename)
      end
    end

    @images = "<p><img src=\"/#{NETSTAT_DIR}/tmp/#{@image_file}?start_time=#{@start_when.xmlschema}&end_time=#{@stop_when.xmlschema}\"></p>\n"
  end

  private def print_header(fd_out)
    fd_out.puts "#[Accumulated GBytes for #{@host} (#{@start_when.strftime('%Y-%m-%d %H:%M:%S')} to #{@stop_when.strftime('%Y-%m-%d %H:%M:%S')})]\n"
  end

  private def print_key(fd_out)
    fd_out.puts "#datetime\tin\tout\ttotal\n"
  end

  private def fetch_data(txt_fd)
    WIKK::SQL.connect(@mysql_conf) do |my|
      query = <<~SQL
        SELECT  log_timestamp, bytes_in/1073741824.0 AS b_in, bytes_out/1073741824.0 AS b_out
        FROM log_summary
        WHERE log_timestamp >= '#{@start_when.strftime('%Y-%m-%d %H:%M:%S')}'
        AND log_timestamp <= '#{@stop_when.strftime('%Y-%m-%d %H:%M:%S')}'
        AND hostname = '#{@host}'
        ORDER BY log_timestamp
      SQL

      print_header txt_fd
      print_key txt_fd
      in_sum = 0.0
      out_sum = 0.0

      my.each_hash(query) do |row|
        in_sum += row['b_in'].to_f
        out_sum += row['b_out'].to_f
        txt_fd.puts "#{row['log_timestamp']}\t#{in_sum}\t#{out_sum}\t#{in_sum + out_sum}\n"
      end
    end
  end

  private def gen_graph_instructions(fd)
    fd.print <<~EOF
      set output "#{WWW_DIR}/#{NETSTAT_DIR}/tmp/#{@image_file}"
      datafile = '#{@tmp_stats_file}'
      set datafile separator '\\t'
      set terminal png enhanced truecolor font "Monoco,12" size 800,495
      set key invert box top left reverse Left
      set xtics nomirror
      set ytics nomirror
      set border 3
      set datafile missing '-'
      set yrange [0:*]
      set style data linespoints
      set xdata time
      set timefmt "%Y-%m-%d %H:%M:%S"
      set format x "%H:%M\\n%m/%d"
      set title "Usage for #{@host} #{@start_when.strftime('%Y-%m-%d')} to #{@stop_when.strftime('%Y-%m-%d')} (#{Time.now.to_sql})"  offset character 0, 0, 0 font "" norotate
      set xlabel "Date"  offset character 0, 0, 0 font "" textcolor lt -1 norotate
      set ylabel "Giga Bytes"  offset character 0, 0, 0 font "" textcolor lt -1 rotate by 90
      plot datafile using 1:2 title 'in' lw 2 lc rgb "red",  datafile using 1:3 title 'out' pt 7 ps 0.5 lw 1 lc rgb "forest-green",  datafile using 1:4 title 'total' pt 1 lw 1 lc rgb "blue"
    EOF
  end
end
