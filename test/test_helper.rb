require 'test/unit'
require 'rubygems'
require 'flexmock/test_unit'

# Figure out the root relative to where this file is
#
GPGR_ROOT = File.expand_path(File.dirname(__FILE__) + '/../lib')

# Include the gpgr library
#
require GPGR_ROOT + '/gpgr.rb'

def remove_installed_key(email)
  system "gpg -q --no-verbose --delete-key --yes --batch #{email}"
end

def cleanup_batch_keys
    remove_installed_key 'testymctest1@example.com'
    remove_installed_key 'testymctest2@example.com'
    remove_installed_key 'testymctest3@example.com'
end

def pgp_global_dir_key_and_email
  ['pub:-:2048:1:9710B89BCA57AD7C:2004-12-06:::-:PGP Global Directory Verification Key::scSC:',
   'pub:u:2048:17:0247FEC05FDA4350:2010-09-13:::u:John Example <john@example.com>::scESC:']
end

