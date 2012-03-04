# Overview

## 2.0.1

### API Changes
  * `client.login` will now raise `ResponseError` errors if the RETS tag cannot be found in the response
  * `client.login` added the ability to pass `:rets_version` to force the RETS Version used in HTTP requests (small speedup when used)
  * `client.get_object` can return both Content-Description or Description rather than just Description. Also will return Preferred

### Features
  * Added support for TimeoutSeconds, after the timeout passes the gem seamlessly reauthenticate
  * Improved the edge case handling for authentication requests to greatly increase compatability with logging into any RETS based system

### Fixes
  * Object multipart parsing no longer fails if the boundary is wrapped in quotes
  * Response parsing won't fail if the RETS server uses odd casing for the "ReplyText" and "ReplyCode" args in RETS 

## 2.0.0

### API Changes
  * `client.logout` will now raise `CapabilityNotFound` errors if it's unsupported
  * `client.get_object` now requires a block which is yielded to rather than returning an array of the content
  * `client.get_object` headers are now returned in lowercase form ("content-id" not "Content-ID" and so on)
  * `RETS::Client.login` now uses `:useragent => {:name => "Foo", :password => "Bar"}` to pass User Agent data
  * `RETS::Client.login` no longer implies the User-Agent username or password by the primary username and password

### Features
  * Added support for Count, Offset, Select and RestrictedIndicators in `client.search`
  * Added support for Location in `client.get_object`
  * RETS reply code, text and other data such as count or delimiter can be gotten through `client.rets_data` after the call is finished

### Fixes
  * Redid how authentication is handled, no longer implies HTTP Basic auth when using RETS-UA-Authorization
  * RETS-Version is now used for RETS-UA-Authorization when available with "RETS/1.7" as a fallback
  * Exceptions are now raised consistently and have been simplifed to `APIError`, `HTTPError`, `Unauthorized` and `CapabilityNotFound`
  * `HTTPError` and `APIError` now include the reply text and code in `reply_code` and `reply_text`