#!/usr/bin/env ruby


require 'yaml'

require './lib/record'
require './lib/year'


config = YAML.load File.read( File.expand_path( File.join( File.dirname( __FILE__ ), 'config.yaml' ) ) )
config[:estimates][:taxable] = config[:estimates][:income] - config[:estimates][:expense]

data = YAML.load File.read( File.expand_path( File.join( File.dirname( __FILE__ ), 'flow.yaml' ) ) )
data[:templates].each { |name, hash| Books::BalanceSheet::Record.add_template name, hash }
records = data[:flow].map { |hash| Books::BalanceSheet::Record.new hash }.sort { |a, b| a.ts <=> b.ts }


# year-lib-based vars
lib_year = {}
#

balance = Hash.new

records.each do |rec|
  year = rec.ts.year
  month = rec.ts.month
  balance[year] ||= Hash.new
  lib_year[year] ||= Books::BalanceSheet::Year.new year, config
  lib_year[year].add_record rec
  bal = balance[year][month] ||= Books::BalanceSheet::Record.new_balance
  rec.to_hash[:balance].each { |k, v| bal[k] += v }
end

last_month = 12
last_year = balance.keys.sort.pop

lib_year[last_year].set_as_active
lib_year.keys.sort.each { |year| lib_year[year].set_next( lib_year[year + 1] ) if lib_year[year + 1] }
lib_year[lib_year.keys.sort.shift].calculate true

curr = balance[last_year].merge Hash.new
call = curr[:all] = Books::BalanceSheet::Record.new_balance
blast = balance[last_year] = {}
( 1..12 ).each do |month|
  if curr[month]
    last_month = month
    blast[month] = curr[month]
    curr[month].each { |k, v| curr[:all][k] += v }
    next
  end
  blast[month] = Books::BalanceSheet::Record.new_balance
  blast[month][:gross] = config[:estimates][:income]
  blast[month][:expense] = config[:estimates][:expense]
  blast[month][:taxable] = config[:estimates][:taxable]
end

balance.each do |year, bals|
  all = Books::BalanceSheet::Record.new_balance
  bals.each { |m, bal| bal.each { |k, v| all[k] += v } }
  bals[:all] = all
end

balance.keys.sort.each do |year|
  this = balance[year][:all]
  next unless balance[year + 1]
  that = balance[year + 1][:all]
  # transfer the account balance into the next year
  that[:account] += this[:account]
  call[:account] += this[:account] if last_year == year + 1
  # ... net transfers
  that[:net_total] += this[:net_free]
  call[:net_total] += this[:net_free] if last_year == year + 1
  if ( this[:taxable] * 1000 ).to_i < 0
    that[:taxable] += this[:taxable]
    that[:expense] -= this[:taxable]
    if last_year == year + 1
      call[:taxable] += this[:taxable]
      call[:expense] -= this[:taxable]
    end
  end
  if ( this[:loan] * 1000 ).to_i != 0
    that[:loan] += this[:loan]
    call[:loan] += this[:loan] if last_year == year + 1
  end
end

balance.each do |year, bals|
  bal = bals[:all]
  annual = 0.0
  config[:annual].each do |name, percentage|
    annual += bal[:gross] * ( percentage / 100.0 )
  end
  bal[:taxable] -= annual
  bal[:expense] += annual
  bal[:annual] = annual
  bal[:taxes] = {}
  taxes = 0.0
  config[:tax].sort { |a, b| a[:from] <=> b[:from] }.each do |tax|
    if tax[:to] and bal[:taxable] >= tax[:to]
      bal[:taxes][tax[:percent]] = tax[:to] - tax[:from]
    elsif bal[:taxable] >= tax[:from] and !tax[:to]
      bal[:taxes][tax[:percent]] = bal[:taxable] - tax[:from]
    end
  end
  bal[:taxes].each do |percent, amount|
    puts "#{year}: #{amount} * #{percent} = #{amount * percent / 100.0}"
    taxes += amount * percent / 100.0
  end
  bal[:taxes] = taxes
  bal[:net_total] = bal[:net_total] + bal[:taxable] - taxes
  bal[:net_free] = bal[:net_total] - bal[:net_out]
end

call[:taxes] = blast[:all][:taxes] * last_month / 12.0
call[:annual] = blast[:all][:annual] * last_month / 12.0
call[:net_total] = call[:net_total] + call[:taxable] - call[:taxes] - call[:annual]
call[:net_free] = call[:net_total] - call[:net_out]

blast[:all].merge! call

balance.each do |year, bals|
  lyear = lib_year[year]
  puts "[*] #{year} - script | lib_year | eq [*]"
  bals[:all].each do |key, val|
    ly_val = lyear.all[key]
    puts "    #{key}:  #{val}  |  #{ly_val}  |  #{( ( val - ly_val ) * 1000 ).to_i == 0 ? 'YES' : 'NO'}"
  end
  puts
end

