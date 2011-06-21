require "cgi"
require "net/https"
require "nokogiri"
require "digest"

module RETS
  class HTTP
    def initialize(auth, user_agent=nil)
      @request_count = 1
      @headers = {"User-Agent" => (user_agent || "Ruby RETS/#{RETS::VERSION}")}
      @auth = auth
    end

    # Creates and manages the HTTP digest auth
    # if the WWW-Authorization header is passed, then it will overwrite what it knows about the auth data
    def create_digest(method, request_uri, header=nil)
      if header
        @request_count = 1
        @digest = {}

        header.split(", ").each do |line|
          k, v = line.split("=", 2)
          @digest[k] = (k != "algorithm" and k != "stale") && v[1..-2] || v
        end

        @digest["qop"] ||= "digest"
        @digest_type = @digest["qop"].split(",")
      end

      first = Digest::MD5.hexdigest("#{@auth[:username]}:#{@digest["realm"]}:#{@auth[:password]}")
      second = Digest::MD5.hexdigest("#{method}:#{request_uri}")
      cnonce = Digest::MD5.hexdigest("#{@headers["User-Agent"]}:#{@auth[:password]}:#{@request_count}:#{@digest["nonce"]}")

      if @digest_type.include?("auth")
        hash = Digest::MD5.hexdigest("#{first}:#{@digest["nonce"]}:#{"%08X" % @request_count}:#{cnonce}:#{@digest["qop"]}:#{second}")
      else
        raise RETS::UnsupportedAuth.new("Support for Digest mode #{@digest["qop"]} is not available yet.")
      end

      http_digest = "Digest username=\"#{@auth[:username]}\", "
      http_digest << "realm=\"#{@digest["realm"]}\", "
      http_digest << "nonce=\"#{@digest["nonce"]}\", "
      http_digest << "uri=\"#{request_uri}\", "
      http_digest << "algorithm=MD5, "
      http_digest << "response=\"#{hash}\", "
      http_digest << "opaque=\"#{@digest["opaque"]}\", "
      http_digest << "qop=\"#{@digest["qop"]}\", "
      http_digest << "nc=#{"%08X" % @request_count}, "
      http_digest << "cnonce=\"#{cnonce}\""

      http_digest
    end

    def create_basic
       "Basic " << "#{@auth[:username]}:#{@auth[:password]}".pack("m").delete("\r\n")
    end

    def query_string(args)
      (args.collect {|k, v| "#{k}=#{CGI::escape(v.to_s)}"}).join("&")
    end

    def request(args, &block)
      request_uri = "#{args[:url].request_uri}"
      request_uri << "?" << query_string(args[:params]) if args[:params]

      # Increment request count for digest auth
      @request_count += 1

      # Figure out auth if any
      args[:headers] ||= {}
      args[:headers].merge!(@headers)

      if @auth_mode == :digest
        args[:headers].merge!("Authorization" => create_digest("GET", request_uri))
      elsif @auth_mode == :basic
        args[:headers].merge!("Authorization" => create_basic)
      end

      http = ::Net::HTTP.new(args[:url].host, args[:url].port)
      http.read_timeout = args[:read_timeout] if args[:read_timeout]

#      if args[:url].scheme == "https"
#        http.use_ssl = true
#        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
#      end

      resend_request = nil

      http.start do
        http.request_get(request_uri, args[:headers]) do |response|
          if response.code == "401" and !args[:skip_auth]
            @auth_mode = nil

            # We're already trying to auth, and we still get an invalid auth, can call it a bust and raise
            raise RETS::InvalidAuth.new("Failed to login") if args[:authing]
            raise RETS::UnsupportedAuth.new("Unknown authentication method used") unless response.header["WWW-Authenticate"]

            mode, header = response.header["WWW-Authenticate"].split(" ", 2)
            raise RETS::UnsupportedAuth.new("Unknown HTTP Auth, not digest or basic") unless mode == "Digest" or mode == "Basic"

            args[:authing] = true

            if mode == "Digest"
              args[:headers].merge!("Authorization" => create_digest("GET", request_uri, header))
            elsif mode == "Basic"
              args[:headers].merge!("Authorization" => create_basic)
            end

            # Resend the request with the authorization, if it still fails it'll just throw another exception that will bubble up
            # If the request succeeds, we save that auth mode and will use it on any future requests
            @auth_mode = mode.downcase.to_sym
            resend_request = true

          # We just tried to auth, so call the block manually
          elsif args[:authing]
            # Save the cookie if any
            if response.header["set-cookie"]
              @headers.merge!("Cookie" => response.header["set-cookie"].split("; ").first)
            end

            args[:block].call(response)

          # Actual block, call as is
          elsif block_given?
            yield response
          end
        end
      end

      # Auth failed, resend request
      if resend_request
        args[:block] = block
        self.request(args)
      end
    end
  end
end