#!/usr/local/bin/ruby
require 'wikk_sql'
require 'time'
require 'wikk_configuration'

unless defined? WIKK_CONF
  load '/wikk/etc/wikk.conf'
end

# For each customer site
# Insert a start of month marker record into the log_summary table
@mysql_conf = WIKK::Configuration.new(MYSQL_CONF)
WIKK::SQL.connect(@mysql_conf) do |sql|
  query = <<~SQL
    INSERT INTO log_summary (bytes_in , bytes_out , hostname  , log_timestamp )
      SELECT 0.0, 0.0, site_name, Date_format(now(),'%Y-%m-01 00:00:01')
      FROM customer
      WHERE active = 1
      AND site_name LIKE 'wikk%'
    ON DUPLICATE KEY UPDATE log_timestamp = log_timestamp, hostname=hostname
  SQL
  # puts query
  sql.query(query)
end
