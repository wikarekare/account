#!/usr/local/bin/ruby
RLIB = '/wikk/rlib'

require "#{RLIB}/wikk_conf.rb"
require_relative '../graph_sql_traffic.rb'

# Graph_flow_Host_Hist_trim.debug('wikk046', Time.parse('2016-02-01 00:00:00'), Time.parse('2016-03-01 00:00:00'))
Graph_Flow_Ports_Hist_trim.debug('wikk125', Time.parse('2017-06-23 00:00:00'), Time.parse('2017-06-24 00:00:00'))
