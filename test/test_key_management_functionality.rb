require File.dirname(__FILE__) + '/test_helper.rb'

class TestKeyManagementFunctionality < Test::Unit::TestCase

  def test_installed_public_keys
    setup_for_key_tests
    before = Gpgr::Keys.installed_public_keys.nitems
    Gpgr::Keys.import @mark_key
    Gpgr::Keys.import @john_key
    assert_equal before + 2, Gpgr::Keys.installed_public_keys.nitems
    teardown_for_key_tests
  end

  #  This becomes necessary if PGP keys are installed
  #
  def test_installed_public_keys_allow_for_no_email_in_keyline
    setup_for_key_tests
    assert_equal false, Gpgr::Keys.public_key_installed?('john@example.com')

    flexmock(Gpgr::Keys).should_receive(:public_key_entries).and_return(pgp_global_dir_key_and_email)
    Gpgr::Keys.import @john_key

    assert_nothing_raised do
      Gpgr::Keys.installed_public_keys.include?('john@example.com'.upcase)
    end
    teardown_for_key_tests
  end
  
  def test_import_keys_method_adds_keys
    setup_for_key_tests
    assert_equal false, Gpgr::Keys.public_key_installed?('john@example.com')
    assert_equal false, Gpgr::Keys.public_key_installed?('mark@example.com')
    Gpgr::Keys.import @john_key
    Gpgr::Keys.import @mark_key
    assert_equal true, Gpgr::Keys.public_key_installed?('john@example.com')
    assert_equal true, Gpgr::Keys.public_key_installed?('mark@example.com')
    teardown_for_key_tests
  end

  def test_import_all_keys_at_a_path
    path = File.dirname(__FILE__) + '/test_keys'
    before = Gpgr::Keys.installed_public_keys.nitems
    Gpgr::Keys.import_keys_at(path)
    assert_equal before + 3, Gpgr::Keys.installed_public_keys.nitems
    cleanup_batch_keys
  end
  
  def test_import_all_keys_at_path_with_non_key_files
    path = File.dirname(__FILE__) + '/test_keys_with_non_key_files'
    before = Gpgr::Keys.installed_public_keys.nitems
    Gpgr::Keys.import_keys_at(path)
    assert_equal before + 3, Gpgr::Keys.installed_public_keys.nitems
    cleanup_batch_keys
  end
  
  def setup_for_key_tests
    @john_key = File.dirname(__FILE__) + '/john_and_marks_keys/john.pub'
    @mark_key = File.dirname(__FILE__) + '/john_and_marks_keys/mark.pub'
  end
  
  def teardown_for_key_tests
    remove_installed_key 'john@example.com'
    remove_installed_key 'mark@example.com'
  end

end
