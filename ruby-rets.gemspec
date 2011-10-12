$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require "lib/rets/version.rb"

Gem::Specification.new do |s|
  s.name        = "ruby-rets"
  s.version     = RETS::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Zachary Anker"]
  s.email       = ["zach.anker@gmail.com"]
  s.homepage    = "http://github.com/Placester/ruby-rets"
  s.summary     = "RETS library for Ruby"
  s.description = "Simplifies communication with RETS 1.x APIs."

  s.files        = Dir.glob("lib/**/*") + %w[GPL-LICENSE MIT-LICENSE README.markdown]
  s.require_path = "lib"

  s.required_rubygems_version = ">= 1.3.6"
  s.rubyforge_project         = "ruby-rets"

  s.add_runtime_dependency "nokogiri", "~>1.4.0"
end