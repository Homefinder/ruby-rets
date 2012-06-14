# For more information on what the possible values of fields that are passed to the RETS server can be, see {http://www.rets.org/documentation}.
module RETS
  module Base
    class Core
      GET_OBJECT_DATA = ["object-id", "description", "content-id", "content-description", "location", "content-type", "preferred"]

      # Can be called after any {RETS::Base::Core} call that hits the RETS Server.
      # @return [String] How big the request was
      attr_reader :request_size

      # Can be called after any {RETS::Base::Core} call that hits the RETS Server.
      # @return [String] SHA1 hash of the request
      attr_reader :request_hash

      # Can be called after any {RETS::Base::Core} call that hits the RETS Server.
      # @return [Hash]
      #   Gives access to the miscellaneous RETS data, such as reply text, code, delimiter, count and so on depending on the API call made.
      #   * *text* (String) - Reply text from the server
      #   * *code* (String) - Reply code from the server
      attr_reader :rets_data

      def initialize(http, urls)
        @http = http
        @urls = urls
      end

      ##
      # Attempts to logout of the RETS server.
      #
      # @raise [RETS::CapabilityNotFound]
      # @raise [RETS::APIError]
      # @raise [RETS::HTTPError]
      def logout
        unless @urls[:logout]
          raise RETS::CapabilityNotFound.new("No Logout capability found for given user.")
        end

        @http.request(:url => @urls[:logout])

        nil
      end

      ##
      # Whether the RETS server has the requested capability.
      #
      # @param [Symbol] type Lowercase of the capability, "getmetadata", "getobject" and so on
      # @return [Boolean]
      def has_capability?(type)
        @urls.has_key?(type)
      end

      ##
      # Requests metadata from the RETS server.
      #
      # @param [Hash] args
      # @option args [String] :type Metadata to request, the same value if you were manually making the request, "METADATA-SYSTEM", "METADATA-CLASS" and so on
      # @option args [String] :id Filter the data returned by ID, "*" would return all available data
      # @option args [Integer, Optional] :read_timeout How many seconds to wait before giving up
      #
      # @yield For every group of metadata downloaded
      # @yieldparam [String] :type Type of data that was parsed with "METADATA-" stripped out, for "METADATA-SYSTEM" this will be "SYSTEM"
      # @yieldparam [Hash] :attrs Attributes of the data, generally *Version*, *Date* and *Resource* but can vary depending on what metadata you requested
      # @yieldparam [Array] :metadata Array of hashes with metadata info
      #
      # @raise [RETS::CapabilityNotFound]
      # @raise [RETS::APIError]
      # @raise [RETS::HTTPError]
      # @see #rets_data
      # @see #request_size
      # @see #request_hash
      def get_metadata(args, &block)
        raise ArgumentError, "No block passed" unless block_given?

        unless @urls[:getmetadata]
          raise RETS::CapabilityNotFound.new("No GetMetadata capability found for given user.")
        end

        @request_size, @request_hash, @rets_data = nil, nil, nil
        @http.request(:url => @urls[:getmetadata], :read_timeout => args[:read_timeout], :params => {:Format => :COMPACT, :Type => args[:type], :ID => args[:id]}) do |response|
          stream = RETS::StreamHTTP.new(response)
          sax = RETS::Base::SAXMetadata.new(block)

          Nokogiri::XML::SAX::Parser.new(sax).parse_io(stream)

          @request_size, @request_hash = stream.size, stream.hash
          @rets_data = sax.rets_data
        end

        nil
      end

      ##
      # Requests an object from the RETS server.
      #
      # @param [Hash] args
      # @option args [String] :resource Resource to load, typically *Property*
      # @option args [String] :type Type of object you want, usually *Photo*
      # @option args [String] :id What objects to return
      # @option args [Array, Optional] :accept Array of MIME types to accept, by default this is *image/png*, *image/gif* and *image/jpeg*
      # @option args [Boolean, Optional] :location Return the location of the object rather than the contents of it
      # @option args [Integer, Optional] :read_timeout How many seconds to wait before timing out
      #
      # @yield For every object downloaded
      # @yieldparam [Hash] :headers Object headers
      #     * *object-id* (String) - Objects ID
      #     * *content-id* (String) - Content ID
      #     * *content-type* (String) - MIME type of the content
      #     * *description* (String, Optional) - A description of the object
      #     * *location* (String, Optional) - Where the file is located, only returned is *location* is true
      # @yieldparam [String, Optional] :content Content for the object, not called when *location* is set
      #
      # @raise [RETS::CapabilityNotFound]
      # @raise [RETS::APIError]
      # @raise [RETS::HTTPError]
      # @see #rets_data
      # @see #request_size
      # @see #request_hash
      def get_object(args, &block)
        raise ArgumentError, "No block passed" unless block_given?

        unless @urls[:getobject]
          raise RETS::CapabilityNotFound.new("No GetObject capability found for given user.")
        end

        req = {:url => @urls[:getobject], :read_timeout => args[:read_timeout], :headers => {}}
        req[:params] = {:Resource => args[:resource], :Type => args[:type], :Location => (args[:location] ? 1 : 0), :ID => args[:id]}
        if args[:accept].is_a?(Array)
          req[:headers]["Accept"] = args[:accept].join(",")
        else
          req[:headers]["Accept"] = "image/png,image/gif,image/jpeg"
        end

        # Will get swapped to a streaming call rather than a download-and-parse later, easy to do as it's called with a block now
        @request_size, @request_hash, @rets_data = nil, nil, nil
        @http.request(req) do |response|
          body = response.read_body
          @request_size, @request_hash = body.length, Digest::SHA1.hexdigest(body)

          # Make sure we aren't erroring
          if body =~ /(<RETS(.+)\>)/
            code, text = @http.get_rets_response(Nokogiri::XML($1).xpath("//RETS").first)
            @rets_data = {:code => code, :text => text}

            if code == "20403"
              return
            else
              raise RETS::APIError.new("#{code}: #{text}", code, text)
            end
          end

          # Using a wildcard somewhere
          if response.content_type == "multipart/parallel"
            boundary = response.type_params["boundary"]
            boundary.gsub!(/^"|"$/, "")

            parts = body.split("--#{boundary}\r\n")
            parts.last.gsub!("\r\n--#{boundary}--", "")
            parts.each do |part|
              part.strip!
              next if part == ""

              headers, content = part.split("\r\n\r\n", 2)

              parsed_headers = {}
              headers.split("\r\n").each do |line|
                name, value = line.split(":", 2)
                next unless value and value != ""

                parsed_headers[name.downcase] = value.strip
              end

              if block.arity == 1
                yield parsed_headers
              else
                yield parsed_headers, content
              end

            end

          # Either text (error) or an image of some sorts, which is irrelevant for this
          else
            headers = {}
            GET_OBJECT_DATA.each do |field|
              next unless response.header[field] and response.header[field] != ""
              headers[field] = response.header[field].strip
            end

            if block.arity == 1
              yield headers
            else
              yield headers, body
            end
          end
        end

        nil
      end

      ##
      # Searches the RETS server for data.
      #
      # @param [Hash] args
      # @option args [String] :search_type What to search on, typically *Property*, *Office* or *Agent*
      # @option args [String] :class What class of data to return, varies between RETS implementations and can be anything from *1* to *ResidentialProperty*
      # @option args [String] :query How to filter data, should be unescaped as CGI::escape will be called on the string
      # @option args [Symbol, Optional] :count_mode Either *:only* to return just the total records found or *:both* to get count and records returned
      # @option args [Integer, Optional] :limit Limit total records returned
      # @option args [Integer, Optional] :offset Offset to start returning records from
      # @option args [Array, Optional] :select Restrict the fields the RETS server returns
      # @option args [Boolean, Optional] :standard_names Whether to use standard names for all fields
      # @option args [String, Optional] :restricted String to show in place of a field value for any restricted fields the user cannot see
      # @option args [Integer, Optional] :read_timeout How long to wait for data from the socket before giving up
      # @option args [Boolean, Optional] :disable_stream Disables the streaming setup for data and instead loads it all and then parses
      #
      # @yield Called for every <DATA></DATA> group from the RETS server
      # @yieldparam [Hash] :data One record of data from the RETS server
      #
      # @raise [RETS::CapabilityNotFound]
      # @raise [RETS::APIError]
      # @raise [RETS::HTTPError]
      # @see #rets_data
      # @see #request_size
      # @see #request_hash
      def search(args, &block)
        if !block_given? and args[:count_mode] != :only
          raise ArgumentError, "No block found"
        end

        unless @urls[:search]
          raise RETS::CapabilityNotFound.new("Cannot find URL for Search call")
        end

        req = {:url => @urls[:search], :read_timeout => args[:read_timeout]}
        req[:params] = {:Format => "COMPACT-DECODED", :SearchType => args[:search_type], :QueryType => "DMQL2", :Query => args[:query], :Class => args[:class], :Limit => args[:limit], :Offset => args[:offset], :RestrictedIndicator => args[:restricted]}
        req[:params][:Select] = args[:select].join(",") if args[:select].is_a?(Array)
        req[:params][:StandardNames] = 1 if args[:standard_names]

        if args[:count_mode] == :only
          req[:params][:Count] = 2
        elsif args[:count_mode] == :both
          req[:params][:Count] = 1
        end

        @request_size, @request_hash, @rets_data = nil, nil, {}
        @http.request(req) do |response|

          if args[:disable_stream]
            stream = StringIO.new(response.body)
          else
            stream = RETS::StreamHTTP.new(response)
          end

          sax = RETS::Base::SAXSearch.new(@rets_data, block)
          Nokogiri::XML::SAX::Parser.new(sax).parse_io(stream)

          @request_size, @request_hash = stream.size, stream.hash
        end

        nil
      end
    end
  end
end
