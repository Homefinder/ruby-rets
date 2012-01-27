Overview
===
Main focus is on a simple gem for pulling data from the RETS server through SAX parsing rather than requiring documents to be written to disk and then manually passed through a SAX parser. Should support any 1.x implementation.

Compability
-
Tested against Ruby 1.8.7, 1.9.2, 2.0.0 and REE. [Build History](http://travis-ci.org/Placester/ruby-rets)

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