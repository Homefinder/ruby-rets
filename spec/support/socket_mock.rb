require "stringio"

module Support
  module SocketMock
    def mock_response_with_socket(chunked, size, body)
      response = mock("Response")
      response.stub(:content_length).and_return(chunked ? nil : size)
      response.stub(:chunked?).and_return(chunked)
      response.stub(:instance_variable_get).with(:@socket).and_return(StringIO.new(body))
      response.stub(:header).and_return({})
      response.should_receive(:instance_variable_set).at_least(1).with(:@read, true)
      response
    end
  end
end