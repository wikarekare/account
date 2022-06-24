#!/usr/local/bin/ruby
# take the comment line as the key to the column names
# output the datetime first
# output the total
# output admin1 and admin2
# output the wikkxxx sites
# In all values average over the interval and express in GBytes, not bytes.
require 'rubygems'
require 'wikk_sql'

require 'pp'
# require "parsedate"
require 'time'

require 'wikk_configuration'
RLIB = '/wikk/rlib' unless defined? RLIB
require_relative "#{RLIB}/wikk_conf.rb"

class Preprocess
  FLINK = 5
  NLINKS = 7

  # FREE_PERCENTAGE=0.50        ########################## FREE PERCENTAGE From WIKK.CONF **************

  # 1Mb/s free for 10s interval
  INTERVAL_BYTE_COUNT_100 = 1310720

  # 1GByte = 1073741824
  GBYTE = 1073741824.0

  attr_accessor :start_when, :stop_when, :title

  def initialize
    @start_when = nil
    @stop_when = nil
    @title = nil
    @interval_byte_count = 0 # Free traffic rate, measured in bytes every 10s
  end

  def last23rd
    t = Time.now
    if t.day < 23
      if t.month == 1
        Time.local(t.year - 1, 12, 23)
      else
        Time.local(t.year, t.month - 1, 23)
      end
    else
      Time.local(t.year, t.month, 23)
    end
  end

  def addMonth(t)
    if t.month == 12
      Time.local(t.year + 1, 1, t.day)
    else
      Time.local(t.year, t.month + 1, t.day)
    end
  end

  def go(tmp_stats_file, gplot_filename)
    @tmp_stats_file = tmp_stats_file
    @gplot_filename = gplot_filename
    @tmp_excel_file = @gplot_filename.sub('.png', '_excel.txt')
    @gplot_link_filename = @gplot_filename.sub('.png', '_link.png')
    # puts "# #{@tmp_stats_file}"
    # puts "# #{@gplot_filename}"

    # @start_when = last23rd  if @start_when == nil
    t = Time.now
    @start_when = Time.local(t.year, t.month, 1) if @start_when.nil? # start of the month.
    @stop_when = addMonth(@start_when) if @stop_when.nil?
    sum_giga_bytes = {}
    (1..NLINKS).each do |i| # 0.0's are there so we have the right number of entries before we append to the array
      sum_giga_bytes["Link#{i}"] = [ 0.0, 0.0 ] # [Below Threshold, Above_threshold]
    end

    @mysql_conf = WIKK::Configuration.new(MYSQL_CONF)
    WIKK::SQL.connect(@mysql_conf) do |sql|
      res = sql.query_hash <<~SQL
        SELECT free_rate FROM plan WHERE plan_id = -1
      SQL
      # Free traffic rate, measured in bytes every 10s
      @interval_byte_count = (INTERVAL_BYTE_COUNT_100 * res.first['free_rate'].to_f).round

      # Get the actual values
      query = <<~SQL
        SELECT hostname, sum(bytes_in + bytes_out)/#{GBYTE} AS gbytes
        FROM log_summary
        WHERE log_timestamp >= '#{@start_when.strftime('%Y-%m-%d %H:%M:%S')}'
        AND log_timestamp < '#{@stop_when.strftime('%Y-%m-%d %H:%M:%S')}
        GROUP BY hostname
      SQL
      sql.each_hash(query) do |row|
        row['hostname'].capitalize! if row['hostname'] =~ /^link/
        sum_giga_bytes[row['hostname']] = [ row['gbytes'].to_f, 0.0 ] # Set the actual GB usage
      end

      # Get the values, above the threshold in each interval.
      query2 = <<~SQL
        SELECT hostname, sum(bytes_in + bytes_out - #{@interval_byte_count})/#{GBYTE} AS gbytes
        FROM log_summary
        WHERE log_timestamp >= '#{@start_when.strftime('%Y-%m-%d %H:%M:%S')}'
        AND log_timestamp < '#{@stop_when.strftime('%Y-%m-%d %H:%M:%S')}'
        AND (bytes_in + bytes_out) > #{@interval_byte_count}
        GROUP BY hostname
      SQL
      sql.each_hash(query2) do |row|
        row['hostname'].capitalize! if row['hostname'] =~ /^link/
        sum_giga_bytes[row['hostname']] ||= [ 0.0, 0.0 ]
        sum_giga_bytes[row['hostname']][1] = row['gbytes'].to_f # Set the GB usage above the interval threshold
      end
    end

    @key_by_index = [ 'Hosts' ]
    @sum_free_giga_bytes = [ 'Free_GB' ] # Record actual usage, so we know what we are giving away for free.
    @sum_charged_giga_bytes = [ 'Charged_GB' ]     # Charging for values above the threshold

    sorted = sum_giga_bytes.sort
    sorted.each do |hostname, usage|
      next unless hostname =~ /^Link/

      @key_by_index << hostname
      @sum_charged_giga_bytes << usage[0].round(3)
      @sum_free_giga_bytes << 0.0
    end

    # Then the rest, but ignore the minor traffic from the distribution nodes.
    sorted.each do |hostname, usage|
      next if hostname =~ /^10\..*\.0$/ || hostname =~ /^Link/

      @key_by_index << hostname
      @sum_charged_giga_bytes << usage[1].round(3)
      @sum_free_giga_bytes << (usage[0] - usage[1]).round(3)
    end

    gen_gnuplot_output
    gen_excel_output
    gen_link_output
  end

  def gen_gnuplot_output
    File.open(@tmp_stats_file, 'w') do |fd_out|
      print_header fd_out
      print_key fd_out
      print_charged_gb_line fd_out
      print_gnuplot
      print_gnuplot_links
    end
  end

  def gen_excel_output
    File.open(@tmp_excel_file, 'w') do |fd_out|
      print_header fd_out
      print_key fd_out
      print_charged_gb_line fd_out
      print_free_gb_line fd_out
      print_gnuplot
      print_gnuplot_links
    end
  end

  def gen_link_output
    File.open("#{@tmp_stats_file}.lnk", 'w') do |fd_out|
      print_header fd_out
      print_link_key fd_out
      print_link_line fd_out
      print_gnuplot_links
    end
  end

  def print_gnuplot
    print <<~EOF
      set terminal png enhanced truecolor size 1224,757 font "Monoco,8"
      set style line 1 lt 1 lc rgb "blueviolet"
      set output '#{@gplot_filename}'
      set boxwidth 0.75 absolute
      set style fill  solid 1.00 border -1
      set style rectangle back fc lt -3 fillstyle  solid 1.00 border -1
      set key outside right top vertical Left reverse invert enhanced samplen 4 spacing 1 width 0 height 0 autotitles columnhead box linetype -2 linewidth 1.000
      set style histogram columnstacked title offset 0,0,0
      set datafile missing '-'
      set style data histograms
      set xtics border in scale 0,0 nomirror rotate by -90  autojustify
      set format y "%.1f"
      set grid ytics mytics linetype 1 linetype 0 linewidth 1
      set ytics 20
      set yrange [0:*]
      set mytics 5
    EOF
    if @title
      print "set title \"#{@title} (#{Time.new})\" offset character 0, 0, 0 font \"\" norotate\n"
    elsif @start_when
      if @stop_when
        print "set title \"Monthly Usage per site #{@start_when.strftime('%Y-%m-%d')} to #{@stop_when.strftime('%Y-%m-%d')} (#{Time.new})\"  offset character 0, 0, 0 font \"\" norotate\n"
      else
        print "set title \"Monthly Usage per site starting at #{@start_when.strftime('%Y-%m-%d')} (#{Time.new})\"  offset character 0, 0, 0 font \"\" norotate\n"
      end
    else
      print "set title \"Monthly Usage per site (#{Time.new})\"  offset character 0, 0, 0 font \"\" norotate\n"
    end
    print <<~EOF
      set xlabel ""
      set ylabel "Giga Bytes"  offset character 0, 0, 0 font "" textcolor lt -1 rotate by 90
      set colorbox vertical origin screen 0.9, 0.2, 0 size screen 0.05, 0.6, 0 bdefault
    EOF
    print_plot_cmd
  end

  def print_plot_cmd
    print "plot '#{@tmp_stats_file}' "
    # (@key_by_index.length - 2).times { |x| print " using #{x + 2} ti col, '' " }
    (NLINKS + 2...@key_by_index.length).each { |x| print " using #{x} ti col, '' " }
    print " using #{@key_by_index.length}:key(1) ti col\n"
  end

  def print_header(fd_out)
    fd_out.puts "#[Accumulated GBytes This Month (#{@start_when.strftime('%Y-%m-%d %H:%M:%S')} to #{@stop_when.strftime('%Y-%m-%d %H:%M:%S')})] Line1 is hostnames, Line2 is GBs above threshold, Line3 is actual GBs used\n"
  end

  def print_key(fd_out)
    fd_out.puts "#{@key_by_index.join("\t")}"
  end

  def print_charged_gb_line(fd_out)
    fd_out.puts "#{@sum_charged_giga_bytes.join("\t")}"
  end

  def print_free_gb_line(fd_out)
    fd_out.puts "#{@sum_free_giga_bytes.join("\t")}"
  end

  def print_link_key(fd_out)
    fd_out.print "#{@key_by_index[0]}"
    (FLINK..NLINKS).each do |i|
      fd_out.print "\t#{@key_by_index[i]}"
    end
    fd_out.print "\n"
  end

  def print_link_line(fd_out)
    fd_out.print "#{@sum_charged_giga_bytes[0]}"
    (FLINK..NLINKS).each do |i|
      fd_out.print "\t#{@sum_charged_giga_bytes[i]}"
    end
    fd_out.print "\n"
  end

  def print_gnuplot_links
    print <<~EOF
      reset
      set terminal png enhanced truecolor size 200,1150 font "Monoco,8"
      set style line 1 lt 1 lc rgb "red"
      set output '#{@gplot_link_filename}'
      set boxwidth 0.75 absolute
      set style fill  solid 1.00 border -1
      set style rectangle back fc lt -3 fillstyle  solid 1.00 border -1
      set key off
      set style histogram columnstacked title offset 0,0,0
      set datafile missing '-'
      set style data histograms
      set xtics border in scale 0,0 nomirror rotate by -45  autojustify
      set format y "%.1f"
      set grid ytics mytics linetype 1 linetype 0 linewidth 1
      set ytics 20
      set yrange [0:*]
      set mytics 5
      set xlabel ""
      set ylabel "Giga Bytes"  offset character 0, 0, 0 font "" textcolor lt -1 rotate by 90
      set colorbox vertical origin screen 0.9, 0.2, 0 size screen 0.05, 0.6, 0 bdefault
    EOF
    print_plot_links_cmd
  end

  def print_plot_links_cmd
    print "plot '#{@tmp_stats_file}.lnk' "
    (FLINK...NLINKS).each { |x| print " using #{x - FLINK + 2} ti col, '' " }
    print " using #{NLINKS - FLINK + 2}:key(1) ti col\n"
  end
end

require 'getoptlong'

opts = GetoptLong.new(
  [ '--title',	GetoptLong::REQUIRED_ARGUMENT ],
  [ '--start_when', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--stop_when', GetoptLong::REQUIRED_ARGUMENT ]
)

ppfilter = Preprocess.new

opts.each do |opt, arg|
  case opt
  when '--start_when'
    # the_date = ParseDate::parsedate(arg, false )
    # start_datetime = Time.local(*the_date[0..5])
    start_datetime = Time.parse(arg)
    ppfilter.start_when = start_datetime
  when '--stop_when'
    # the_date = ParseDate::parsedate(arg, false )
    # stop_datetime = Time.local(*the_date[0..5])
    stop_datetime = Time.parse(arg)
    ppfilter.stop_when = stop_datetime
  when '--title'
    ppfilter.title = arg
  end
end

ppfilter.go(ARGV[0], ARGV[1])
