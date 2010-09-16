spec = Gem::Specification.new do |spec|
  spec.name = "gpgr"
  spec.version = "0.0.5"
  spec.platform = Gem::Platform::RUBY
  spec.summary = "A lightweight GPG CLI interface for encyrypting files"
  spec.files =  Dir.glob("{lib,spec,test}/**/**/*") +
                      ["Rakefile"]
  spec.require_path = "lib"

  spec.test_files = Dir[ "test/*_test.rb" ]
  spec.has_rdoc = true
  spec.extra_rdoc_files = %w{HACKING README.markdown LICENSE COPYING}
  spec.rdoc_options << '--title' << 'Gpgr Documentation' <<
                       '--main'  << 'lib/gpgr.rb' << '-q'
  spec.author = "Ryan Stenhouse"
  spec.email = "  ryan@ryanstenhouse.eu"
  spec.rubyforge_project = "gpgr"
  spec.homepage = "http://ryanstenhouse.eu"
  spec.description = <<END_DESC
  gpgr is a very light interface to the command-line GPG (GNU 
  Privacy Guard) tool which is soley concerned with making it
  as easy as possible to encrypt files with one (or more) public
  keys.

  It does not provide any major key management tools and does not
  support decryption.   

	some updates by ben vandgrift, ben@vandgrift.com
END_DESC
