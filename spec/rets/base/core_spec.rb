require "spec_helper"

describe RETS::Base::Core do
  before :all do
    @uri = URI("http://foobar.com/api/page")
    @response_path = File.expand_path("../../../responses", __FILE__)
  end

  # Make sure that \r\n is always used as that's what we get back from HTTP
  def load_file(dir, file)
    body = File.read(File.join(@response_path, dir, "#{file}.txt"))
    body.gsub!("\r", "")
    body.gsub!("\n", "\r\n")
    body
  end

  it "attempts to logout" do
    http = mock("HTTP")
    http.should_receive(:request).with(:url => @uri)
    RETS::Base::Core.new(http, {:logout => @uri}).logout
  end

  it "returns based on capability" do
    client = RETS::Base::Core.new(nil, {:logout => @uri})
    client.has_capability?(:logout).should be_true
    client.has_capability?(:search).should be_false
  end

  context "get_metadata" do
    it "successfully loads" do
      RETS::StreamHTTP.stub(:new).and_return(StringIO.new(load_file("get_metadata", "success")))

      http = mock("HTTP")
      http.should_receive(:request).with(hash_including(:url => @uri, :read_timeout => nil, :params => {:Format => :COMPACT, :Type => "Foo", :ID => "*"})).and_yield(nil)

      client = RETS::Base::Core.new(http, {:getmetadata => @uri})
      client.get_metadata(:type => "Foo", :id => "*") do |type, attrs, data|
        type.should == "TABLE"
        attrs["Version"].should == "0.0.2"
        attrs["Date"].should == "Thu, 26 Jan 2012 00:00:00 GMT"
        attrs["Resource"].should == "PropDM"
        attrs["Class"].should == "Place"

        data.should == [
          {"MetadataEntryID" => "BB1662B7C5F22A0F905FD59E718CA05E", "SystemName" => "DM_LOC", "StandardName" => "", "LongName" => "DM_LOC", "DBName" => "DM_LOC", "ShortName" => "", "MaximumLength" => "16", "DataType" => "Character", "Precision" => "", "Searchable" => "1"},
          {"MetadataEntryID" => "9457FC28CEB408103E13533E4A5B6BD1", "SystemName" => "DM_ID", "StandardName" => "", "LongName" => "DM_ID", "DBName" => "DM_ID", "ShortName" => "", "MaximumLength" => "10", "DataType" => "Character", "Precision" => "", "Searchable" => "1", "Interpretation" => "", "Alignment" => "", "UseSeparator" => "", "EditMaskID" => "", "LookupName" => "", "MaxSelect" => "", "Units" => "", "Index" => "", "Minimum" => "", "Maximum" => "", "Default" => "", "Required" => "", "SearchHelpID" => "", "Unique" => "1"},
          {"MetadataEntryID" => "BEA5955B308361A1B07BC55042E25E54", "SystemName" => "DM_LVL", "StandardName" => "", "LongName" => "DM_LVL", "DBName" => "DM_LVL", "ShortName" => "", "MaximumLength" => "5", "DataType" => "Decimal", "Precision" => "0", "Searchable" => "1"},
          {"MetadataEntryID" => "F9D1152547C0BDE01830B7E8BD60024C", "SystemName" => "DM_MLSID", "StandardName" => "", "LongName" => "DM_MLSID", "DBName" => "DM_MLSID", "ShortName" => "", "MaximumLength" => "10", "DataType" => "Character", "Precision" => "", "Searchable" => "1"},
          {"MetadataEntryID" => "AF4732711661056EADBF798BA191272A", "SystemName" => "DM_ORDR", "StandardName" => "", "LongName" => "DM_ORDR", "DBName" => "DM_ORDR", "ShortName" => "", "MaximumLength" => "5", "DataType" => "Decimal", "Precision" => "0", "Searchable" => "1"},
          {"MetadataEntryID" => "008BD5AD93B754D500338C253D9C1770", "SystemName" => "DM_TYPE", "StandardName" => "", "LongName" => "DM_TYPE", "DBName" => "DM_TYPE", "ShortName" => "", "MaximumLength" => "5", "DataType" => "Decimal", "Precision" => "0", "Searchable" => "1"}
        ]
      end

      client.rets_data.should == {:code => "0", :text => "Operation Successful.", :delimiter => "\t"}
    end

    it "raises an error" do
      RETS::StreamHTTP.stub(:new).and_return(StringIO.new(load_file("get_metadata", "error")))

      http = mock("HTTP")
      http.should_receive(:request).with(anything).and_yield(nil)

      client = RETS::Base::Core.new(http, {:getmetadata => @uri})

      lambda { client.get_metadata({}) {} }.should raise_error(RETS::APIError) do |e|
        e.code.should == "20000"
        e.text.should == "Error message goes here."
      end
    end
  end

  context "get_object" do
    context "multipart" do
      it "successfully loads full data" do
        body = load_file("get_object", "multipart_success")

        response = mock("Response")
        response.stub(:read_body).and_return(body)
        response.stub(:content_type).and_return("multipart/parallel")
        response.stub(:type_params).and_return("boundary" => "534546696C65426F756E647279")

        http = mock("HTTP")
        http.should_receive(:request).with(hash_including(:url => @uri, :headers => {"Accept" => "a/b,c/d,e/f"}, :params => {:Resource => "Property", :Type => "Photo", :Location => 0, :ID => "0:0:*"})).and_yield(response)

        data = []

        client = RETS::Base::Core.new(http, {:getobject => @uri})
        client.get_object(:resource => "Property", :type => "Photo", :id => "0:0:*", :accept => ["a/b", "c/d", "e/f"]) do |headers, content|
          data.push(:headers => headers, :content => content)
        end

        client.rets_data.should be_nil
        client.request_size.should == body.length
        client.request_hash.should == Digest::SHA1.hexdigest(body)

        data.should have(2).photos

        data[0][:headers].should == {"content-type" => "a/b", "description" => "Foo Bar", "content-id" => "1234", "object-id" => "1"}
        data[0][:content].should == "Object Data 1"

        data[1][:headers].should == {"content-type" => "c/d", "description" => "Bar Foo", "content-id" => "5678", "object-id" => "2"}
        data[1][:content].should == "Quick\r\nObject\r\nData\r\n2"
      end

      it "successfully loads locations" do
        body = load_file("get_object", "multipart_location_success")

        response = mock("Response")
        response.stub(:read_body).and_return(body)
        response.stub(:content_type).and_return("multipart/parallel")
        response.stub(:type_params).and_return("boundary" => "534546696C65426F756E647279", "charset" => "UTF8")

        http = mock("HTTP")
        http.should_receive(:request).with(hash_including(:url => @uri, :headers => {"Accept" => "image/png,image/gif,image/jpeg"}, :params => {:Resource => "Property", :Type => "Photo", :Location => 1, :ID => "0:0:*"})).and_yield(response)

        data = []

        client = RETS::Base::Core.new(http, {:getobject => @uri})
        client.get_object(:resource => "Property", :type => "Photo", :id => "0:0:*", :location => true) do |headers|
          data.push(headers)
        end

        client.rets_data.should be_nil
        client.request_size.should == body.length
        client.request_hash.should == Digest::SHA1.hexdigest(body)

        data.should have(2).photos
        data[0].should == {"content-type" => "image/jpeg", "content-id" => "1234", "object-id" => "1", "description" => "Foo Bar", "location" => "http://foobar.com/images/1234_1686250.jpg"}
        data[1].should == {"content-type" => "image/jpeg", "content-id" => "5678", "object-id" => "2", "description" => "Bar Foo", "location" => "http://foobar.com/images/1234_0186250.jpg"}
      end

      it "raises an error" do
        body = load_file("get_object", "multipart_error")

        response = mock("Response")
        response.stub(:read_body).and_return(body)
        response.stub(:content_type).and_return("multipart/parallel")
        response.stub(:type_params).and_return("boundary" => '"534546696C65426F756E647279"', "charset" => "UTF8")

        http = mock("HTTP")
        http.should_receive(:request).with(anything).and_yield(response)
        http.stub(:get_rets_response) do |args|
          RETS::HTTP.new({}).get_rets_response(args)
        end

        client = RETS::Base::Core.new(http, {:getobject => @uri})
        lambda {
          client.get_object(:resource => "Property", :type => "Photo", :id => "0:0:*") {|a, b|}
        }.should raise_error(RETS::APIError) do |e|
          e.code.should == "20000"
          e.text.should == "Error message goes here."
        end

        client.rets_data.should == {:code => "20000", :text => "Error message goes here."}
      end
    end

    context "without multipart" do
      it "successfully loads data" do
        body = load_file("get_object", "single_success")

        response = mock("Response")
        response.stub(:read_body).and_return(body)
        response.stub(:content_type).and_return("image/jpg")
        response.stub(:header).and_return("content-type" => "image/jpg", "content-id" => "1234", "object-id" => "1")

        http = mock("HTTP")
        http.should_receive(:request).with(hash_including(:url => @uri, :headers => {"Accept" => "image/png,image/gif,image/jpeg"}, :params => {:Resource => "Property", :Type => "Photo", :Location => 0, :ID => "0:0:*"})).and_yield(response)

        client = RETS::Base::Core.new(http, {:getobject => @uri})
        client.get_object(:resource => "Property", :type => "Photo", :id => "0:0:*") do |headers, content|
          headers.should == {"content-type" => "image/jpg", "content-id" => "1234", "object-id" => "1"}
          content.should == "Quick\r\nObject\r\nData\r\n2"
        end

        client.rets_data.should be_nil
        client.request_size.should == body.length
        client.request_hash.should == Digest::SHA1.hexdigest(body)
      end

      it "successfully loads a single location" do
        body = load_file("get_object", "single_location_success")

        response = mock("Response")
        response.stub(:read_body).and_return(body)
        response.stub(:content_type).and_return("image/png")
        response.stub(:header).and_return("content-type" => "image/png", "content-id" => "1234", "object-id" => "1", "description" => "Foo Bar", "location" => "http://foobar.com/images/1234_5678.png")

        http = mock("HTTP")
        http.should_receive(:request).with(hash_including(:url => @uri, :headers => {"Accept" => "image/png,image/gif,image/jpeg"}, :params => {:Resource => "Property", :Type => "Photo", :Location => 1, :ID => "0:0:*"})).and_yield(response)

        client = RETS::Base::Core.new(http, {:getobject => @uri})
        client.get_object(:resource => "Property", :type => "Photo", :id => "0:0:*", :location => true) do |headers|
          headers.should == {"content-type" => "image/png", "content-id" => "1234", "object-id" => "1", "description" => "Foo Bar", "location" => "http://foobar.com/images/1234_5678.png"}
        end

        client.rets_data.should be_nil
        client.request_size.should == body.length
        client.request_hash.should == Digest::SHA1.hexdigest(body)
      end

      it "raises an error" do
        body = load_file("get_object", "single_error")

        response = mock("Response")
        response.stub(:read_body).and_return(body)
        response.stub(:content_type).and_return("image/xml")
        response.stub(:header).and_return("content-type" => "image/xml; charset=UTF8")

        http = mock("HTTP")
        http.should_receive(:request).with(anything).and_yield(response)
        http.should_receive(:get_rets_response).and_return(["20000", "Error message goes here."])

        client = RETS::Base::Core.new(http, {:getobject => @uri})
        lambda {
          client.get_object(:resource => "Property", :type => "Photo", :id => "0:0:*") {|a, b|}
        }.should raise_error(RETS::APIError) do |e|
          e.code.should == "20000"
          e.text.should == "Error message goes here."
        end
      end
    end
  end

  context "search" do
    it "successfully loads data" do
      RETS::StreamHTTP.stub(:new).and_return(StringIO.new(load_file("search", "success")))

      http = mock("HTTP")
      http.should_receive(:request).with(hash_including(:url => @uri, :params => {:SearchType => "Property", :QueryType => "DMQL2", :Format => "COMPACT-DECODED", :Class => "RES", :Limit => 5, :Offset => 10, :RestrictedIndicator => "####", :Select => "A,B,C", :StandardNames => 1, :Count => 1, :Query => "(FOO=BAR)"})).and_yield(nil)

      data = []

      client = RETS::Base::Core.new(http, {:search => @uri})
      client.search(:search_type => "Property", :query => "(FOO=BAR)", :class => "RES", :limit => 5, :offset => 10, :restricted => "####", :select => ["A", "B", "C"], :standard_names => true, :count_mode => :both) do |row|
        data.push(row)
      end

      client.rets_data.should == {:code => "0", :text => "Operation Successful", :count => 2, :delimiter => "\t"}

      data.should have(2).items
      data[0].should == {"BATHS" => "1.000000", "BATHS_FULL" => "1", "BATHS_HALF" => "0", "BEDROOMS" => "3", "STREET_NAME" => "BAR STEET"}
      data[1].should == {"BATHS" => "3.000000", "BATHS_FULL" => "2", "BATHS_HALF" => "1", "BEDROOMS" => "", "STREET_NAME" => "FOO STREET"}
    end

    it "successfully loads data" do

      body = load_file("search", "success")
    
      response = mock("Response")
      response.stub(:body).and_return(body)
      response.stub(:header).and_return({"Content-Type" => "text/plain; charset=utf-8"})
      
      http = mock("HTTP")
      http.should_receive(:request).with(anything).and_yield(response)

      data = []

      client = RETS::Base::Core.new(http, {:search => @uri})
      client.search(:search_type => "Property", :query => "(FOO=BAR)", :class => "RES", :limit => 5, :offset => 10, :restricted => "####", :select => ["A", "B", "C"], :standard_names => true, :count_mode => :both, :disable_stream => true) do |row|
        data.push(row)
      end

      client.rets_data.should == {:code => "0", :text => "Operation Successful", :count => 2, :delimiter => "\t"}

      data.should have(2).items
      data[0].should == {"BATHS" => "1.000000", "BATHS_FULL" => "1", "BATHS_HALF" => "0", "BEDROOMS" => "3", "STREET_NAME" => "BAR STEET"}
      data[1].should == {"BATHS" => "3.000000", "BATHS_FULL" => "2", "BATHS_HALF" => "1", "BEDROOMS" => "", "STREET_NAME" => "FOO STREET"}
    end

    it "raises an error" do
      RETS::StreamHTTP.stub(:new).and_return(StringIO.new(load_file("search", "error")))

      http = mock("HTTP")
      http.should_receive(:request).with(anything).and_yield(nil)

      client = RETS::Base::Core.new(http, {:search => @uri})
      lambda { client.search({}) {} }.should raise_error(RETS::APIError) do |e|
        e.code.should == "20000"
        e.text.should == "Error message goes here."
      end
    end
  end
end