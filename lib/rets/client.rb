require "nokogiri"

module RETS
  class Client
    URL_KEYS = {:getobject => true, :login => true, :logout => true, :search => true, :getmetadata => true}

    ##
    # Attempts to login to a RETS server.
    # @param [Hash] args
    # @option args [String] :url Login URL for the RETS server
    # @option args [String] :username Username to authenticate with
    # @option args [String] :password Password to authenticate with
    # @option args [Symbol, Optional] :auth_mode When set to *:basic* will automatically use HTTP Basic authentication, skips a discovery request when initially connecting
    # @option args [Hash, Optional] :useragent Only necessary for User Agent authentication
    #   * :name [String, Optional] - Name to set the User-Agent to
    #   * :password [String, Optional] - Password to use for RETS-UA-Authorization
    #
    # @raise [ArgumentError]
    # @raise [RETS::APIError]
    # @raise [RETS::HTTPError]
    # @raise [RETS::Unauthorized]
    #
    # @return [RETS::Base::Core]
    def self.login(args)
      raise ArgumentError, "No URL passed" unless args[:url]

      urls = {:login => URI.parse(args[:url])}
      raise ArgumentError, "Invalid URL passed" unless urls[:login].is_a?(URI::HTTP)

      base_url = urls[:login].to_s
      base_url.gsub!(urls[:login].path, "") if urls[:login].path

      http = RETS::HTTP.new(args)
      http.request(:url => urls[:login]) do |response|
        doc = Nokogiri::XML(response.body)

        code = doc.xpath("//RETS").attr("ReplyCode").value
        unless code == "0"
          text = doc.xpath("//RETS").attr("ReplyText").value
          raise RETS::APIError.new("#{code}: #{text}", code, text)
        end

        doc.xpath("//RETS").first.content.split("\n").each do |row|
          key, value = row.split("=", 2)
          next unless key and value

          key, value = key.downcase.strip.to_sym, value.strip

          if URL_KEYS[key]
            # In case it's a relative path and doesn't include the domain
            value = "#{base_url}#{value}" unless value =~ /(http|www)/
            urls[key] = URI.parse(value)
          elsif key == :timeoutseconds
            http.auth_timeout = value.to_i
            http.auth_timer = Time.now.utc + http.auth_timeout
            http.login_uri = urls[:login]
          end
        end
      end

      RETS::Base::Core.new(http, urls)
    end
  end
end