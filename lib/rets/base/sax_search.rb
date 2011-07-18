class RETS::Base::SAXSearch < Nokogiri::XML::SAX::Document
  def initialize(block)
    @block = block
  end

  def start_element(tag, attrs)
    @current_tag = nil

    # Figure out if the request is a success
    if tag == "RETS"
      reply_code = attrs.first.last
      if reply_code != "0" and reply_code != "20201"
        raise RETS::ServerError.new("#{attrs.last.last} (Code #{reply_code})")
      end

    # Determine the separator for data
    elsif tag == "DELIMITER"
      @delimiter = attrs.first.last.to_i.chr

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
      @columns = @buffer.split(@delimiter)

    # Finalize data and send it off
    else
      data = {}

      list = @buffer.split(@delimiter)
      list.each_index do |index|
        next if @columns[index].nil? or @columns[index] == ""
        data[@columns[index]] = list[index]
      end

      @block.call(data)
    end
  end
end
