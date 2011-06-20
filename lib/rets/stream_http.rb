# This is a slightly crazy hack, but it's saner if we can just use Net::HTTP and then fallback on the StreamHTTP class when we need to do stream parsing.
# If we were to do it fully ourselves with Sockets, it would be a bigger pain to manage that, and we would have to do roughly the same setup as below anyway.
# Essentially, for the hack of using instance_variable_get/instance_variable_set, we get a simple stream parser, without having to write our own HTTP class.
module RETS
  class StreamHTTP
    def initialize(response)
      @response = response
      @left_to_read = @response.content_length
      @chunked = @response.chunked?
      @socket = @response.instance_variable_get(:@socket)
    end

    def read(read_len)
      if @left_to_read
        # We hit the end of what we need to read, if this is a chunked request, then we need to check for the next chunk
        if @left_to_read <= read_len
          data = @socket.read(@left_to_read)
          @left_to_read = nil
          @read_clfr = true
        # Reading from known buffer still
        else
          @left_to_read -= read_len
          data = @socket.read(read_len)
        end

      else @chunked
        # We finished reading the chunks, read the last 2 to get \r\n out of the way, and then find the next chunk
        if @read_clfr
          @read_clfr = nil
          @socket.read(2)
        end

        data = ""
        while true
          # Read first line to get the chunk length
          line = @socket.readline

          len = line.slice(/[0-9a-fA-F]+/) or raise Net::HTTPBadResponse.new("wrong chunk size line: #{line}")
          len = len.hex
          break if len == 0

          # The chunk is outside of our buffer, we're going to start a straight read
          if len > read_len
            @left_to_read = len - read_len
            data << @socket.read(read_len)
            break
          # We can just return the chunk as -is
          else
            data << @socket.read(len)
            @socket.read(2)
          end
        end
      end

      # We've finished reading, set this so Net::HTTP doesn't try and read it again
      if data == ""
        @response.instance_variable_set(:@read, true)

        nil
      else
        data
      end
    end

    def close
    end
  end
end

