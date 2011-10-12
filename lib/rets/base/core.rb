require "nokogiri"

# For more information on what the possible values of fields that are passed to the RETS server can be, see {http://www.rets.org/documentation}.
module RETS
  module Base
    class Core
      GET_OBJECT_DATA = {"object-id" => "Object-ID", "description" => "Description", "content-id" => "Content-ID"}

      # Can be called after any {RETS::Base::Core#get_metadata}, {RETS::Base::Core#search} or {RETS::Base::Core#get_object} calls to get how much data was returned from the server.
      # @return [String] How big the request was.
      attr_accessor :request_size

      # Can be called after any {RETS::Base::Core#get_metadata}, {RETS::Base::Core#search} or {RETS::Base::Core#get_object} calls to get a hash of the servers returned data.
      # @return [String] SHA1 hash of the request.
      attr_accessor :request_hash

      def initialize(http, version, urls)
        @http = http
        @urls = urls
        @active_version = version
      end

      ##
      # Attempts to logout of the RETS server.
      def logout
        return unless @urls[:logout]
        @http.request(:url => @urls[:logout], :skip_auth => true)
      end

      ##
      # Requests metadata from the RETS server.
      #
      # @param [Hash] args
      #   * type - Metadata to request, the same value if you were manually making the request, "METADATA-SYSTEM", "METADATA-CLASS" and so on.
      #   * id - Filter the data returned by ID, "*" would return all available data.
      #   * read_timeout (Optional) - How many seconds to wait before giving up.
      #
      # @param [Proc] block
      #   Block the library should call for each bit of metadata downloaded. Called with the below arguments:
      #   * type (String) - Type of data that was parsed with "METADATA-" stripped out, for "METADATA-SYSTEM" this will be "SYSTEM".
      #   * attrs (Hash) - Attributes of the data, generally *Version*, *Date* and *Resource* but can vary depending on what metadata you requested.
      #   * data (Array) - Array of hashes with all of the metadatas info inside.
      #
      # @return
      #   Can raise {RETS::CapabilityNotFound} or {RETS::ServerError} exceptions if something goes wrong.
      def get_metadata(args, &block)
        unless @urls[:getmetadata]
          raise RETS::CapabilityNotFound.new("Cannot find URL for GetMetadata call")
        end

        @http.request(:url => @urls[:getmetadata], :read_timeout => args[:read_timeout], :params => {:Format => :COMPACT, :Type => args[:type], :ID => args[:id]}) do |response|
          stream = RETS::StreamHTTP.new(response)

          doc = Nokogiri::XML::SAX::Parser.new(RETS::Base::SAXMetadata.new(block))
          doc.parse_io(stream)

          self.request_size = stream.size
          self.request_hash = stream.hash
        end
      end

      ##
      # Requests an object from the RETS server.
      #
      # @param [Hash] args
      #   * resource - Resource to load, typically *Property*.
      #   * type - Type of object you want, usually *Photo*.
      #   * location - Whether the location of the object should be returned, rather than the entire object.
      #   * id - Filter what objects are returned.
      #   * read_timeout (Optional) - How many seconds to wait before giving up.
      #
      # @return [Array] objects
      #   Returns an array containing the objects found. Can raise {RETS::CapabilityNotFound}, {RETS::InvalidResponse} or {RETS::ServerError} exceptions if something goes wrong.
      #   Each object contains the following fields:
      #   * content - Content returned for the object.
      #   - headers
      #     * Object-ID - Objects ID
      #     * Content-ID - Content ID
      #     * Content-Type - MIME type of the content.
      #     * Description - A description of the object, if any.
      def get_object(args)
        unless @urls[:getobject]
          raise RETS::CapabilityNotFound.new("Cannot find URL for GetObject call")
        end

        headers = {"Accept" => "image/png,image/gif,image/jpeg"}

        objects = []
        @http.request(:url => @urls[:getobject], :read_timeout => args[:read_timeout], :headers => headers, :params => {:Resource => args[:resource], :Type => args[:type], :Location => (args[:location] ? 1 : 0), :ID => args[:id]}) do |response|
          unless response.code == "200"
            raise RETS::InvalidResponse.new("Tried to retrieve object, got #{response.message} (#{response.code}) instead")
          end

          body = response.read_body

          self.request_size = body.length
          self.request_hash = Digest::SHA1.hexdigest(body)

          types = response.header["content-type"].split("; ")

          # Using a wildcard somewhere
          if types.first == "multipart/parallel" and types[1] =~ /boundary=(.+)/
            parts = body.split("--#{$1}\r\n")
            parts.last.gsub!("\r\n--#{$1}--", "")
            parts.each do |part|
              next if part == "\r\n"
              headers, content = part.strip.split("\r\n\r\n", 2)

              row = {:headers => {}, :content => content}
              headers.split("\r\n").each do |line|
                name, value = line.split(":", 2)
                next if !value or value == ""
                row[:headers][name] = value.strip
              end

              objects.push(row)
            end

          # Either text (error) or an image of some sorts, which is irrelevant for this
          else
            headers = {"Content-Type" => types.first}
            GET_OBJECT_DATA.each do |field, real_name|
              next if !response.header[field] or response.header[field] == ""
              headers[real_name] = response.header[field].strip
            end

            objects.push(:headers => headers, :content => body)
          end

        end

        # First object is text/xml, so it's an error
        if objects.length > 0 and objects.first[:headers]["Content-Type"] == "text/xml"
          doc = Nokogiri::XML(objects.first[:content]).at("//RETS")
          code, message = doc.attr("ReplyCode"), doc.attr("ReplyText")

          # 404 errors don't need a hard fail, anything else does
          if code == "20403"
            return []
          else
            raise RETS::ServerError.new("#{message} (Code #{code})")
          end
        end

        objects
      end

      ##
      # Searches the RETS server for data.
      #
      # @param [Hash] args
      #   * search_type - What you are searching on, typically *Property* or *Office*.
      #   * class - Class of data to find, varies depending on RETS implementation, typically anything from *1* to *ResidentialProperty*.
      #   * limit - Limit how many results are returned.
      #   * standard_names - Whether to use standard names for the column and the search.
      #   * query - What data to return, should be unescaped. CGI escaping is done automatically before sending it off.
      #   * read_timeout (Optional) - How many seconds to wait before giving up.
      #
      # @param [Proc] block
      #   Block the library should call anytime data is available for a piece of data. Called for every <DATA></DATA> group.
      #   * data (Hash) - Column name, value hash of the data returned from the server.
      #
      # @return
      #   Can raise {RETS::CapabilityNotFound} or {RETS::ServerError} exceptions if something goes wrong.
      def search(args, &block)
        unless @urls[:search]
          raise RETS::CapabilityNotFound.new("Cannot find URL for Search call")
        end

        @http.request(:url => @urls[:search], :read_timeout => args[:read_timeout], :params => {:Format => "COMPACT-DECODED", :SearchType => args[:search_type], :StandardNames => (args[:standard_names] && 1 || 0), :QueryType => "DMQL2", :Query => args[:query], :Class => args[:class], :Limit => args[:limit]}) do |response|
          stream = RETS::StreamHTTP.new(response)

          doc = Nokogiri::XML::SAX::Parser.new(RETS::Base::SAXSearch.new(block))
          doc.parse_io(stream)

          self.request_size = stream.size
          self.request_hash = stream.hash
        end
      end
    end
  end
end