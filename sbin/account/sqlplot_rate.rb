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
require 'date'

require 'wikk_configuration'
RLIB = '/wikk/rlib' unless defined? RLIB
require_relative "#{RLIB}/wikk_conf.rb"

# Horrible name.
# Update the daily log_summary cache
# Then generate site and link usage graphs for the web site
class Preprocess
  FLINK = 5   # First active link
  NLINKS = 7  # Total number of links

  # The global free rate is defined in the 'plan' table's free_rate field for plan_id -1
  # Low level traffic, under INTERVAL_BYTE_COUNT_100 * free_rate, is not charged.
  # To make the calculation simpler, this amount is subtracted from all 10s intervals.
  # 1Mb/s free for 10s interval.
  INTERVAL_BYTE_COUNT_100 = 1310720

  # 1GByte = 1024x1024x1024
  GBYTE = 1073741824.0

  attr_accessor :start_when, :stop_when, :title, :full_update

  # Set up accounting interval
  def initialize
    @start_when = nil
    @stop_when = nil
    @title = nil
    @full_update = false
    @interval_byte_count = 0 # Free traffic rate, measured in bytes every 10s
  end

  # Produce a site usage graph for the web page
  # Creates a data txt and tsv usage file, which we process further in the next step
  # Plot file is written to the standard output, which can be feed into gnuplot, referencing the data file
  # @param tmp_stats_file [String] Working file holding plot data, which gets included in the gnu plot file
  # @param gplot_filename [String] The filename for the PNG graph
  def go(tmp_stats_file, gplot_filename)
    @tmp_stats_file = tmp_stats_file
    @gplot_filename = gplot_filename
    # tmp_excel_file is a TSV transitional file, for human consumption
    # Further processed by transpose and sum rate
    @tmp_excel_file = @gplot_filename.sub('.png', '_excel.txt')
    # We also want a summary graph, excluding the sites
    @gplot_link_filename = @gplot_filename.sub('.png', '_link.png')
    # puts "# #{@tmp_stats_file}"
    # puts "# #{@gplot_filename}"

    # @start_when = last23rd  if @start_when == nil
    @today = Date.today
    @start_when = Date.new(@today.year, @today.month, 1) if @start_when.nil? # start of the month.
    @stop_when =  @start_when.next_month if @stop_when.nil? # start of the next month
    @sum_giga_bytes = {}
    (1..NLINKS).each do |i| # 0.0's are there so we have the right number of entries before we append to the array
      @sum_giga_bytes["Link#{i}"] = [ 0.0, 0.0 ] # [Below Threshold, Above_threshold]
    end

    @mysql_conf = WIKK::Configuration.new(MYSQL_CONF)
    WIKK::SQL.connect(@mysql_conf) do |sql|
      update_bill_cache(sql: sql)
      fetch_this_months_usage(sql: sql)
    end

    @key_by_index = [ 'Hosts' ]
    @sum_free_giga_bytes = [ 'Free_GB' ] # Record actual usage, so we know what we are giving away for free.
    @sum_charged_giga_bytes = [ 'Charged_GB' ]     # Charging for values above the threshold

    sorted = @sum_giga_bytes.sort
    # Get just the links in pass 1
    sorted.each do |hostname, usage|
      next unless hostname =~ /^Link/

      @key_by_index << hostname
      @sum_charged_giga_bytes << usage[0].round(3)
      @sum_free_giga_bytes << 0.0
    end

    # Then add in the rest, ignoring the traffic from the distribution nodes.
    sorted.each do |hostname, usage| # rubocop: disable Style/CombinableLoops
      next if hostname =~ /^100\.64\..*$/ || hostname =~ /^Link/

      @key_by_index << hostname
      @sum_charged_giga_bytes << usage[1].round(3)
      @sum_free_giga_bytes << (usage[0] - usage[1]).round(3)
    end

    gen_gnuplot_output
    gen_excel_output
    gen_link_output

    print_gnuplot
    print_gnuplot_links
  end

  # update the daily_usage cache, to make lookups much faster
  # If @full_update, then we update the cache back to the start of the month of @start_when
  # Otherwise, we assume the cache is no more than a day old (it is probably on 6m old)
  private def update_bill_cache(sql:)
    yesterday = @full_update ? Date.new(@start_when.year, @start_when.month, 1) : @today.prev_day
    tomorrow = @full_update ? Date.new(@stop_when.year, @stop_when.month, 1) : @today.next_day
    res = sql.query_hash <<~SQL
      SELECT free_rate FROM plan WHERE plan_id = -1
    SQL
    # Free traffic rate, measured in bytes every 10s
    @interval_byte_count = (INTERVAL_BYTE_COUNT_100 * res.first['free_rate'].to_f).round

    # set the daily cached values.
    # No clean way to ensure this is done properly, should we fail to process logs until much later.
    #
    # So we catch 99% by updating yesterday too, and the whole month, before billing proceeds.
    update_usage_query = <<~SQL
      INSERT INTO daily_usage ( bill_day, hostname, used_bytes, charged_bytes )
        SELECT  DATE(log_timestamp) as bill_date,
                hostname,
                SUM(bytes_in + bytes_out),
                SUM(IF((bytes_in + bytes_out) > #{@interval_byte_count}, bytes_in + bytes_out - #{@interval_byte_count},0))
        FROM log_summary
        WHERE log_timestamp >= '#{yesterday}'
        AND log_timestamp < '#{tomorrow}'
        GROUP BY hostname, bill_date
      ON DUPLICATE
        KEY UPDATE used_bytes=VALUES(used_bytes), charged_bytes=VALUES(charged_bytes)
    SQL

    sql.query(update_usage_query)
  end

  # Fetch the months usage, by site, setting @sum_giga_bytes
  # @param sql [SQL_FD] open connection to the DB
  private def fetch_this_months_usage(sql:)
    # Get the values, above the threshold in each interval.
    fetch_usage_query = <<~SQL
      SELECT hostname, sum(used_bytes)/#{GBYTE} AS used_gbytes, sum(charged_bytes)/#{GBYTE} AS charged_gbytes
      FROM daily_usage
      WHERE bill_day >= '#{@start_when}'
      AND bill_day < '#{@stop_when}'
      GROUP BY hostname
    SQL

    sql.each_hash(fetch_usage_query) do |row|
      row['hostname'].capitalize! if row['hostname'] =~ /^link/
      @sum_giga_bytes[row['hostname']] = [ row['used_gbytes'].to_f, row['charged_gbytes'].to_f ]
    end
  end

  # Update the bill_month table
  # fetching @sum_giga_bytes values from this months bill_month.

  # Output the plot data for the per site usage graph
  # Then print gnuplot commands to STDOUT, so gnuplot can create the graph
  private def gen_gnuplot_output
    File.open(@tmp_stats_file, 'w') do |fd_out|
      print_header fd_out
      print_key fd_out
      print_charged_gb_line fd_out
    end
  end

  # Output a TSV file, of the per site usage, separately reporting 'Charged' and 'Free' GB
  private def gen_excel_output
    File.open(@tmp_excel_file, 'w') do |fd_out|
      print_header fd_out
      print_key fd_out
      print_charged_gb_line fd_out
      print_free_gb_line fd_out
    end
  end

  # Output the instructions for generating the per link usage summary graph
  private def gen_link_output
    File.open("#{@tmp_stats_file}.lnk", 'w') do |fd_out|
      print_header fd_out
      print_link_key fd_out
      print_link_line fd_out
    end
  end

  # Outputs gnuplot instructions for site usage graph
  private def print_gnuplot
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
        print "set title \"Monthly Usage per site #{@start_when} to #{@stop_when} (#{Time.new})\"  offset character 0, 0, 0 font \"\" norotate\n"
      else
        print "set title \"Monthly Usage per site starting at #{@start_when} (#{Time.new})\"  offset character 0, 0, 0 font \"\" norotate\n"
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

  # Output gnuplot data reference lines for site usage graph
  private def print_plot_cmd
    print "plot '#{@tmp_stats_file}' "
    # (@key_by_index.length - 2).times { |x| print " using #{x + 2} ti col, '' " }
    (NLINKS + 2...@key_by_index.length).each { |x| print " using #{x} ti col, '' " }
    print " using #{@key_by_index.length}:key(1) ti col\n"
  end

  # Output header line for site usage
  private def print_header(fd_out)
    fd_out.puts "#[Accumulated GBytes This Month (#{@start_when} to #{@stop_when})] Line1 is hostnames, Line2 is GBs above threshold, Line3 is actual GBs used\n"
  end

  # output TSV key names header
  private def print_key(fd_out)
    fd_out.puts "#{@key_by_index.join("\t")}"
  end

  # Output TSV Charged GB per site line
  private def print_charged_gb_line(fd_out)
    fd_out.puts "#{@sum_charged_giga_bytes.join("\t")}"
  end

  # Output TSV Free GB per site line
  private def print_free_gb_line(fd_out)
    fd_out.puts "#{@sum_free_giga_bytes.join("\t")}"
  end

  # Print key for link data line
  private def print_link_key(fd_out)
    fd_out.print "#{@key_by_index[0]}"
    (FLINK..NLINKS).each do |i|
      fd_out.print "\t#{@key_by_index[i]}"
    end
    fd_out.print "\n"
  end

  # output link graph data line
  private def print_link_line(fd_out)
    fd_out.print "#{@sum_charged_giga_bytes[0]}"
    (FLINK..NLINKS).each do |i|
      fd_out.print "\t#{@sum_charged_giga_bytes[i]}"
    end
    fd_out.print "\n"
  end

  # Output GNUPlot instructions for generating link summary graph
  private def print_gnuplot_links
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

  # Output data reference line, into link summary gnuplot cmd stream
  private def print_plot_links_cmd
    print "plot '#{@tmp_stats_file}.lnk' "
    (FLINK...NLINKS).each { |x| print " using #{x - FLINK + 2} ti col, '' " }
    print " using #{NLINKS - FLINK + 2}:key(1) ti col\n"
  end
end

require 'getoptlong'

opts = GetoptLong.new(
  [ '--title',	GetoptLong::REQUIRED_ARGUMENT ],
  [ '--start_when', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--stop_when', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--full_update', GetoptLong::NO_ARGUMENT ]
)

ppfilter = Preprocess.new

opts.each do |opt, arg|
  case opt
  when '--start_when'
    # the_date = ParseDate::parsedate(arg, false )
    # start_datetime = Time.local(*the_date[0..5])
    start_datetime = Date.parse(arg)
    ppfilter.start_when = start_datetime
  when '--stop_when'
    # the_date = ParseDate::parsedate(arg, false )
    # stop_datetime = Time.local(*the_date[0..5])
    stop_datetime = Date.parse(arg)
    ppfilter.stop_when = stop_datetime
  when '--title'
    ppfilter.title = arg
  when '--full_update'
    ppfilter.full_update = true
  end
end

# ARGV[0] is the name of the tmp tsv file, we write plot data into
#         This file also gets processed into a bill tsv
# ARGV[1] is the name of the PNG file, GNUPlot will save the graph into
ppfilter.go(ARGV[0], ARGV[1])
