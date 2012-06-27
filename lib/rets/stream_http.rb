# This is a slightly crazy hack, but it's saner if we can just use Net::HTTP and then fallback on the StreamHTTP class when we need to do stream parsing.
# If we were to do it ourselves with Sockets, it would be a bigger pain to manage that, and we would have to do roughly the same setup as below anyway.
# Essentially, for the hack of using instance_variable_get/instance_variable_set, we get a simple stream parser, without having to write our own HTTP class.
module RETS
  class StreamHTTP
    ENCODABLE = RUBY_VERSION >= "1.9.0"

    ##
    # Initializes a new HTTP stream which can be passed to Nokogiri for SAX parsing.
    # @param [Net::HTTPResponse] response
    #   Unused HTTP response, no calls to any of the read_body or other methods can have been called.
    def initialize(response)
      @response = response
      @left_to_read = @response.content_length
      @content_length = @response.content_length
      @chunked = @response.chunked?
      @socket = @response.instance_variable_get(:@socket)

      @digest = Digest::SHA1.new
      @total_size = 0

      if @response.header.key?("content-type") and @response["content-type"] =~ /.*charset=(.*)/i
        @encoding = $1.to_s.upcase
      end
    end

    ##
    # The total size read from the stream, can be called either while reading or at the end.
    def size
      @total_size
    end

    ##
    # SHA1 hash of the data read from the stream
    def hash
      @digest.hexdigest
    end

    ##
    # Detected encoding
    def encoding
      @encoding
    end

    ##
    # Read
    #
    # @param [Integer] read_len
    #   How many bytes to read from the HTTP stream
    def read(read_len)
      # If we closed the connection, return nil without calling anything again to avoid EOF
      # or other errors
      return nil if @closed

      if @left_to_read
        # We hit the end of what we need to read, if this is a chunked request, then we need to check for the next chunk
        if @left_to_read <= read_len
          data = @socket.read(@left_to_read)
          @total_size += @left_to_read
          @left_to_read = nil
          @read_clfr = true
        # Reading from known buffer still
        else
          @left_to_read -= read_len
          @total_size += read_len
          data = @socket.read(read_len)
        end

      elsif @chunked
        # We finished reading the chunks, read the last 2 to get \r\n out of the way, and then find the next chunk
        if @read_clfr
          @read_clfr = nil
          @socket.read(2)
        end

        data, chunk_read = "", 0
        while true
          # Read first line to get the chunk length
          line = @socket.readline

          len = line.slice(/[0-9a-fA-F]+/) or raise Net::HTTPBadResponse.new("wrong chunk size line: #{line}")
          len = len.hex

          # Nothing left, read off the final \r\n
          if len == 0
            @socket.read(2)
            @socket.close
            @response.instance_variable_set(:@read, true)

            @closed = true
            break
          end

          # Reading this chunk will set us over the buffer amount
          # Read what we can of it (if anything), and send back what we have and queue a read for the rest
          if ( chunk_read + len ) > read_len
            can_read = len - ( ( chunk_read + len ) - read_len )

            @left_to_read = len - can_read
            @total_size += can_read

            data << @socket.read(can_read) if can_read > 0
            break
          # We can just return the chunk as-is
          else
            @total_size += len
            chunk_read += len

            data << @socket.read(len)
            @socket.read(2)
          end
        end

      # If we don't have a content length, then we need to keep reading until we run out of data
      elsif !@content_length
        data = @socket.readline

        @total_size += data.length if data
      end

      # We've finished reading, set this so Net::HTTP doesn't try and read it again
      if !data or data == ""
        @response.instance_variable_set(:@read, true)

        nil
      else
        if data.length >= @total_size and !@chunked
          @response.instance_variable_set(:@read, true)
        end

        if ENCODABLE and @encoding
          data = data.force_encoding(@encoding) if @encoding
          data = data.encode("UTF-8")
        end

        @digest.update(data)
        data
      end

    # Mark as read finished, return the last bits of data (if any)
    rescue EOFError
      @response.instance_variable_set(:@read, true)
      @socket.close
      @closed = true

      if data and data != ""
        @digest.update(data)
        data
      else
        nil
      end
    end

    ##
    # Does nothing, only used because Nokogiri requires it in a SAX parser.
    def close
    end
  end
end