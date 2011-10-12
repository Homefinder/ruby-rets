require "cgi"
require "net/https"
require "nokogiri"
require "digest"

module RETS
  class HTTP
    ##
    # Creates a new HTTP instance which will automatically handle authenting to the RETS server.
    def initialize(auth, user_agent=nil)
      @request_count = 1
      @headers = {"User-Agent" => (user_agent || "Ruby RETS/v#{RETS::VERSION}")}
      @auth = auth
    end

    ##
    # Creates and manages the HTTP digest auth
    # if the WWW-Authorization header is passed, then it will overwrite what it knows about the auth data.
    def save_digest(header)
      @request_count = 0
      @digest = {}

      header.split(",").each do |line|
        k, v = line.strip.split("=", 2)
        @digest[k] = (k != "algorithm" and k != "stale") && v[1..-2] || v
      end

      @digest["qop"] ||= "auth"
      @digest_type = @digest["qop"].split(",")
    end

    ##
    # Creates a HTTP digest header.
    def create_digest(method, request_uri)
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

    ##
    # Creates a HTTP basic header.
    def create_basic
       "Basic " << ["#{@auth[:username]}:#{@auth[:password]}"].pack("m").delete("\r\n")
    end

    ##
    # Takes a hash and turns it into an escaped query string.
    def query_string(args)
      (args.collect {|k, v| "#{k}=#{CGI::escape(v.to_s)}"}).join("&")
    end

    ##
    # sends a request to the RETS server.
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
      # From the Interealty implementation at least, RETS-Version is really just an unverified field to "salt" the UA-Auth header.
      # Will just make up a version and let it do the rest when it's flagged as requiring UA Auth. Might make it auto detect in the future.
      elsif @auth[:ua_auth] or @auth[:ua_username] or @auth[:ua_password]
        @auth_mode = :basic

        args[:authing] = true
        args[:block] = block
        args[:headers].merge!(
          "Authorization" => create_basic,
          "User-Agent" => @auth[:ua_username] || @auth[:username],
          "RETS-UA-Authorization" => "Digest #{Digest::MD5.hexdigest("#{Digest::MD5.hexdigest("#{@auth[:ua_username] || @auth[:username]}:#{@auth[:ua_password] || @auth[:password]}")}:::1.7")}",
          "RETS-Version" => "1.7")
      end

      http = ::Net::HTTP.new(args[:url].host, args[:url].port)
      http.read_timeout = args[:read_timeout] if args[:read_timeout]

      resend_request = nil

      http.start do
        http.request_get(request_uri, args[:headers]) do |response|
          # We already authed, and the request became stale so we have to switch to the new auth
          if @auth_mode == :digest and response.header["www-authenticate"] =~ /stale=true/i
            mode, header = response.header["www-authenticate"].split(" ", 2)

            save_digest(header)

            @headers.delete("Cookie")
            args[:authing] = true
            resend_request = true

          # Invalid auth
          elsif response.code == "401" and !args[:skip_auth]
            @auth_mode = nil

            # We're already trying to auth, and we still get an invalid auth, can call it a bust and raise
            raise RETS::InvalidAuth.new("Failed to login") if args[:authing]
            raise RETS::UnsupportedAuth.new("Unknown authentication method used") unless response.header["www-authenticate"]

            mode, header = response.header["www-authenticate"].split(" ", 2)
            raise RETS::UnsupportedAuth.new("Unknown HTTP Auth, not digest or basic") unless mode == "Digest" or mode == "Basic"

            args[:authing] = true
            save_digest(header)

            # Resend the request with the authorization, if it still fails it'll just throw another exception that will bubble up
            # If the request succeeds, we save that auth mode and will use it on any future requests
            @auth_mode = mode.downcase.to_sym
            resend_request = true

          # We just tried to auth, so call the block manually
          elsif args[:authing]
            if response.header["set-cookie"]
              cookies = response.header["set-cookie"].split(",").map do |cookie|
                cookie.split(";").first.strip
              end

              @headers.merge!("Cookie" => cookies.join("; "))
            end

            args[:block].call(response) if args[:block]

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