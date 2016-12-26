require 'date'


module Books
  
  
  module BalanceSheet
    
    
    class Record
      
      
      FIELDS = [:type, :desc, :amount, :tax, :loan, :ts]
      
      DEFAULT = {
        type: :out,
        desc: '',
        amount: 0.0,
        tax: true,
        loan: false,
        ts: nil
      }
      
      FIELDS.each { |f| attr_reader f }
      
      BALANCE_FIELDS = [
        :account,
        :in,
        :out,
				:gross,
        :taxable,
        :expense,
        :loan,
        :net_out,
        :net_free,
        :net_total
      ]
      
      
      # the hash of templates with name => record pairs
      @@templates = {}
      
      
      def self.add_template name, attr_hash = nil
        
        @@templates[name] = Record.new attr_hash
        
      end
      
      
      def self.new_balance
        
        retval = Hash.new
        BALANCE_FIELDS.each { |bf| retval[bf] = 0.0 }
        
        return retval
        
      end
      
      
      def initialize attr_hash = {}
        
        # first, check if we have a Record already
        if attr_hash.is_a? Record
          attr_hash = attr_hash.to_hash
          attr_hash.keep_if { |k, v| FIELDS.include? k.to_sym }
        end
        
        # then, check if we have a template
        if attr_hash.key?( :template ) or attr_hash.key?( 'template' )
          attr_copy = attr_hash.merge Hash.new
          attr_copy.keep_if { |k, v| k.to_sym != :template }
          attr_hash = @@templates[attr_hash[:template] || attr_hash['template']].to_hash
          attr_hash.keep_if { |k, v| FIELDS.include? k.to_sym }
          attr_hash.merge! attr_copy
        end
        
        DEFAULT.each do |key, val|
          self.instance_variable_set "@#{key.to_s}".to_sym, val
        end
        
        self.update attr_hash
        
      end
      
      
      def update attr_hash = nil
        
        return self if !attr_hash.is_a?( Hash ) || attr_hash.empty?
        
        attr_hash.each do |key, val|
          raise ArgumentError, "unsupported key - #{key}" unless FIELDS.include? key.to_sym
          self.instance_variable_set "@#{key.to_s}".to_sym, val
        end
        
        @type = @type.to_sym
        raise ArgumentError, "unknown type #{@type}" unless [:in, :out].include? @type
        @multiplier = case @type
          when :in then 1
          when :out then -1
        end
        
        @ts ||= Date.today
        @ts = Date.parse( @ts ) unless @ts.is_a?( Date )
        
        @balance = nil
        @hash = nil
        @string = nil
        
        self
        
      end
      
      
      def balance
        
        return @balance if @balance
        
        @balance = Record.new_balance
        @balance[@type] = @amount
        @balance[:account] = @multiplier * @amount
        if @loan
          @balance[:loan] = @multiplier * @amount
        elsif @tax
          @balance[:taxable] = @multiplier * @amount
          @balance[:expense] = @amount if @type == :out
          @balance[:gross] = @amount if @type == :in
        elsif @type == :out
          @balance[:net_out] = @amount
        end
        
        return @balance
        
      end
      
      
      def to_hash
        
        return @hash if @hash
        
        @hash = {}
        FIELDS.each do |key|
          @hash[key] = self.instance_variable_get "@#{key.to_s}"
        end
        @hash[:balance] = self.balance.merge Hash.new
        
        return @hash
        
      end
      
      
      def to_s
        
        @string ||= self.to_hash.to_s
        
      end
      
      
    end
    
    
  end
  
  
end

