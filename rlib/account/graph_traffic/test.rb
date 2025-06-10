#!/usr/local/bin/ruby
load '/wikk/etc/wikk.conf' unless defined? WIKK_CONF
require_relative "#{RLIB}/account/graph_sql_traffic.rb"

# Gen_Table_Internal_Hosts.debug('wik003', Time.parse('2022-11-01 00:00:00'), Time.parse('2023-11-02 00:00:00'))
Graph_Internal_Hosts.debug('wikk003', Time.parse('2022-11-01 00:00:00'), Time.parse('2022-11-02 00:00:00'))
Graph_flow_Host_Hist_trim.debug('wikk003', Time.parse('2022-11-01 00:00:00'), Time.parse('2022-11-02 00:00:00'))
Graph_Flow_Ports_Hist_trim.debug('wikk003', Time.parse('2022-11-01 00:00:00'), Time.parse('2022-11-02 00:00:00'))
