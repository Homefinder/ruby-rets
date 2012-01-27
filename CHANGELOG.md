# Overview

## 2.0.0

The fast 1.0.0 -> 2.0.0 bump was due to bugs in how authorization was handled requiring some small breaking changes to the initial login call. I also wanted to clean up some small parts of the API and make sure everything had tests to reduce future issues as well. This should be the last breaking changes release for a while, everything else will follow a deprecation period.

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