module RETS
  class ServerError < RuntimeError; end

  class CapabilityNotFound < RuntimeError; end

  class InvalidResponse < RuntimeError; end
  class InvalidAuth < RuntimeError; end
  class UnsupportedAuth < RuntimeError; end
end