require "spec_helper"

describe RETS::StreamHTTP do
  include Support::SocketMock

  it "reads data from the socket in 4 character groups" do
    str = "The quick brown fox jumps over the lazy dog."

    response = mock_response_with_socket(false, str.length, str)
    stream = RETS::StreamHTTP.new(response)

    11.times do |i|
      stream.read(4).should == str[i * 4, 4]
    end

    stream.size.should == 44
    stream.hash.should == Digest::SHA1.hexdigest(str)
  end

  it "can handle HTTP chunked data from the socket" do
    orig_str = "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

    response = mock_response_with_socket(true, orig_str.length, "1a\r\nLorem ipsum dolor sit amet\r\n62\r\n, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.\r\nb2\r\n Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum\r\n5\r\n dolo\r\n6\r\nre eu \r\na\r\nfugiat nul\r\n24\r\nla pariatur. Excepteur sint occaecat\r\n7\r\n cupida\r\n50\r\ntat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.\r\n0\r\n\r\n")
    stream = RETS::StreamHTTP.new(response)

    # While Nokogiri reads at a fixed 4000 char buffer, purposely adding some randomness to what it reads to make sure
    # that it's a resilient implementation and doesn't have any hidden bugs.
    len_pattern = [6, 4, 20, 21, 2, 80, 2]

    offset, i = 0, 0
    while offset <= 446
      data = stream.read(len_pattern[i])
      break if data.nil?

      data.should == orig_str[offset, data.length]

      offset += data.length
      i += 1
      i = 0 if len_pattern[i].nil?
    end

    stream.size.should == orig_str.length
    stream.hash.should == Digest::SHA1.hexdigest(orig_str)
  end
end