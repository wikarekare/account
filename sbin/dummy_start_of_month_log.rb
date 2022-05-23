#!/usr/local/ruby3.0/bin/ruby
require 'wikk_sql'
require 'time'
require 'wikk_configuration'
RLIB = '../../rlib'
require_relative "#{RLIB}/wikk_conf.rb"

@mysql_conf = WIKK::Configuration.new(MYSQL_CONF)
WIKK::SQL.connect(@mysql_conf) do |my|
  # puts ("insert ignore into log_summary (bytes_in , bytes_out , hostname  , log_timestamp ) select 0.0,0.0,site_name, '#{Time.now.strftime("%Y-%m-%d")} 00:00:01' from customer where active = 1 and site_name like 'wikk%'")
  my.query("insert ignore into log_summary (bytes_in , bytes_out , hostname  , log_timestamp ) select 0.0,0.0,site_name, '#{Time.now.strftime('%Y-%m-%d')} 00:00:01' from customer where active = 1 and site_name like 'wikk%'")
end
