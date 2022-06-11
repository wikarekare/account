#!/usr/local/ruby3.0/bin/ruby
require 'wikk_sql'
require 'wikk_configuration'
RLIB = '../../rlib'
require_relative "#{RLIB}/wikk_conf.rb"

# [Accumulated GBytes This Month (2014-05-01 00:00:00 to 2014-06-01 00:00:00)]
# Direction	Link1
# GBytes	0

# PLAN_EXCESS_CAP = [
#                      { :plan => 30,
#                        :base_gb => 30,
#                        :extended_gb => 70,
#                        :extended_price => 1.0,
#                        :excess_price =>1.5
#                      },
#                      { :plan => 40,
#                        :base_gb => 40,
#                        :extended_gb => 80,
#                        :extended_price => 1.0,
#                        :excess_price =>1.5
#                      }
#                    ]
# MINIMUM_UNIT_CHARGE = 5  #dollars

def cmp(a, b)
  if a[0] !~ /wikk[0-9]*/
    if b[0] =~ /wikk[0-9]*/
      return -1 <=> b[1]   # Only first one wikkXXX
    else
      return b[0] <=> a[0] # Both wikkXXX
    end
  elsif b[0] !~ /wikk[0-9]*/ # Only second one wikkXXX
    return a[1] <=> -1
  else  # Neither wikkXXX
    return a[1] <=> b[1] # Sort by GBytes total.
  end
end

def fetch_site_plans
  query = <<~SQL
    SELECT site_name, plan_id, base_gb, extended_gb,
            base_price, extended_unit_price, excess_unit_price
    FROM customer, plan
    WHERE customer.plan = plan.plan_id
  SQL
  site_plan = {}
  @mysql_conf = WIKK::Configuration.new(MYSQL_CONF)
  WIKK::SQL.connect(@mysql_conf) do |my|
    my.each_hash(query) do |row|
      # site_plan[site_name] =
      site_plan[row['site_name']] = {
        plan_id: row['plan_id'].to_i,
        base_gb: row['base_gb'].to_i,
        extended_gb: row['extended_gb'].to_i,
        base_price: row['base_price'].to_f,
        extended_unit_price: row['extended_unit_price'].to_f,
        excess_unit_price: row['excess_unit_price'].to_f
      }
    end
  end
  return site_plan
end

