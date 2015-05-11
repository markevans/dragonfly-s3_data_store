# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'dragonfly/s3_data_store/version'

Gem::Specification.new do |spec|
  spec.name          = "dragonfly-s3_data_store"
  spec.version       = Dragonfly::S3DataStore::VERSION
  spec.authors       = ["Mark Evans"]
  spec.email         = ["mark@new-bamboo.co.uk"]
  spec.description   = %q{S3 data store for Dragonfly}
  spec.summary       = %q{Data store for storing Dragonfly content (e.g. images) on S3}
  spec.homepage      = "https://github.com/markevans/dragonfly-s3_data_store"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "dragonfly", "~> 1.0"
  spec.add_runtime_dependency "fog-aws"
  spec.add_development_dependency "rspec", "~> 2.0"

  spec.post_install_message = <<-POST_INSTALL_MESSAGE
=====================================================
Thanks for installing dragonfly-s3_data_store!!
If you have any fog compatibility problems, please be aware that
it now depends on the 'fog-aws' gem rather than the 'fog' gem.
=====================================================
POST_INSTALL_MESSAGE
end
