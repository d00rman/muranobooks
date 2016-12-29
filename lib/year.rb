require 'date'
require './lib/record'


module Books
  
  
  module BalanceSheet
    
    
    class Year
      
      
      attr_accessor :next_year
      attr_accessor :prev_year
      
      attr_reader :is_active
      attr_reader :year
      attr_reader :all
      
      
      def initialize year, config
        
        @next_year = nil
        @prev_year = nil
        @is_active = false
        @year = year
        @all = Record.new_balance
        
        @no_missing_months = 0
        @config = config
        @records = []
        @needs_update = true
        
      end
      
      
      def set_as_active
        
        @is_active = true
        @needs_update = true
        self
        
      end
      
      
      def set_next year = nil
        
        @next_year = year
        year.prev_year = self if year
        self
        
      end
      
      
      def add_record record
        
        @records.push( record ).sort! { |a, b| a.ts <=> b.ts }
        @needs_update = true
        self
        
      end
      
      
      def calculate call_next = false
        
        unless @needs_update
          @next_year.calculate( true ) if call_next and @next_year
          return self
        end
        
        mon = {}
        @no_missing_months = 0
        @all = Record.new_balance
        
        # add all of the records in the list
        @records.each do |rec|
          month = rec.ts.month
          bal = mon[month] ||= Record.new_balance
          self.add_balance rec.to_hash[:balance], bal, @all
        end
        
        # fill in the missing months for the current year
        curr_all = @all.merge Hash.new
        if @is_active
          ( 1..12 ).to_a.reverse.each do |month|
            break if mon[month]
            @no_missing_months += 1
            mon[month] = Books::BalanceSheet::Record.new_balance
            mon[month][:gross] = @config[:estimates][:income]
            mon[month][:expense] = @config[:estimates][:expense]
            mon[month][:taxable] = @config[:estimates][:taxable]
            self.add_balance mon[month], @all
          end
        end
        
        # transfer part of the state from the previous year
        if @prev_year
          self.transfer_from_prev @all
          self.transfer_from_prev( curr_all ) if @is_active
        end
        
        # calculate the annual givings
        annual = 0.0
        @config[:annual].each do |name, percentage|
          annual += @all[:gross] * ( percentage / 100.0 )
        end
        @all[:taxable] -= annual
        @all[:expense] += annual
        @all[:annual] = annual
        
        # taxes calculation
        @all[:taxes] = {}
        taxes = 0.0
        @config[:tax].sort { |a, b| a[:from] <=> b[:from] }.each do |tax|
          if tax[:to] and @all[:taxable] >= tax[:to]
            @all[:taxes][tax[:percent]] = tax[:to] - tax[:from]
          elsif @all[:taxable] >= tax[:from] and !tax[:to]
            @all[:taxes][tax[:percent]] = @all[:taxable] - tax[:from]
          end
        end
        @all[:taxes].each do |percent, amount|
          taxes += amount * percent / 100.0
        end
        @all[:taxes] = taxes
        
        # netto
        @all[:net_total] = @all[:net_total] + @all[:taxable] - taxes
        @all[:net_free] = @all[:net_total] - @all[:net_out]
        
        # re-adjust the taxes for the active year
        # if there are missing months
        if @is_active and @no_missing_months > 0
          curr_all[:taxes] = taxes * ( 12 - @no_missing_months) / 12.0
          curr_all[:annual] = annual * ( 12 - @no_missing_months) / 12.0
          curr_all[:net_total] = curr_all[:net_total] + curr_all[:taxable] - curr_all[:taxes] - curr_all[:annual]
          curr_all[:net_free] = curr_all[:net_total] - curr_all[:net_out]
          @all.merge! curr_all
        end
        
        @needs_update = false
        
        @next_year.calculate( true ) if call_next and @next_year
        
        self
        
      end
      
      
      protected
      
      
      def add_balance from, *to
        
        from.each do |k, v|
          to.each { |bal| bal[k] += v }
        end
        
        self
        
      end
      
      
      def transfer_from_prev dest
        
        p_all = @prev_year.all
        # transfer the account balance into the next year
        dest[:account] += p_all[:account]
        # ... net transfers
        dest[:net_total] += p_all[:net_free]
        # ... personal loans
        if ( p_all[:loan] * 1000 ).to_i != 0
          dest[:loan] += p_all[:loan]
        end
        # TODO: revisit this below
        if ( p_all[:taxable] * 1000 ).to_i < 0
          dest[:taxable] += p_all[:taxable]
          dest[:expense] -= p_all[:taxable]
        end
        
      end
      
      
    end
    
    
  end
  
  
end

