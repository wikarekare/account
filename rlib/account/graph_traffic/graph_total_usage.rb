class Graph_Total_Usage < Graph_Parent
  attr_reader :start_when, :stop_when, :title

  def initialize(mysql_conf, title = nil, start_when = nil, stop_when = nil)
    super
    @mysql_conf = mysql_conf
    t = Time.now
    @images = ''
    @title = title
    # default to the start of the billing period, which is the start of the 23rd of the previous month.
    @start_when = start_when.nil? ? t.start_of_billing : start_when
    # default to the end of the billing period, which is the start of the 23rd of this month.
    @stop_when = stop_when.nil? ? @start_when.end_of_billing : stop_when
    @image_file = "wikkpT3D_#{@start_when.year}_#{@start_when.month}_#{@start_when.day}.png"

    temp_filename_base = "#{TMP_DIR}/#{NETSTAT_DIR}/totals_#{t.tv_sec}#{t.tv_usec}"
    @tmp_stats_file = temp_filename_base + '.txt'
    @gplot_filename = temp_filename_base + '.plot'
    TmpFileMod::TmpFile.open(@gplot_filename, 'w') do |plot_fd|
      # plot_fd.no_unlink
      TmpFileMod::TmpFile.open(@tmp_stats_file, 'w') do |txt_fd|
        # txt_fd.no_unlink
        fetch_data(txt_fd)
        gen_graph_instructions(plot_fd)
        plot_fd.flush
        txt_fd.flush
        TmpFileMod::TmpFile.exec(GNUPLOT, @gplot_filename)
      end
    end

    @images = "<p><img src=\"/#{NETSTAT_DIR}/tmp/#{@image_file}?start_time=#{@start_when.xmlschema}&end_time=#{@stop_when.xmlschema}\"></p>\n"
  end

  private def fetch_data(txt_fd)
    WIKK::SQL.connect(@mysql_conf) do |sql|
      query = <<~SQL
        SELECT hostname, sum(bytes_in)/1073741824.0 as b_in, sum(bytes_out)/1073741824.0 AS b_out
        FROM log_summary
        WHERE log_timestamp >= '#{start_time.to_sql}'
        AND log_timestamp <= '#{end_time.to_sql}'
        GROUP BY hostname
        ORDER BY hostname
      SQL

      @sum_in = [ 'In',   0.0 ]
      @sum_out = [ 'Out', 0.0 ]
      @key_by_index = [ 'Direction', 'Total' ]

      (1..NLINKS).each do |i| # 0.0's are there so we have the right number of entries before we append to the array
        @sum_in << 0.0
        @sum_out << 0.0
        @key_by_index << "Link#{i}"
      end

      sql.each_hash(query) do |row|
        case row['hostname']
        when 'link1'
          @sum_in[2] = row['b_in'].to_f
          @sum_out[2] = row['b_out'].to_f
          # Also want Total = Link1 + Link2 + Link3 + Link4
          @sum_in[1] += row['b_in'].to_f
          @sum_out[1] += row['b_out'].to_f
        when 'link2'
          @sum_in[3] = row['b_in'].to_f
          @sum_out[3] = row['b_out'].to_f
          # Also want Total = Link1 + Link2 + Link3 + Link4
          @sum_in[1] += row['b_in'].to_f
          @sum_out[1] += row['b_out'].to_f
        when 'link3'
          @sum_in[4] = row['b_in'].to_f
          @sum_out[4] = row['b_out'].to_f
          # Also want Total = Link1 + Link2 + Link3 + Link4
          @sum_in[1] += row['b_in'].to_f
          @sum_out[1] += row['b_out'].to_f
        when 'link4'
          @sum_in[5] = row['b_in'].to_f
          @sum_out[5] = row['b_out'].to_f
          # Also want Total = Link1 + Link2 + Link3 + Link4
          @sum_in[1] += row['b_in'].to_f
          @sum_out[1] += row['b_out'].to_f
        when 'link5'
          @sum_in[6] = row['b_in'].to_f
          @sum_out[6] = row['b_out'].to_f
          # Also want Total = Link1 + Link2 + Link3 + Link4 + Link5
          @sum_in[1] += row['b_in'].to_f
          @sum_out[1] += row['b_out'].to_f
        when 'link6'
          @sum_in[7] = row['b_in'].to_f
          @sum_out[7] = row['b_out'].to_f
          # Also want Total = Link1 + Link2 + Link3 + Link4 + Link5 + Link6
          @sum_in[1] += row['b_in'].to_f
          @sum_out[1] += row['b_out'].to_f
        when 'link7'
          @sum_in[8] = row['b_in'].to_f
          @sum_out[8] = row['b_out'].to_f
          # Also want Total = Link1 + Link2 + Link3 + Link4 + Link5 + Link6 + Link7
          @sum_in[1] += row['b_in'].to_f
          @sum_out[1] += row['b_out'].to_f
        else # All other hosts append to the gbytes in, out and key arrays
          @key_by_index << row['hostname']
          @sum_in << row['b_in'].to_f
          @sum_out << row['b_out'].to_f
        end
      end
    end

    print_header txt_fd
    print_key txt_fd
    print_line txt_fd
  end

  private def print_header(fd_out)
    fd_out.puts "#[Accumulated GBytes This Month (#{@start_when.strftime('%Y-%m-%d %H:%M:%S')} to #{@stop_when.strftime('%Y-%m-%d %H:%M:%S')})]\n"
  end

  private def print_key(fd_out)
    fd_out.puts "#{@key_by_index.join("\t")}"
  end

  private def print_line(fd_out)
    fd_out.puts "#{@sum_in.join("\t")}"
    fd_out.puts "#{@sum_out.join("\t")}"
  end

  private def gen_graph_instructions(fd)
    fd.print <<~EOF
      set output "#{WWW_DIR}/#{NETSTAT_DIR}/tmp/#{@image_file}"
      set terminal png enhanced truecolor font "Monoco,12" size 1224,757
      set boxwidth 0.75 absolute
      set style fill  solid 1.00 border -1
      set style rectangle back fc lt -3 fillstyle  solid 1.00 border -1
      set key outside right top vertical Left reverse invert enhanced samplen 4 spacing 1 width 0 height 0 autotitles columnhead box linetype -2 linewidth 1.000
      set style histogram columnstacked title offset 0,0,0
      set datafile missing '-'
      set style data histograms
      set xtics border out nomirror rotate by 0-90  offset character 0,0-3, 0 autofreq
      set grid ytics mytics linetype 1 linetype 0 linewidth 1
      set ytics 2.5
      set yrange [0:*]
      set mytics 5
    EOF
    if @title
      fd.print "set title \"#{title} (#{Time.now.to_sql})\" offset character 0, 0, 0 font \"\" norotate\n"
    elsif @start_when
      if @stop_when
        fd.print "set title \"Monthly Usage per site #{@start_when.strftime('%Y-%m-%d')} to #{@stop_when.strftime('%Y-%m-%d')} (#{Time.now.to_sql})\"  offset character 0, 0, 0 font \"\" norotate\n"
      else
        fd.print "set title \"Monthly Usage per site starting at #{@start_when.strftime('%Y-%m-%d')} (#{Time.now.to_sql})\"  offset character 0, 0, 0 font \"\" norotate\n"
      end
    else
      fd.print "set title \"Monthly Usage per site (#{Time.now.to_sql})\"  offset character 0, 0, 0 font \"\" norotate\n"
    end
    fd.print <<~EOF
      set xlabel "Site"  offset character 0, 0, 0 font "" textcolor lt -1 norotate
      set ylabel "Giga Bytes"  offset character 0, 0, 0 font "" textcolor lt -1 rotate by 90
      set colorbox vertical origin screen 0.9, 0.2, 0 size screen 0.05, 0.6, 0 bdefault
    EOF
    print_plot_cmd(fd)
  end

  private def print_plot_cmd(fd)
    fd.print "plot '#{@tmp_stats_file}' "
    (@key_by_index.length - 2).times { |x| fd.print " using #{x + 2} ti col, '' " }
    fd.print " using #{@key_by_index.length}:key(1) ti col\n"
  end
end
