Ruby RETS
===
Library for pulling data from RETS 1.x servers. Primary difference from other RETS gems is that data is parsed as soon as its loaded to the server and discarded, it doesn't have to be written to disk first to do stream parsing.

Documentation
-
See http://rubydoc.info/github/Placester/ruby-rets/master/frames for documentation.

Examples
-

    client = RETS::Client.login(:url => "http://foobar.com/rets/Login", :username => "foo", :password => "bar", :user_agent => "My RETS Importer")
    client.search(:search_type => :Property, :class => :RES, :filter => "(ListPrice=50000-)", :read_timeout => 10.minutes.to_i) do |data|
      # RETS data in key/value format, as COMPACT-DECODED
    end

    client.get_object(:resource => :Property, :type => :Photo, :location => false, :id => "1:0:*").each do |object|
      puts "Object-ID #{object[:headers]["Object-ID"]}, Content-ID #{object[:headers]["Content-ID"], Description #{object[:headers]["Description"]}"
      puts "Data"
      puts object[:content]
    end

Requirements
-
* Tested on Ruby 1.8.7 and Ruby 1.9.3
* Nokogiri ~> 1.5.0

License
-
Dual licensed under MIT and GPL.