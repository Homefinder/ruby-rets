require "nokogiri"

module RETS
  class Client
    URL_KEYS = {:getobject => true, :login => true, :logout => true, :search => true, :getmetadata => true}

    def self.login(args)
      @urls = {:login => URI.parse(args[:url])}
      base_url = @urls[:login].to_s.gsub(@urls[:login].path, "")

      http = RETS::HTTP.new({:username => args[:username], :password => args[:password]}, args[:user_agent])
      http.request(:url => @urls[:login]) do |response|
        # Parse the response and figure out what capabilities we have
        unless response.code == "200"
          raise RETS::InvalidResponse.new("Expected HTTP 200, got #{response.code}")
        end

        doc = Nokogiri::XML(response.body)

        code = doc.xpath("//RETS").attr("ReplyCode").value
        unless code == "0"
          raise RETS::InvalidResponse.new("Expected RETS ReplyCode 0, got #{code}")
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
        else
          raise RETS::InvalidResponse.new("Cannot find RETS-Version header.")
        end
      end

      begin
        model = RETS.const_get("V#{@rets_version.gsub(".", "")}::Core")
      rescue NameError => e
        model = RETS::Base::Core
      end

      model.new(http, @rets_version, @urls)
    end
  end
end