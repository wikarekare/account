require 'rubygems'
require 'wikk_sql'
require 'pp'
require 'date'
require 'time'
require 'tmpfile'
RLIB = '/wikk/rlib'
require_relative "#{RLIB}/utility/datetime_ext.rb"

# Uber class for common methods
class Graph_Parent
  attr_reader :images
  attr_accessor :debug

  def initialize
    @debug = false ######
    @images = ''
  end

  def adsl_ip?(address)
    return address == EXTERNAL5 || address == EXTERNAL6 || address == EXTERNAL7
  end

  def ignore?(dest_address)
    dest_ip = dest_address.split('.')
    return ( adsl_ip?(dest_address) ||
             dest_ip[0] == '10' ||  # Destination is 10.0.0.0/8
             ( dest_ip[0] == '192' && dest_ip[1] == '168' ) || # Destination is 192.168.0.0/16
             ( dest_ip[0] == '100' && dest_ip[1] == '64' ) || # Destination is 100.64.0.0/16
             ( dest_ip[0] == '172' && dest_ip[1].to_i >= 16 && dest_ip[1].to_i < 32 ) || # Destination is 172.16.0.0/12
             dest_address == '255.255.255.255' || # Broadcast
             ( dest_ip[0] >= '224' && dest_ip[0] <= '239' )   # Destination is multicast
           )
  end
end

# Manifest
require_relative 'graph_traffic/graph2d.rb'
require_relative 'graph_traffic/graph3d.rb'
require_relative 'graph_traffic/graph_host_usage.rb'
require_relative 'graph_traffic/graph_total_usage.rb'
require_relative 'graph_traffic/graph_connections.rb'
require_relative 'graph_traffic/graph_ports.rb'
require_relative 'graph_traffic/graph_ntm_port_histogram.rb'
require_relative 'graph_traffic/graph_ntm_host_histogram.rb'
require_relative 'graph_traffic/graph_ntm_port_histogram_trim.rb'
require_relative 'graph_traffic/graph_ntm_host_histogram_trim.rb'
require_relative 'graph_traffic/graph_flow_host_hist_trim.rb'
require_relative 'graph_traffic/graph_flow_port_histogram_trim.rb'
require_relative 'graph_traffic/graph_internal_hosts.rb'
