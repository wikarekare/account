#!/usr/local/bin/ruby
require 'wikk_sql'
require 'time'
require 'wikk_configuration'
RLIB = '../../rlib'
require_relative "#{RLIB}/wikk_conf.rb"

@mysql_conf = WIKK::Configuration.new(MYSQL_CONF)
WIKK::SQL.connect(mysql_conf) do |my|
  query = <<~SQL
    INSERT INTO log_summary (bytes_in , bytes_out , hostname  , log_timestamp )
      SELECT 0.0,0.0,site_name, '#{Time.now.strftime('%Y-%m-%d')} 00:00:01'
      FROM customer
      WHERE active = 1
      AND site_name LIKE 'wikk%'
    ON DUPLICATE KEY UPDATE log_timestamp = log_timestamp, hostname=hostname
  SQL
  # puts query
  my.query(query)
end
