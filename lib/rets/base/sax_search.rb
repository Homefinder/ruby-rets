# SAX parser for the Search API call.
class RETS::Base::SAXSearch < Nokogiri::XML::SAX::Document
  attr_reader :rets_data

  def initialize(rets_data, block)
    @block = block
    @rets_data = rets_data
  end

  def start_element(tag, attrs)
    @current_tag = nil

    # Figure out if the request is a success
    if tag == "RETS"
      @rets_data[:code], @rets_data[:text] = attrs.first.last, attrs.last.last
      if @rets_data[:code] != "0" and @rets_data[:code] != "20201"
        raise RETS::APIError.new("#{@rets_data[:code]}: #{@rets_data[:text]}", @rets_data[:code], @rets_data[:text])
      end

    # Determine the separator for data
    elsif tag == "DELIMITER"
      @rets_data[:delimiter] = attrs.first.last.to_i.chr

    # Total records returned
    elsif tag == "COUNT"
      @rets_data[:count] = attrs.first.last.to_i

    # Parsing data
    elsif tag == "COLUMNS" or tag == "DATA"
      @buffer = ""
      @current_tag = tag
    end
  end

  def characters(string)
    @buffer << string if @current_tag
  end

  def end_element(tag)
    return unless @current_tag

    if @current_tag == "COLUMNS"
      @columns = @buffer.split(@rets_data[:delimiter])

    # Finalize data and send it off
    elsif tag == "DATA"
      data = {}

      list = @buffer.split(@rets_data[:delimiter])
      list.each_index do |index|
        next if @columns[index].nil? or @columns[index] == ""
        data[@columns[index]] = list[index]
      end

      @block.call(data)
    end
  end
end
