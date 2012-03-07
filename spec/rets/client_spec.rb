require "spec_helper"

describe RETS::Client do
  include Support::ResponseMock

  it "raises a ResponseError for non-RETS responses" do
    mock_response('<html><body>Foo Bar</body></html')
    lambda { RETS::Client.login(:url => "http://foobar.com/login/login.bar") }.should raise_error(RETS::ResponseError)
  end

  it "raises an APIError if the ReplyCode is != 0 and != 20037" do
    mock_response('<RETS ReplyCode="20000" replytext="Failure message goes here."></RETS>')
    lambda { RETS::Client.login(:url => "http://foobar.com/login/login.bar") }.should raise_error(RETS::APIError)
  end

  it "correctly passes data to the HTTP class" do
    http_mock = mock("HTTP")
    http_mock.should_receive(:request).with(hash_including(:url => URI("http://foobar.com/login/login.bar")))
    http_mock.should_receive(:login_uri=).with(URI("http://foobar.com/login/login.bar"))

    RETS::HTTP.stub(:new).with(hash_including(:username => "foo", :password => "bar")).and_return(http_mock)

    client = RETS::Client.login(:url => "http://foobar.com/login/login.bar", :username => "foo", :password => "bar")
    client.should be_a_kind_of(RETS::Base::Core)
  end

  context "parses capability format" do
    it "spaces with absolute paths" do
      mock_response("<RETS ReplyCode=\"0\" ReplyText=\"Operation Successful\">\n<RETS-RESPONSE>\nBroker = FOO123\nMemberName = John Doe\nMetadataVersion = 5.00.000\nMinMetadataVersion = 5.00.000\nMetadataTimestamp = Wed, 1 June 2011 09:00:00 GMT\nMinMetadataTimestamp = Wed, 1 June 2011 09:00:00 GMT\nUser = BAR123\nLogin = http://foobar.com:1234/rets/login\nLogout = http://foobar.com:1234/rets/logout\nSearch = http://foobar.com:1234/rets/search\nGetMetadata = http://foobar.com:1234/rets/getmetadata\nGetObject = http://foobar.com:1234/rets/getobject\nTimeoutSeconds = 1800\n</RETS-RESPONSE>\n</RETS>")

      client = RETS::Client.login(:url => "http://foobar.com:1234/rets/login")
      urls = client.instance_variable_get(:@urls)
      urls.should have(5).items
      urls[:login].should == URI("http://foobar.com:1234/rets/login")
      urls[:logout].should == URI("http://foobar.com:1234/rets/logout")
      urls[:search].should == URI("http://foobar.com:1234/rets/search")
      urls[:getmetadata].should == URI("http://foobar.com:1234/rets/getmetadata")
      urls[:getobject].should == URI("http://foobar.com:1234/rets/getobject")
    end

    it "no spaces with absolute paths" do
      mock_response("<RETS ReplyCode=\"0\" ReplyText=\"Operation Successful\">\n<RETS-RESPONSE>\nBroker=FOO123\nMemberName=John Doe\nMetadataVersion=5.00.000\nMinMetadataVersion=5.00.000\nMetadataTimestamp=Wed, 1 June 2011 09:00:00 GMT\nMinMetadataTimestamp=Wed, 1 June 2011 09:00:00 GMT\nUser=BAR123\nLogin=http://foobar.com:1234/rets/login\nLogout=http://foobar.com:1234/rets/logout\nSearch=http://foobar.com:1234/rets/search\nGetMetadata=http://foobar.com:1234/rets/getmetadata\nGetObject=http://foobar.com:1234/rets/getobject\nTimeoutSeconds=18000\n</RETS-RESPONSE>\n</RETS>")

      client = RETS::Client.login(:url => "http://foobar.com:1234/rets/login")
      urls = client.instance_variable_get(:@urls)
      urls.should have(5).items
      urls[:login].should == URI("http://foobar.com:1234/rets/login")
      urls[:logout].should == URI("http://foobar.com:1234/rets/logout")
      urls[:search].should == URI("http://foobar.com:1234/rets/search")
      urls[:getmetadata].should == URI("http://foobar.com:1234/rets/getmetadata")
      urls[:getobject].should == URI("http://foobar.com:1234/rets/getobject")
    end

    it "no spaces with relative paths" do
      mock_response("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<RETS ReplyCode=\"0\" ReplyText=\"Success. Reference ID: AAAAAA-BBBB-3333-2222-CCCCCCCC\">\n  <RETS-RESPONSE>\nMemberName=Jane Doe\nUser=1234\nBroker=BAR1234\nMetadataVersion=10.25.63114\nMetadataTimeStamp=Wed, 25 Jan 2012 20:00:55 GMT\nMinMetadataTimeStamp=Wed, 25 Jan 2012 20:00:55 GMT\nTimeoutSeconds=18000\nChangePassword=/ChangePassword.asmx/ChangePassword\nGetObject=/GetObject.asmx/GetObject\nLogin=/Login.asmx/Login\nLogout=/Logout.asmx/Logout\nSearch=/Search.asmx/Search\nGetMetadata=/GetMetadata.asmx/GetMetadata\n</RETS-RESPONSE>\n</RETS>")

      client = RETS::Client.login(:url => "http://foobar.com/Login.asmx/Login")
      urls = client.instance_variable_get(:@urls)
      urls.should have(5).items
      urls[:login].should == URI("http://foobar.com/Login.asmx/Login")
      urls[:logout].should == URI("http://foobar.com/Logout.asmx/Logout")
      urls[:search].should == URI("http://foobar.com/Search.asmx/Search")
      urls[:getmetadata].should == URI("http://foobar.com/GetMetadata.asmx/GetMetadata")
      urls[:getobject].should == URI("http://foobar.com/GetObject.asmx/GetObject")
    end

    it "spaces with relative paths" do
      mock_response("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<RETS ReplyCode=\"0\" ReplyText=\"Success. Reference ID: AAAAAA-BBBB-3333-2222-CCCCCCCC\">\n  <RETS-RESPONSE>\nMemberName = Jane Doe\nUser = 1234\nBroker = BAR1234\nMetadataVersion = 10.25.63114\nMetadataTimeStamp = Wed, 25 Jan 2012 20:00:55 GMT\nMinMetadataTimeStamp = Wed, 25 Jan 2012 20:00:55 GMT\nTimeoutSeconds = 18000\nChangePassword = /ChangePassword.asmx/ChangePassword\nGetObject = /GetObject.asmx/GetObject\nLogin = /Login.asmx/Login\nLogout = /Logout.asmx/Logout\nSearch = /Search.asmx/Search\nGetMetadata = /GetMetadata.asmx/GetMetadata\n</RETS-RESPONSE>\n</RETS>")

      client = RETS::Client.login(:url => "http://foobar.com/Login.asmx/Login")
      urls = client.instance_variable_get(:@urls)
      urls.should have(5).items
      urls[:login].should == URI("http://foobar.com/Login.asmx/Login")
      urls[:logout].should == URI("http://foobar.com/Logout.asmx/Logout")
      urls[:search].should == URI("http://foobar.com/Search.asmx/Search")
      urls[:getmetadata].should == URI("http://foobar.com/GetMetadata.asmx/GetMetadata")
      urls[:getobject].should == URI("http://foobar.com/GetObject.asmx/GetObject")
    end
  end
end