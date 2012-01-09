require "nokogiri"

module RETS
  class Client
    URL_KEYS = {:getobject => true, :login => true, :logout => true, :search => true, :getmetadata => true}

    ##
    # Attempts to login to a RETS server.
    # @param [Hash] args
    #   * url - Login URL for the RETS server
    #   * username - Username to pass for HTTP authentication
    #   * password - Password to pass for HTTP authentication
    #   * ua_auth (Optional) - Whether RETS-UA-Authorization needs to be passed, implied when using *ua_username* or *ua_password*
    #   * ua_username (Optional) - What to set the HTTP User-Agent header to. If *ua_auth* is set and this is nil, *username* is used
    #   * ua_password (Optional) - What password to use for RETS-UA-Authorization. If *ua_auth* is set and this is nil, *password* is used
    #   * user_agent (Optional) - Custom user agent, ignored when using user agent authentication.
    #
    # @return [RETS::Base::Core]
    #   Successful login will return a {RETS::Base::Core}. Otherwise it can raise a {RETS::InvalidRequest}, {RETS::InvalidResponse} or {RETS::ServerError} exception depending on why it was unable to login or make the request.
    def self.login(args)
      raise ArgumentError, "No URL passed" unless args[:url]

      @urls = {:login => URI.parse(args[:url])}
      raise RETS::InvalidRequest, "Invalid URL passed" unless @urls.is_a?(URI::HTTP)
      
      base_url = @urls[:login].to_s.gsub(@urls[:login].path, "")

      http = RETS::HTTP.new({:username => args[:username], :password => args[:password], :ua_auth => args[:ua_auth], :ua_username => args[:ua_username], :ua_password => args[:ua_password]}, args[:user_agent])
      http.request(:url => @urls[:login]) do |response|
        # Parse the response and figure out what capabilities we have
        unless response.code == "200"
          raise RETS::InvalidResponse.new("Expected HTTP 200, got #{response.code}")
        end

        doc = Nokogiri::XML(response.body)

        code = doc.xpath("//RETS").attr("ReplyCode").value
        unless code == "0"
          raise RETS::ServerError.new("#{doc.xpath("//RETS").attr("ReplyText").value} (ReplyCode #{code})")
        end

        doc.xpath("//RETS").first.content.split("\n").each do |row|
          ability, url = row.split("=", 2)
          next unless ability and url
          ability, url = ability.downcase.strip.to_sym, url.strip
          next unless URL_KEYS[ability]

          # In case it's a relative path and doesn't include the domain
          url = "#{base_url}#{url}" unless url =~ /(http|www)/
          @urls[ability] = URI.parse(url)
        end

        if response.header["rets-version"] =~ /RETS\/(.+)/i
          @rets_version = $1.to_f
        end
      end

      RETS::Base::Core.new(http, @rets_version, @urls)
    end
  end
end