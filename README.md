Overview
===
Simplifies the process of pulling data from RETS servers without having to worry about various authentication setups, should support all 1.x implementations. Parsing uses SAX to stream data as it comes rather than having to pull the entire document down and parse it all at once as some servers can return quite a lot of data.

Compability
-
Tested against Ruby 1.8.7, 1.9.2 and 2.0.0, build history is available [here](http://travis-ci.org/Placester/ruby-rets).

<img src="https://secure.travis-ci.org/Placester/ruby-rets.png?branch=master&.png"/>

Documentation
-
See http://rubydoc.info/github/Placester/ruby-rets/master/frames for full documentation.

Examples
-

    client = RETS::Client.login(:url => "http://foobar.com/rets/Login", :username => "foo", :password => "bar")
    client.search(:search_type => :Property, :class => :RES, :filter => "(ListPrice=50000-)") do |data|
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