module RETS
  ##
  # Generic module that provides access to the code and text separately of the exception
  module ReplyErrors
    attr_reader :reply_text, :reply_code

    def initialize(msg, reply_code=nil, reply_text=nil)
      super(msg)
      @reply_code, @reply_text = reply_code, reply_text
    end
  end

  ##
  # RETS server replied to a request with an error of some sort.
  class APIError < StandardError
    include ReplyErrors
  end

  ##
  # Server responded with bad data.
  class ResponseError < StandardError
  end

  ##
  # HTTP errors related to a request.
  class HTTPError < StandardError
    include ReplyErrors
  end

  ##
  # Cannot login
  class Unauthorized < RuntimeError; end

  ##
  # Account does not have access to the requested API.
  class CapabilityNotFound < RuntimeError; end
end