# excess_cap = 17.5, charge_unit = 2.5, unit_cost = 5
def transpose_and_sum(input, outfile_fd) # , plan_rates, minimum_charge = 5)
  site_plan = fetch_site_plans

  output = []

  sums = [ 'Totals', 0.0, 0.0, 0.0,  # "Total GB", "Free GB", "Charged GB","plan",
           0.0, # plan
           0.0, # 'Base GB',
           0.0, 0.0,       # 'extended GB','Extended Cost',
           0.0, 0.0,       # 'Excess GB',  'Excess Cost',
           0.0             # "Total bill"
        ]

  # Four lines in input.
  # First is a comment
  # Second is list of hosts (starting at 2nd entry)
  # Third is list of GB's used (Starting at 2nd entry). Values above threshold.
  # Forth line is list of GB's used (Starting at 2nd entry). Free Usage, below Threshold
  input[1].each_with_index do |hostname, i| # From first host entry on the line
    next unless hostname =~ /^wikk/

    charged_total = input[2][i].to_f   # Matching GB entry on the second line
    free_total = input[3][i].to_f      # Matching GB entry on the Third line
    total_gb = charged_total + free_total
    if site_plan[hostname].nil?
      site_plan[hostname] = { plan_id: 0, base_gb: 0, extended_gb: 0, base_price: 0.0, extended_unit_price: 0.0, excess_unit_price: 0.0 }
      puts "Error: Site #{hostname} has no plan"
    end
    if charged_total > site_plan[hostname][:base_gb] # plan_rates[plan_id][:base_gb]
      base_usage = site_plan[hostname][:base_gb]     # plan_rates[plan_id][:base_gb]
      if charged_total > site_plan[hostname][:extended_gb] # plan_rates[plan_id][:extended_gb]
        extended_usage = site_plan[hostname][:extended_gb] - base_usage # plan_rates[plan_id][:extended_gb]
        excess_usage = charged_total - site_plan[hostname][:extended_gb] # plan_rates[plan_id][:extended_gb]
      else
        extended_usage = charged_total - base_usage
        excess_usage = 0.0
      end
    else
      base_usage = charged_total
      excess_usage = extended_usage = 0.0
    end

    site_extended_cost = site_plan[hostname][:extended_unit_price] * extended_usage # plan_rates[plan_id][:extended_price]
    site_excess_cost = site_plan[hostname][:excess_unit_price] * excess_usage # plan_rates[plan_id][:excess_price]

    value_array = [ hostname, total_gb.round(3), free_total.round(3), charged_total.round(3),
                    site_plan[hostname][:base_gb], # plan_rates[plan_id][:plan]
                    base_usage.round(3),
                    extended_usage.round(3), site_extended_cost.round(2),
                    excess_usage.round(3),   site_excess_cost.round(2),
                    (site_extended_cost + site_excess_cost).round(2)
              ]
    sums.each_with_index { |v, i| sums[i] = v + value_array[i] unless i == 0 }
    value_array[1] = '%.3f' % value_array[1]
    value_array[2] = '%.3f' % value_array[2]
    value_array[3] = '%.3f' % value_array[3]
    value_array[4] = '%.0f' % value_array[4]
    value_array[5] = '%.3f' % value_array[5]
    value_array[6] = '%.3f' % value_array[6]
    value_array[7] = '$%.2f' % value_array[7]
    value_array[8] = '%.3f' % value_array[8]
    value_array[9] = '$%.2f' % value_array[9]
    value_array[10] = '$%.2f' % value_array[10]
    output << value_array
  end

  outfile_fd.puts [ 'Site', 'Total GB', 'Free GB', 'Charged GB',
                    'plan GB',
                    'Base GB',
                    'extended GB', 'Extended Cost',
                    'Excess GB', 'Excess Cost',
                    'Total bill'
                  ].join("\t")

  output.each { |o| outfile_fd.puts o.join("\t") }

  sums[1] = '%.3f' % sums[1]
  sums[2] = '%.3f' % sums[2]
  sums[3] = '%.3f' % sums[3]
  sums[4] = '%.2f' % sums[4]
  sums[5] = '%.3f' % sums[5]
  sums[6] = '%.3f' % sums[6]
  sums[7] = '$%.2f' % sums[7]
  sums[8] = '%.3f' % sums[8]
  sums[9] = '$%.2f' % sums[9]
  sums[10] = '$%.2f' % sums[10]
  outfile_fd.puts sums.join("\t")
  outfile_fd.puts "Date\t#{Time.now.strftime('%Y-%m-%d %H:%M')}"
end

if ARGV[0].nil?
  puts 'transpose_and_sum input_file [output_file]'
  exit 1
end

input_name = ARGV[0]
output_name = if ARGV[1].nil?
                input_name.gsub(/usage_/, 'bill_')
              else
                ARGV[1]
              end

# 25G Free
# Before July 2014: 2/GB in $5 increments (rounded up). Hence units of 2.5GB
# transpose_and_sum(input_name, output_name, 25.0, 2.5, 5.0)
# From July 2014: 25G free $2.5/GB $2.5 increments (rounded up). Hence units ef 1GB
# From July 2015: 20G free $2.5/GB $2.5 increments (rounded up). Hence units ef 1GB (allow 0.33Mb/s free)
lines = []
File.open(input_name) do |fd|
  fd.each_line do |l|
    tokens = l.chomp.split("\t")
    lines << tokens
  end
end

File.open(output_name, 'w') do |fd|
  transpose_and_sum(lines, fd) # , PLAN_EXCESS_CAP, MINIMUM_UNIT_CHARGE)
end
