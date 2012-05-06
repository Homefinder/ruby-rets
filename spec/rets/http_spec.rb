require "spec_helper"

describe RETS::HTTP do
  it "switches to SSL based on URL" do
    uri = URI("https://foobar.com/login/login.bar")

    http_mock = mock("HTTP")
    http_mock.should_receive(:use_ssl=).with(true)
    http_mock.should_receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
    http_mock.should_receive(:ca_file=).with("/foo/bar/ca.pem")
    http_mock.should_receive(:ca_path=).with("/foo/bar")
    http_mock.should_receive(:start)

    Net::HTTP.should_receive(:new).and_return(http_mock)

    http = RETS::HTTP.new({:http => {:ca_file => "/foo/bar/ca.pem", :ca_path => "/foo/bar", :verify_mode => OpenSSL::SSL::VERIFY_PEER}})
    http.request(:url => uri)
  end

  context "HTTP authentication" do
    it "parses the digest header" do
        http = RETS::HTTP.new({})

        # Some servers return with spaces after each comma, others don't
        http.save_digest('realm="Foo Bar",nonce="4e3b90a132bd197a1319bdf4fc7371bf",opaque="4805755a42ac82d4837fb50a7d3babeb",qop="auth"')
        http.instance_variable_get(:@digest_type).should == ["auth"]
        digest = http.instance_variable_get(:@digest)
        digest["realm"].should == "Foo Bar"
        digest["nonce"].should == "4e3b90a132bd197a1319bdf4fc7371bf"
        digest["opaque"].should == "4805755a42ac82d4837fb50a7d3babeb"
        digest["qop"].should == "auth"

        http.save_digest('realm="Foo Bar",nonce="7d8ca69b352016f88d7c3d8a040dc9e0",opaque="431d3681382c9550ffc0525839a37aa3",qop="auth"')
        http.instance_variable_get(:@digest_type).should == ["auth"]
        digest = http.instance_variable_get(:@digest)
        digest["realm"].should == "Foo Bar"
        digest["nonce"].should == "7d8ca69b352016f88d7c3d8a040dc9e0"
        digest["opaque"].should == "431d3681382c9550ffc0525839a37aa3"
        digest["qop"].should == "auth"
    end

    it "creates a digest header" do
      http = RETS::HTTP.new(:username => "foo", :password => "bar", :useragent => {:name => "FooBar"})
      http.save_digest('realm="Foo Bar",nonce="7d8ca69b352016f88d7c3d8a040dc9e0",opaque="431d3681382c9550ffc0525839a37aa3",qop="auth"')

      digest = http.create_digest("GET", "/foo/bar?a=b&c=d")
      digest.should == 'Digest username="foo", realm="Foo Bar", nonce="7d8ca69b352016f88d7c3d8a040dc9e0", uri="/foo/bar?a=b&c=d", algorithm=MD5, response="c9cfe27cc343e0b18bc857529510a76d", opaque="431d3681382c9550ffc0525839a37aa3", qop="auth", nc=00000000, cnonce="8a1f541c678feb35a19c8802ffd0c173"'
    end

    it "creates a basic header" do
      http = RETS::HTTP.new(:username => "foo", :password => "bar")

      basic = http.create_basic
      basic.should == "Basic Zm9vOmJhcg=="
    end
  end

  context "authentication discovery" do
    it "finds basic auth" do
      uri = URI("http://foobar.com/login/login.bar")

      # The initial response while it's figuring out what authentication is
      header_mock = mock("Header")
      header_mock.stub(:get_fields).with("www-authenticate").and_return(['Basic realm="Foo Bar"'])
      header_mock.stub(:[]).and_return(nil)

      res_mock = mock("Response")
      res_mock.stub(:code).and_return("401")
      res_mock.stub(:header).and_return(header_mock)

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, {"User-Agent" => "FooBar"}).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)

      # Second request made after it figure out everything
      res_mock = mock("Response")
      res_mock.stub(:body).and_return("Foo Bar")
      res_mock.stub(:code).and_return("200")
      res_mock.stub(:header).and_return({})
      res_mock.should_receive(:test).with("Foo Bar")

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, hash_including("User-Agent" => "FooBar", "Authorization" => "Basic Zm9vOmJhcg==")).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)

      # There's no easy way of checking if a yield or proc was called, so will just fake it by calling a stub with should_receive
      http = RETS::HTTP.new(:username => "foo", :password => "bar", :useragent => {:name => "FooBar"})
      http.request(:url => uri) {|r| r.test(r.body)}
    end

    it "finds digest auth" do
      uri = URI("http://foobar.com/login/login.bar")

      # The initial response while it's figuring out what authentication is
      header_mock = mock("Header")
      header_mock.stub(:get_fields).with("www-authenticate").and_return(['Basic Zm9vOmJhcg==', 'Digest realm="Foo Bar",nonce="7d8ca69b352016f88d7c3d8a040dc9e0",opaque="431d3681382c9550ffc0525839a37aa3",qop="auth"'])
      header_mock.stub(:[]).with("rets-version").and_return("RETS/1.8")
      header_mock.stub(:[]).with("set-cookie").and_return(nil)

      res_mock = mock("Response")
      res_mock.stub(:code).and_return("401")
      res_mock.stub(:header).and_return(header_mock)

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, {"User-Agent" => "FooBar"}).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)

      # Second request made after it figure out everything
      res_mock = mock("Response")
      res_mock.stub(:body).and_return("Foo Bar")
      res_mock.stub(:code).and_return("200")
      res_mock.stub(:header).and_return({})
      res_mock.should_receive(:test).with("Foo Bar")

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, hash_including("User-Agent" => "FooBar", "RETS-Version" => "RETS/1.8", "Authorization" => 'Digest username="foo", realm="Foo Bar", nonce="7d8ca69b352016f88d7c3d8a040dc9e0", uri="/login/login.bar", algorithm=MD5, response="f08d9e44c4c45c47da3d676ce686754b", opaque="431d3681382c9550ffc0525839a37aa3", qop="auth", nc=00000001, cnonce="d5f19e5717bda6762e373e9c9be24e7b"')).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)

      # There's no easy way of checking if a yield or proc was called, so will just fake it by calling a stub with should_receive
      http = RETS::HTTP.new(:username => "foo", :password => "bar", :useragent => {:name => "FooBar"})
      http.request(:url => uri) {|r| r.test(r.body)}
    end

    it "uses RETS-UA-Authorization" do
      uri = URI("http://foobar.com/login/login.bar")

      # The initial response while it's figuring out what authentication is
      header_mock = mock("Header")
      header_mock.stub(:get_fields).with("www-authenticate").and_return([])
      header_mock.stub(:[]).with("rets-version").and_return("RETS/1.8")
      header_mock.stub(:[]).with("set-cookie").and_return(nil)

      res_mock = mock("Response")
      res_mock.stub(:code).and_return("401")
      res_mock.stub(:header).and_return(header_mock)

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, {"User-Agent" => "FooBar"}).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)

      # Second request made after it figure out everything
      res_mock = mock("Response")
      res_mock.stub(:body).and_return("Foo Bar")
      res_mock.stub(:code).and_return("200")
      res_mock.stub(:header).and_return({})
      res_mock.should_receive(:test).with("Foo Bar")

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, hash_including("User-Agent" => "FooBar", "RETS-Version" => "RETS/1.8", "RETS-UA-Authorization" => "Digest aaeef7c65ff28b5b475acb42e66268f8")).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)

      # There's no easy way of checking if a yield or proc was called, so will just fake it by calling a stub with should_receive
      http = RETS::HTTP.new(:username => "foo", :password => "bar", :useragent => {:name => "FooBar", :password => "foo"})
      http.request(:url => uri) {|r| r.test(r.body)}
    end

    it "uses RETS-UA-Authorization after HTTP 200 with RETS ReplyCode 20037" do
      uri = URI("http://foobar.com/login/login.bar")

      # The initial response while it's figuring out what authentication is
      header_mock = mock("Header")
      header_mock.stub(:get_fields).with("set-cookie").and_return(["RETS-Session-ID=4f220ee66794dc9281000002; path=/"])
      header_mock.stub(:get_fields).with("www-authenticate").and_return([])
      header_mock.stub(:[]).with("rets-version").and_return("RETS/1.8")
      header_mock.stub(:[]).with("set-cookie").and_return("RETS-Session-ID=4f220ee66794dc9281000002; path=/")

      res_mock = mock("Response")
      res_mock.stub(:code).and_return("200")
      res_mock.stub(:body).and_return('<RETS ReplyCode="20037" replytext="Failure message goes here."></RETS>')
      res_mock.stub(:header).and_return(header_mock)

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, {"User-Agent" => "FooBar"}).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)

      # Second one where the request still fails because it also needs WWW-Authenticaet which wasn't passed originally
      header_mock = mock("Header")
      header_mock.stub(:get_fields).with("www-authenticate").and_return(['Digest realm="Foo Bar",nonce="7d8ca69b352016f88d7c3d8a040dc9e0",opaque="431d3681382c9550ffc0525839a37aa3",qop="auth"'])
      header_mock.stub(:[]).with("set-cookie").and_return(nil)
      header_mock.stub(:[]).with("rets-version").and_return("RETS/1.8")

      res_mock = mock("Response")
      res_mock.stub(:code).and_return("401")
      res_mock.stub(:header).and_return(header_mock)

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, hash_including("User-Agent" => "FooBar", "RETS-Version" => "RETS/1.8", "RETS-UA-Authorization" => "Digest 3f56217348ed45a08e8669ed2a37c8da")).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)

      # Third request which was fine
      res_mock = mock("Response")
      res_mock.stub(:code).and_return("200")
      res_mock.stub(:body).and_return('<RETS ReplyCode="0" replytext="Success message goes here."></RETS>')
      res_mock.stub(:header).and_return({})
      res_mock.should_receive(:test).with('<RETS ReplyCode="0" replytext="Success message goes here."></RETS>')

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, hash_including("User-Agent" => "FooBar", "RETS-Version" => "RETS/1.8", "RETS-UA-Authorization" => "Digest 3f56217348ed45a08e8669ed2a37c8da")).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)

      # There's no easy way of checking if a yield or proc was called, so will just fake it by calling a stub with should_receive
      http = RETS::HTTP.new(:username => "foo", :password => "bar", :useragent => {:name => "FooBar", :password => "foo"})
      http.request(:url => uri, :check_response => true) {|r| r.test(r.body)}

      rets_data = http.instance_variable_get(:@rets_data)
      rets_data[:session_id].should == "4f220ee66794dc9281000002"
    end

    it "won't infinite loop on continous RETS ReplyCode 20037 with HTTP 200" do
      uri = URI("http://foobar.com/login/login.bar")

      # The initial response while it's figuring out what authentication is
      header_mock = mock("Header")
      header_mock.stub(:get_fields).with("set-cookie").and_return([])
      header_mock.stub(:get_fields).with("www-authenticate").and_return([])
      header_mock.stub(:[]).with("rets-version").and_return(nil)
      header_mock.stub(:[]).with("set-cookie").and_return(nil)

      res_mock = mock("Response")
      res_mock.stub(:code).and_return("200")
      res_mock.stub(:body).and_return('<RETS ReplyCode="20037" replytext="Failure message goes here."></RETS>')
      res_mock.stub(:header).and_return(header_mock)

      http_mock = mock("HTTP1")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, hash_including({"User-Agent" => "FooBar"})).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)

      # Second response where it still fails
      header_mock = mock("Header")
      header_mock.stub(:get_fields).with("set-cookie").and_return([])
      header_mock.stub(:get_fields).with("www-authenticate").and_return([])
      header_mock.stub(:[]).with("rets-version").and_return(nil)
      header_mock.stub(:[]).with("set-cookie").and_return(nil)

      res_mock = mock("Response")
      res_mock.stub(:code).and_return("200")
      res_mock.stub(:body).and_return('<RETS ReplyCode="20037" replytext="Failure message goes here."></RETS>')
      res_mock.stub(:header).and_return(header_mock)

      http_mock = mock("HTTP2")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, {"User-Agent" => "FooBar",  "RETS-Version" => "RETS/1.7", "RETS-UA-Authorization" => "Digest d2469c44dd4b56a1b9021ea481ec0e70"}).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)

      # Off we go
      http = RETS::HTTP.new(:username => "foo", :password => "bar", :useragent => {:name => "FooBar", :password => "foo"})

      lambda { http.request(:url => uri, :check_response => true) }.should raise_error(RETS::Unauthorized)
    end
  end

  it "handles cookie storing and passing" do
    uri = URI("http://foobar.com/login/login.bar")

    cookies = ["ASP.NET_SessionId=4f220ee66794dc9281000001; path=/; HttpOnly", "RETS-Session-ID=4f220ee66794dc9281000002; path=/"]

    header_mock = mock("Header")
    header_mock.stub(:get_fields).with("set-cookie").and_return(cookies)
    header_mock.stub(:[]).with("set-cookie").and_return(cookies.join(", "))

    res_mock = mock("Response")
    res_mock.stub(:code).and_return("200")
    res_mock.stub(:header).and_return(header_mock)
    res_mock.stub(:body).and_return("Foo Bar")
    res_mock.should_receive(:test).with("Foo Bar")

    http_mock = mock("HTTP")
    http_mock.should_receive(:start).and_yield
    http_mock.should_receive(:request_get).with(uri.request_uri, anything).and_yield(res_mock)

    Net::HTTP.should_receive(:new).and_return(http_mock)

    # There's no easy way of checking if a yield or proc was called, so will just fake it by calling a stub with should_receive
    http = RETS::HTTP.new(:username => "foo", :password => "bar")
    http.request(:url => uri) {|r| r.test(r.body)}

    cookies = http.instance_variable_get(:@cookie_list)
    cookies["RETS-Session-ID"].should == "4f220ee66794dc9281000002"
    cookies["ASP.NET_SessionId"].should == "4f220ee66794dc9281000001"

    headers = http.instance_variable_get(:@headers)
    headers["Cookie"].should =~ /RETS-Session-ID=4f220ee66794dc9281000002/
    headers["Cookie"].should =~ /ASP.NET_SessionId=4f220ee66794dc9281000001/

    rets_data = http.instance_variable_get(:@rets_data)
    rets_data[:session_id].should == "4f220ee66794dc9281000002"
  end

  it "adds cookies if Set-Cookie is called multiple times" do
    uri = URI("http://foobar.com/login/login.bar")

    # First call
    [["ASP.NET_SessionId=4f220ee66794dc9281000001; path=/; HttpOnly", "RETS-Session-ID=4f220ee66794dc9281000002; path=/"], ["RETS-Session-ID=foobar; path=/", "SERVERID=w613; path=/"]].each do |cookies|
      header_mock = mock("Header")
      header_mock.stub(:get_fields).with("set-cookie").and_return(cookies)
      header_mock.stub(:[]).with("set-cookie").and_return(cookies.join(", "))

      res_mock = mock("Response")
      res_mock.stub(:code).and_return("200")
      res_mock.stub(:header).and_return(header_mock)
      res_mock.should_receive(:test)

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, anything).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)
    end

    # There's no easy way of checking if a yield or proc was called, so will just fake it by calling a stub with should_receive
    http = RETS::HTTP.new(:username => "foo", :password => "bar")
    http.request(:url => uri) {|r| r.test}
    http.request(:url => uri) {|r| r.test}

    cookies = http.instance_variable_get(:@cookie_list)
    cookies["ASP.NET_SessionId"].should == "4f220ee66794dc9281000001"
    cookies["RETS-Session-ID"].should == "foobar"
    cookies["SERVERID"].should == "w613"


    headers = http.instance_variable_get(:@headers)
    headers["Cookie"].should =~ /ASP.NET_SessionId=4f220ee66794dc9281000001/
    headers["Cookie"].should =~ /RETS-Session-ID=foobar/
    headers["Cookie"].should =~ /SERVERID=w613/

    rets_data = http.instance_variable_get(:@rets_data)
    rets_data[:session_id].should == "foobar"
  end

  it "refreshes a digest if it becomes stale" do
    uri = URI("http://foobar.com/login/login.bar")

    # Stale request
    digest = 'Digest realm="Foo Bar",nonce="7d8ca69b352016f88d7c3d8a040dc9e0",opaque="431d3681382c9550ffc0525839a37aa3",stale=true,qop="auth"'

    header_mock = mock("Header")
    header_mock.should_receive(:get_fields).with("www-authenticate").and_return(["Digest #{digest}"])
    header_mock.should_receive(:[]).with("www-authenticate").and_return("Digest #{digest}")
    header_mock.should_receive(:[]).with("set-cookie").and_return(nil)

    res_mock = mock("Response")
    res_mock.stub(:code).and_return("200")
    res_mock.stub(:header).and_return(header_mock)

    http_mock = mock("HTTP")
    http_mock.should_receive(:start).and_yield
    http_mock.should_receive(:request_get).with(uri.request_uri, anything).and_yield(res_mock)

    Net::HTTP.should_receive(:new).ordered.and_return(http_mock)

    # Good request
    header_mock = mock("Header")
    header_mock.should_receive(:[]).with("www-authenticate").and_return(nil)
    header_mock.should_receive(:[]).with("set-cookie").and_return(nil)

    res_mock = mock("Response")
    res_mock.stub(:body).and_return("Foo Bar")
    res_mock.stub(:code).and_return("200")
    res_mock.stub(:header).and_return(header_mock)
    res_mock.should_receive(:test).with("Foo Bar")

    http_mock = mock("HTTP")
    http_mock.should_receive(:start).and_yield
    http_mock.should_receive(:request_get).with(uri.request_uri, anything).and_yield(res_mock)

    Net::HTTP.should_receive(:new).ordered.and_return(http_mock)

    # There's no easy way of checking if a yield or proc was called, so will just fake it by calling a stub with should_receive
    http = RETS::HTTP.new(:username => "foo", :password => "bar")

    http.instance_variable_set(:@auth_mode, :digest)
    http.should_receive(:save_digest).with(digest)
    http.should_receive(:create_digest).twice.with("GET", uri.request_uri).and_return(nil)

    http.request(:url => uri) {|r| r.test(r.body) }
  end

  it "reauthenticates after a HTTP 401 with successful authentication" do
    uri, login_uri = URI("http://foobar.com/search/search.bar"), URI("http://foobar.com/login/login.bar")

    tests = [
      {:code => "401", :uri => uri, :hash_match => hash_including("Cookie" => "RETS-Session-ID=foofoo")},
      {:cookie => "barfoo", :code => "200", :uri => login_uri, :hash_match => hash_not_including("Cookie" => "RETS-Session-ID=foofoo")},
      {:code => "200", :uri => uri, :hash_match => hash_including("Cookie" => "RETS-Session-ID=barfoo"), :body => "Foo Bar"}
    ]

    tests.each do |config|
      header_mock = mock("Header")
      header_mock.should_receive(:[]).with("www-authenticate").and_return('realm="Foo Bar",nonce="7d8ca69b352016f88d7c3d8a040dc9e0",opaque="431d3681382c9550ffc0525839a37aa3",qop="auth"')

      if config[:cookie]
        header_mock.should_receive(:get_fields).with("set-cookie").and_return(["RETS-Session-ID=#{config[:cookie]}; path=/"])
        header_mock.should_receive(:[]).with("set-cookie").and_return("RETS-Session-ID=#{config[:cookie]}; path=/")
      else
        header_mock.should_receive(:[]).with("set-cookie").and_return(nil)
      end

      res_mock = mock("Response")
      res_mock.stub(:code).and_return(config[:code])
      res_mock.stub(:header).and_return(header_mock)

      if config[:body]
        res_mock.stub(:body).and_return(config[:body])
        res_mock.should_receive(:test).with(config[:body])
      end

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(config[:uri].request_uri, config[:hash_match]).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)
    end

    http = RETS::HTTP.new(:username => "foo", :password => "Bar")
    http.instance_variable_set(:@auth_mode, :digest)
    http.instance_variable_set(:@headers, {"Cookie" => "RETS-Session-ID=foofoo"})
    http.save_digest('realm="Foo Bar",nonce="7d8ca69b352016f88d7c3d8a040dc9e0",opaque="431d3681382c9550ffc0525839a37aa3",qop="auth"')
    http.login_uri = login_uri

    http.request(:url => uri) {|r| r.test(r.body) }
  end

  it "reauthenticates after a HTTP 401 and then raises an exception after the subsequent failure" do
    uri, login_uri = URI("http://foobar.com/search/search.bar"), URI("http://foobar.com/login/login.bar")

    tests = [
      {:code => "401", :uri => uri, :hash_match => hash_including("Cookie" => "RETS-Session-ID=foofoo")},
      {:cookie => "barfoo", :code => "401", :uri => login_uri, :hash_match => hash_not_including("Cookie" => "RETS-Session-ID=foofoo")}
    ]

    tests.each do |config|
      header_mock = mock("Header")
      header_mock.should_receive(:[]).with("www-authenticate").and_return('realm="Foo Bar",nonce="7d8ca69b352016f88d7c3d8a040dc9e0",opaque="431d3681382c9550ffc0525839a37aa3",qop="auth"')

      if config[:cookie]
        header_mock.should_receive(:get_fields).with("set-cookie").and_return(["RETS-Session-ID=#{config[:cookie]}; path=/"])
        header_mock.should_receive(:[]).with("set-cookie").and_return("RETS-Session-ID=#{config[:cookie]}; path=/")
      else
        header_mock.should_receive(:[]).with("set-cookie").and_return(nil)
      end

      res_mock = mock("Response")
      res_mock.stub(:code).and_return(config[:code])
      res_mock.stub(:header).and_return(header_mock)

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(config[:uri].request_uri, config[:hash_match]).and_yield(res_mock)

      Net::HTTP.should_receive(:new).ordered.and_return(http_mock)
    end

    http = RETS::HTTP.new(:username => "foo", :password => "Bar")
    http.instance_variable_set(:@auth_mode, :digest)
    http.instance_variable_set(:@headers, {"Cookie" => "RETS-Session-ID=foofoo"})
    http.save_digest('realm="Foo Bar",nonce="7d8ca69b352016f88d7c3d8a040dc9e0",opaque="431d3681382c9550ffc0525839a37aa3",qop="auth"')
    http.login_uri = login_uri

    lambda { http.request(:url => uri) }.should raise_error(RETS::Unauthorized)
  end

  context "request error" do
    it "raises an APIError for RETS Server errors" do
      uri = URI("http://foobar.com/login/login.bar")

      res_mock = mock("Response")
      res_mock.stub(:body).and_return('<RETS ReplyCode="20000" replytext="Message indicating why it failed."></RETS>')
      res_mock.stub(:code).and_return("400")
      res_mock.stub(:message).and_return("Bad Request")
      res_mock.stub(:header).and_return({})

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, anything).and_yield(res_mock)

      Net::HTTP.should_receive(:new).and_return(http_mock)

      # There's no easy way of checking if a yield or proc was called, so will just fake it by calling a stub with should_receive
      http = RETS::HTTP.new(:username => "foo", :password => "bar")
      lambda { http.request(:url => uri) }.should raise_error(RETS::APIError)
    end

    it "raises a HTTPError for web server errors" do
      uri = URI("http://foobar.com/login/login.bar")

      res_mock = mock("Response")
      res_mock.stub(:body).and_return("")
      res_mock.stub(:code).and_return("400")
      res_mock.stub(:message).and_return("Bad Request")
      res_mock.stub(:header).and_return({})

      http_mock = mock("HTTP")
      http_mock.should_receive(:start).and_yield
      http_mock.should_receive(:request_get).with(uri.request_uri, anything).and_yield(res_mock)

      Net::HTTP.should_receive(:new).and_return(http_mock)

      # There's no easy way of checking if a yield or proc was called, so will just fake it by calling a stub with should_receive
      http = RETS::HTTP.new(:username => "foo", :password => "bar")
      lambda { http.request(:url => uri) }.should raise_error(RETS::HTTPError)
    end
  end
end