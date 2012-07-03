require "net/https"
require "digest"

module RETS
  class HTTP
    attr_accessor :login_uri

    ##
    # Creates a new HTTP instance which will automatically handle authenting to the RETS server.
    def initialize(args)
      @headers = {"User-Agent" => "Ruby RETS/v#{RETS::VERSION}"}
      @request_count = 0
      @config = {:http => {}}.merge(args)
      @rets_data, @cookie_list = {}, {}

      if @config[:useragent] and @config[:useragent][:name]
        @headers["User-Agent"] = @config[:useragent][:name]
      end

      if @config[:rets_version]
        @rets_data[:version] = @config[:rets_version]
        self.setup_ua_authorization(:version => @config[:rets_version])
      end

      if @config[:auth_mode] == :basic
        @auth_mode = @config.delete(:auth_mode)
      end
    end

    def url_encode(str)
      encoded_string = ""
      str.each_char do |char|
        case char
        when "+"
          encoded_string << "%2b"
        when "="
          encoded_string << "%3d"
        when "?"
          encoded_string << "%3f"
        when "&"
          encoded_string << "%26"
        when "%"
          encoded_string << "%25"
        when ","
          encoded_string << "%2C"
        else
          encoded_string << char
        end
      end
      encoded_string
    end

    def get_digest(header)
      return unless header

      header.each do |text|
        mode, text = text.split(" ", 2)
        return text if mode == "Digest"
      end

      nil
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

      @digest_type = @digest["qop"] ? @digest["qop"].split(",") : []
    end

    ##
    # Creates a HTTP digest header.
    def create_digest(method, request_uri)
      # http://en.wikipedia.org/wiki/Digest_access_authentication
      first = Digest::MD5.hexdigest("#{@config[:username]}:#{@digest["realm"]}:#{@config[:password]}")
      second = Digest::MD5.hexdigest("#{method}:#{request_uri}")

      # Using the "newer" authentication QOP
      if @digest_type.include?("auth")
        cnonce = Digest::MD5.hexdigest("#{@headers["User-Agent"]}:#{@config[:password]}:#{@request_count}:#{@digest["nonce"]}")
        hash = Digest::MD5.hexdigest("#{first}:#{@digest["nonce"]}:#{"%08X" % @request_count}:#{cnonce}:#{@digest["qop"]}:#{second}")
      # Nothing specified, so default to the old one
      elsif @digest_type.empty?
        hash = Digest::MD5.hexdigest("#{first}:#{@digest["nonce"]}:#{second}")
      else
        raise RETS::HTTPError, "Cannot determine auth type for server (#{@digest_type.join(",")})"
      end

      http_digest = "Digest username=\"#{@config[:username]}\", "
      http_digest << "realm=\"#{@digest["realm"]}\", "
      http_digest << "nonce=\"#{@digest["nonce"]}\", "
      http_digest << "uri=\"#{request_uri}\", "
      http_digest << "algorithm=MD5, " unless @digest_type.empty?
      http_digest << "response=\"#{hash}\", "
      http_digest << "opaque=\"#{@digest["opaque"]}\""

      unless @digest_type.empty?
        http_digest << ", "
        http_digest << "qop=\"#{@digest["qop"]}\", "
        http_digest << "nc=#{"%08X" % @request_count}, "
        http_digest << "cnonce=\"#{cnonce}\""
      end

      http_digest
    end

    ##
    # Creates a HTTP basic header.
    def create_basic
       "Basic " << ["#{@config[:username]}:#{@config[:password]}"].pack("m").delete("\r\n")
    end

    ##
    # Finds the ReplyText and ReplyCode attributes in the response
    #
    # @param [Nokogiri::XML::NodeSet] rets <RETS> attributes found
    #
    # @return [String] RETS ReplyCode
    # @return [String] RETS ReplyText
    def get_rets_response(rets)
      code, text = nil, nil
      rets.attributes.each do |attr|
        key = attr.first.downcase
        if key == "replycode"
          code = attr.last.value
        elsif key == "replytext"
          text = attr.last.value
        end
      end

      return code, text
    end

    ##
    # Handles managing the relevant RETS-UA-Authorization headers
    #
    # @param [Hash] args
    # @option args [String] :version RETS Version
    # @option args [String, Optional] :session_id RETS Session ID
    def setup_ua_authorization(args)
      # Most RETS implementations don't care about RETS-Version for RETS-UA-Authorization.
      # Because Rapattoni's does, will set and use it when possible, but otherwise will fake one.
      # They also seem to require RETS-Version even when it's not required by RETS-UA-Authorization.
      # Others, such as Offut/Innovia pass the header, but without a version attached.
      @headers["RETS-Version"] = args[:version]

      if @headers["RETS-Version"] and @config[:useragent] and @config[:useragent][:password]
        login = Digest::MD5.hexdigest("#{@config[:useragent][:name]}:#{@config[:useragent][:password]}")
        @headers.merge!("RETS-UA-Authorization" => "Digest #{Digest::MD5.hexdigest("#{login}::#{args[:session_id]}:#{@headers["RETS-Version"]}")}")
      end
    end

    ##
    # Sends a request to the RETS server.
    #
    # @param [Hash] args
    # @option args [URI] :url URI to request data from
    # @option args [Hash, Optional] :params Query string to include with the request
    # @option args [Integer, Optional] :read_timeout How long to wait for the socket to return data before timing out
    #
    # @raise [RETS::APIError]
    # @raise [RETS::HTTPError]
    # @raise [RETS::Unauthorized]
    def request(args, &block)
      if args[:params]
        url_terminator = (args[:url].request_uri.include?("?")) ? "&" : "?"
        request_uri = "#{args[:url].request_uri}#{url_terminator}"
        args[:params].each do |k, v|
          request_uri << "#{k}=#{url_encode(v.to_s)}&" if v
        end
      else
        request_uri = args[:url].request_uri
      end

      headers = args[:headers]

      # Digest will change every time due to how its setup
      @request_count += 1
      if @auth_mode == :digest
        if headers
          headers["Authorization"] = create_digest("GET", request_uri)
        else
          headers = {"Authorization" => create_digest("GET", request_uri)}
        end
      end

      headers = headers ? @headers.merge(headers) : @headers

      if @config[:proxy]
        http = ::Net::HTTP.new(args[:url].host, args[:url].port, @config[:proxy].host, @config[:proxy].port, @config[:proxy].user, @config[:proxy].password)
      else
        http = ::Net::HTTP.new(args[:url].host, args[:url].port)
      end
      
      http.read_timeout = args[:read_timeout] if args[:read_timeout]
      http.set_debug_output(@config[:debug_output]) if @config[:debug_output]

      if args[:url].scheme == "https"
        http.use_ssl = true
        http.verify_mode = @config[:http][:verify_mode] || OpenSSL::SSL::VERIFY_NONE
        http.ca_file = @config[:http][:ca_file] if @config[:http][:ca_file]
        http.ca_path = @config[:http][:ca_path] if @config[:http][:ca_path]
      end

      http.start do
        http.request_get(request_uri, headers) do |response|
          # Pass along the cookies
          # Some servers will continually call Set-Cookie with the same value for every single request
          # to avoid authentication problems from cookies being stomped over (which is sad, nobody likes having their cookies crushed).
          # We keep a hash of every cookie set and only update it if something changed
          if response.header["set-cookie"]
            cookies_changed = nil

            response.header.get_fields("set-cookie").each do |cookie|
              key, value = cookie.split(";").first.split("=")
              key.strip!
              value.strip!

              # If it's a RETS-Session-ID, it needs to be shoved into the RETS-UA-Authorization field
              # Save the RETS-Session-ID so it can be used with RETS-UA-Authorization
              if key.downcase == "rets-session-id"
                @rets_data[:session_id] = value
                self.setup_ua_authorization(@rets_data) if @rets_data[:version]
              end

              cookies_changed = true if @cookie_list[key] != value
              @cookie_list[key] = value
            end

            if cookies_changed
              @headers.merge!("Cookie" => @cookie_list.map {|k, v| "#{k}=#{v}"}.join("; "))
            end
          end

          # Rather than returning HTTP 401 when User-Agent authentication is needed, Retsiq returns HTTP 200
          # with RETS error 20037. If we get a 20037, will let it pass through and handle it as if it was a HTTP 401.
          rets_code = nil
          if response.code != "401" and ( response.code != "200" or args[:check_response] )
            if response.body =~ /<RETS/i
              rets_code, text = self.get_rets_response(Nokogiri::XML(response.body).xpath("//RETS").first)
              unless rets_code == "20037" or rets_code == "0"
                raise RETS::APIError.new("#{rets_code}: #{text}", rets_code, text)
              end

            elsif !args[:check_response]
              raise RETS::HTTPError.new("#{response.code}: #{response.message}", response.code, response.message)
            end
          end

          # Digest can become stale requiring us to reload data
          if @auth_mode == :digest and response.header["www-authenticate"] =~ /stale=\\?"?true/i
            save_digest(get_digest(response.header.get_fields("www-authenticate")))

            args[:block] ||= block
            return self.request(args)

          elsif response.code == "401" or rets_code == "20037"
            raise RETS::Unauthorized, "Cannot login, check credentials" if ( @auth_mode and @retried_request ) or ( @retried_request and rets_code == "20037" )
            @retried_request = true

            # We already have an auth mode, and the request wasn't retried.
            # Meaning we know that we had a successful authentication but something happened so we should relogin.
            if @auth_mode
              @headers.delete("Cookie")
              @cookie_list = {}

              self.request(:url => login_uri)
              return self.request(args.merge(:block => block))
            end

            # Find a valid way of authenticating to the server as some will support multiple methods
            if response.header.get_fields("www-authenticate") and !response.header.get_fields("www-authenticate").empty?
              digest = get_digest(response.header.get_fields("www-authenticate"))
              if digest
                save_digest(digest)
                @auth_mode = :digest
              else
                @headers.merge!("Authorization" => create_basic)
                @auth_mode = :basic
              end

              unless @auth_mode
                raise RETS::HTTPError.new("Cannot authenticate, no known mode found", response.code)
              end
            end

            # Check if we need to deal with User-Agent authorization
            if response.header["rets-version"] and response.header["rets-version"] != ""
              @rets_data[:version] = response.header["rets-version"]
            else
              @rets_data[:version] = "RETS/1.7"
            end

            self.setup_ua_authorization(@rets_data)

            args[:block] ||= block
            return self.request(args)

          # We just tried to auth and don't have access to the original block in yieldable form
          elsif args[:block]
            @retried_request = nil
            args.delete(:block).call(response)

          elsif block_given?
            @retried_request = nil
            yield response
          end
        end
      end
    end
  end
end
