Ruby RETS
===
Library for pulling data from RETS. Should work with any implementations based off of RETS 1.x.

Documentation
-
See http://rubydoc.info/github/Placester/ruby-rets/master/frames for documentation.

Examples
-

Search and metadata requests sent through Nokogiri's SAX parser while downloading, and the data is sent back using the passed block.

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
* Ruby 1.8 (Should work on 1.9)
* Nokogiri

License
-
Dual licensed under MIT and GPL.