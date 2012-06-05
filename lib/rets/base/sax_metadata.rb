# SAX parser for the GetMetadata call.
class RETS::Base::SAXMetadata < Nokogiri::XML::SAX::Document
  attr_accessor :rets_data

  def initialize(block)
    @rets_data = {:delimiter => "\t"}
    @block = block
    @parent = {}
  end

  def start_element(tag, attrs)
    @current_tag = nil

    # Figure out if the request is a success
    if tag == "RETS"
      @rets_data[:code], @rets_data[:text] = attrs.first.last, attrs.last.last
      if @rets_data[:code] != "0" and @rets_data[:code] != "20201"
        raise RETS::APIError.new("#{@rets_data[:code]}: #{@rets_data[:text]}", @rets_data[:code], @rets_data[:text])
      end

    elsif tag == "SYSTEM"
      @rets_data[:system_id] = attrs.first.last

    # Parsing data
    elsif tag == "COLUMNS" or tag == "DATA"
      @buffer = ""
      @current_tag = tag

    # Start of the parent we're working with
    elsif tag =~ /^METADATA-(.+)/
      @parent[:tag] = tag
      @parent[:name] = $1
      @parent[:data] = []
      @parent[:attrs] = {}
      attrs.each {|attr| @parent[:attrs][attr[0]] = attr[1] }
    end
  end

  def characters(string)
    @buffer << string if @current_tag
  end

  def end_element(tag)
    return unless @current_tag

    if @current_tag == "COLUMNS"
      @columns = @buffer.split(@rets_data[:delimiter])
    elsif tag == "DATA"
      data = {}

      list = @buffer.split(@rets_data[:delimiter])
      list.each_index do |index|
        next if @columns[index].nil? or @columns[index] == ""
        data[@columns[index]] = list[index]
      end

      @parent[:data].push(data)
    elsif tag == @parent[:tag]
      @block.call(@parent[:name], @parent[:attrs], @parent[:data])
      @parent[:tag] = nil
    end
  end
end
