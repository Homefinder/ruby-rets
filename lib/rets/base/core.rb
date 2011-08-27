require "nokogiri"

module RETS
  module Base
    class Core
      GET_OBJECT_DATA = {"object-id" => "Object-ID", "description" => "Description", "content-id" => "Content-ID"}
      attr_accessor :request_size, :request_hash

      def initialize(http, version, urls)
        @http = http
        @urls = urls
        @active_version = version
      end

      def logout
        return unless @urls[:logout]
        @http.request(:url => @urls[:logout], :skip_auth => true)
      end

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

      def search(args, &block)
        unless @urls[:search]
          raise RETS::CapabilityNotFound.new("Cannot find URL for Search call")
        end

        @http.request(:url => @urls[:search], :read_timeout => args[:read_timeout], :params => {:Format => "COMPACT-DECODED", :searchType => args[:search_type], :StandardNames => (args[:standard_names] && 1 || 0), :QueryType => "DMQL2", :Query => args[:query], :Class => args[:class]}) do |response|
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
