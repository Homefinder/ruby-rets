# Overview

## 2.0.0 \[In Development\]

I wasn't originally planning on doing a 1.0.0 -> 2.0.0 bump so quickly, but redoing the authentication to fix a bug with one of the RETS Server implementations meant some sort of breaking change would be necessary. As I had some other areas of the API I wanted to clean up and make more consistent overall, this turned into a 2.0.0 version bump.

### API Changes
  * `client.logout` will now raise `CapabilityNotFound` errors if it's unsupported
  * `client.get_object` now requires a block which is yielded to rather than returning an array of the content
  * `client.get_object` headers are now returned in lowercase form ("content-id" not "Content-ID" and so on)
  * `RETS::Client.login` now uses `:useragent => {:name => "Foo", :password => "Bar"}` to pass User Agent data, and it's no longer tries to guess at the User Agent data

### Features
  * Added support for all optional arguments in `client.search`
  * Added support for getting object location rather than content in `client.get_object`
  * RETS reply code, text and other data such as count or delimiter can be gotten through `client.rets_data` after the call is finished

### Fixes
  * Redid how authentication is handled, should fix any authentication bugs due to lax User Agent handling
  * Exceptions are now raised consistently and have been simplifed to `APIError`, `HTTPError`, `Unauthorized` and `CapabilityNotFound`
  * `HTTPError` and `APIError` now include the reply text and code in `reply_code` and `reply_text`