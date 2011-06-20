require "nokogiri"

module RETS
  class Client
    def self.login(args)
      @urls = {:Login => URI.parse(args[:url])}

      http = RETS::HTTP.new({:username => args[:username], :password => args[:password]}, args[:user_agent])
      http.request(:url => @urls[:Login]) do |response|
        # Parse the response and figure out what capabilities we have
        unless response.code == "200"
          raise RETS::InvalidResponse.new("Expected HTTP 200, got #{response.code}")
        end

        doc = Nokogiri::XML(response.body)

        code = doc.xpath("//RETS").attr("ReplyCode").value
        unless code == "0"
          raise RETS::InvalidResponse.new("Expected RETS ReplyCode 0, got #{code}")
        end

        doc.xpath("//RETS/RETS-RESPONSE").first.children.first.content.split("\n").each do |row|
          ability, url = row.split(" = ", 2)
          next unless url =~ /^(http|www)/
          @urls[ability.to_sym] = URI.parse(url)
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