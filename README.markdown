Ruby RETS
===
RETS library for 1.7, should work for 1.5 but hasn't been tested yet. Support for 2.0 is planned, but it's not in yet. The main focus is towards pulling data out of a RETS, the GetObject and Search API's are supported, Update will be eventually.

Requirements
-
* Ruby 1.8 (Should work on 1.9)
* Nokogiri

Examples
-

user_agent and read_timeout are optional.

    client = RETS::Client.login(:url => "http://foobar.com/rets/Login", :username => "foo", :password => "bar", :user_agent => "My RETS Importer")
    client.search(:search_type => :Property, :class => :RES, :filter => "(ListPrice=50000-)", :read_timeout => 10.minutes.to_i) do |data|
      # RETS data in key/value format, as COMPACT-DECODED
    end

    client.get_object(:resource => :Property, :type => :Photo, :location => false, :id => "1:0:*").each do |object|
      puts "Object-ID #{object[:headers]["Object-ID"]}, Content-ID #{object[:headers]["Content-ID"], Description #{object[:headers]["Description"]}"
      puts "Data"
      puts object[:content]
    end

License
-
Dual licensed under MIT and GPL.

Todo
-
* Write rdocs
* Add support for inline GZIP decompression
* Add actual tests for areas that can be tested.
* Clean up and improve the code a bit for sanity.
* RETS 2.0 support
