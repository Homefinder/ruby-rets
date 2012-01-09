module RETS
  # RETS server replied to a request with an error of some sort.
  class ServerError < RuntimeError; end

  # Account does not have access to the requested API.
  class CapabilityNotFound < RuntimeError; end

  # HTTP errors related to a request.
  class InvalidResponse < RuntimeError; end

  # Failed to login to the RETS server.
  class InvalidAuth < RuntimeError; end
  
  # Something with the request was invalid
  class InvalidRequest < RuntimeError; end

  # Attempting to auth in a way that the library does not support.
  class UnsupportedAuth < RuntimeError; end
end