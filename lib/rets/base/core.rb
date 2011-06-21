require "nokogiri"

module RETS
  module Base
    class Core
      GET_OBJECT_DATA = {"object-id" => "Object-ID", "description" => "Description", "content-id" => "Content-ID"}

      def initialize(http, version, urls)
        @http = http
        @urls = urls
        @active_version = version
      end

      def logout
        return unless @urls[:Logout]
        @http.request(:url => @urls[:Logout], :skip_auth => true)
      end

      def get_object(args)
        unless @urls[:GetObject]
          raise RETS::CapabilityNotFound.new("Cannot find URL for GetObject call")
        end

        headers = {"Accept" => "image/png,image/gif,image/jpeg"}

        objects = []
        @http.request(:url => @urls[:GetObject], :headers => headers, :params => {:Resource => args[:resource], :Type => args[:type], :Location => (args[:location] ? 1 : 0), :ID => args[:id]}) do |response|
          unless response.code == "200"
            raise RETS::InvalidResponse.new("Tried to retrieve object, got #{response.message} (#{response.code}) instead")
          end

          body = response.read_body

          types = response.header["content-type"].split("; ")

          # Using a wildcard somewhere
          if types.first == "multipart/parallel" and types[1] =~ /boundary=(.+)/
            body.scan(/--#{$1}\r\n(.+)\r\n(.+)\r\n--#{$1}--/m).each do |headers, data|
              row = {:headers => {}, :data => data}
              headers.split("\r\n").each do |line|
                name, value = line.split(":", 2)
                row[:headers][name] = value.strip
              end

              objects.push(row)
            end

          # Either text (error) or an image of some sorts, which is irrelevant for this
          else
            headers = {"Content-Type" => types.first}
            GET_OBJECT_DATA.each do |field, real_name|
              next if !response.header[field] or response.header[field] == ""
              headers[real_name] = response.header[field]
            end

            objects.push(:headers => headers, :content => body)
          end

        end

        # First object is text/xml, so it's an error
        if objects.first[:headers]["Content-Type"] == "text/xml"
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
        unless @urls[:Search]
          raise RETS::CapabilityNotFound.new("Cannot find URL for Search call")
        end

        @http.request(:url => @urls[:Search], :params => {:Format => "COMPACT-DECODED", :SearchType => args[:search_type], :StandardNames => 1, :QueryType => "DMQL2", :Query => args[:filter], :Class => args[:class]}) do |response|
          doc = Nokogiri::XML::SAX::Parser.new(RETS::Base::SAXSearch.new(block))
          doc.parse_io(RETS::StreamHTTP.new(response))
        end
      end
    end
  end
end