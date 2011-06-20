$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require "rets/version"

Gem::Specification.new do |s|
  s.name        = "rets"
  s.version     = RETS::Version
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Zachary Anker"]
  s.email       = ["zach.anker@gmail.com"]
  s.homepage    = "http://github.com/Placester/rets"
  s.summary     = "RETS library for Ruby"
  s.description = "Simplifies communication with RETS 1.7, support for 2.0 and possibly 1.5 are planned."

  s.files        = Dir.glob("lib/**/*") + %w[GPL-LICENSE MIT-LICENSE README.markdown]
  s.require_path = "lib"

#  s.required_rubygems_version = ">= 1.3.6"
#  s.rubyforge_project         = "rets"

  s.add_runtime_dependency "nokogiri", "~>1.4.0"
  s.add_development_dependency "rspec", "~> 2.0.0"
end