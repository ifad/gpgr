#  Gpgr by Ryan Stenhouse <ryan@ryanstenhouse.eu>, March 2010
#  on behalf of Purchasing Card Consultancy Limited.
#
#  gpgr is a very light interface to the command-line GPG (GNU 
#  Privacy Guard) tool which is soley concerned with making it
#  as easy as possible to encrypt files with one (or more) public
#  keys.
#
#  It does not provide any major key management tools and does not
#  support decryption.   
#
#  Usage:
#    
#    require 'rubygems'
#    require 'gpgr'
#
#    # Synopsis
#    #
#    list_of_keys = [ 'foo@example.com', 'bar@example.com' ]
#    Gpgr::Encrypt.stream("cleat text").encrypt_using(list_of_keys)
#
#    # To import all the public keys in a given directory
#    #
#    Gpgr::Keys.import_keys_at('/path/to/public/keys')
#   
#    #  Will encrypt for every single person you have a public key for
#    #
#    Gpgr::Encrypt.stream("clear text").encrypt_using(Gpgr::Keys.installed_public_keys)
#
#  Changelog
#  * 21-Feb-2012 deadbea7 <deadbea7 [AT] gmail [DOT] com>
#  - Forked gpgr
#  - Updated to pass a stream of data and encrypt -- no need for saving unencrypted files to disk
#  - s/Gpgr::Encrypt.file/Gpgr::Encrypt.stream/
module Gpgr

  # Returns the command to execute to run GPG. It is defualted to /use/bin/env gpg 
  # which should correctly track down gpg on any UNIX-like operating system. If you
  # need to use this on Windows, simply change the method to return the path to where
  # gpg is installed.
  #
  # Of course, since grep is used in this script too, you'll need a windows version of
  # grep installed as well!
  #
  def self.command
    '/usr/bin/env gpg'
  end

  def self.version
    @version ||= `#{command} --version`.split("\n").grep(/GnuPG/).first.match(/(\d+\.\d+\.\d+)/) { $1 }.to_f
  end

  # Poor man's IO Loop.
  def self.run(options, data)
    options = [options].flatten.join(' ')

    input  = StringIO.new(data)
    output = StringIO.new('')

    closed_write = false
    chunk = 65535
    IO.popen [command, options].join(' '), :mode => 'r+' do |pgp|
      loop do

        r, w = IO.select([pgp], [pgp], [], 2)

        begin
          if w[0]
            read    = input.read(chunk)
            written = pgp.write_nonblock(read)

            if written < read.size
              input.seek(written - read.size, IO::SEEK_CUR)
            end
          end

          if r[0]
            i = output.write pgp.read_nonblock(chunk)
          end

          if input.eof?
            if !closed_write
              pgp.close_write
              closed_write = true
            end
          end

        rescue EOFError
          break
        end
      end
    end

    output.rewind
    output.read
  end

  class InvalidEmailError < StandardError; end
  class InvalidKeyError < StandardError; end

  # Encapsulates all the functionality related to encrypting a file. All of the real work
  # is done by the class GpgGileForEncryption.
  #
  module Encrypt
    
    # Takes a stream of data you want to encrypt; and returns a GpgForEncryption
    # object for you to modify with the people (e-mail addresses) you want to encrypt this
    # file for. Optionally you can specify where you want the encrypted file to be written,
    # by setting :to => some_path. Will default to wherever the current file is, with the
    # extension 'pgp' appended.
    #
    def self.stream(data)
      GpgEncryption.new(data)
    end

    # Contians the details used to encrypt specified stream, is what actually does
    # any encryption.
    # 
    class GpgEncryption

      def initialize(data)
        @clear_text = data
      end
      
      # Expects an array of e-mail addresses for people who this file file should be  
      # decryptable by. 
      #
      def for(email_addresses)
        @email_addresses = Set.new([email_addresses].flatten.map(&:downcase))
        self
      end
      
      # Encrypts the current file for the list of recipients specific (if they are valid)
      #   
      def encrypt
        keys = Gpgr::Keys.installed_public_keys.select {|key| @email_addresses.include?(key.mail)}

        unless keys.size == @email_addresses.size
          raise InvalidEmailError.new("One or more of the e-mail addresses you supplied don't have valid keys assigned!")
        end

        encrypt = keys.map {|key| "--trusted-key #{key.uid} --recipient #{key.mail}"}.push("--yes --encrypt")

        Gpgr.run encrypt, @clear_text
      end
      
    end
  end

  # Encapsulates all the functionality for dealing with GPG Keys. There isn't much here since
  # key managment isn't really one of the goals of this project. It will, however, allow you
  # to import new keys and provides a means to list existing installed keys.
  # 
  module Keys

    # Imports the key at the specified path into the keyring. Since this is
    # really running gpg --import ./path/to/key.asc, the key will be imported
    # and added to the keyring for the user executing this command.
    #
    # FIXME: RACE CONDITION HERE
    #
    def self.import(key_material)
      installed = self.installed_public_keys
      new_key = Key.parse(key_material)

      if existing = installed.find {|k| k.mail == new_key.mail}
        existing
      else
        Gpgr.run '--import --quiet --yes --no-verbose', key_material

        # Return the new key
        (self.installed_public_keys - installed).first
      end
    end

    # Simply checks to see if the e-mail address passed through as an argument has a
    # public key attached to it by checking in installed_public_keys.
    #
    def self.public_key_installed?(email)
      email = email.downcase
      !!installed_public_keys.find {|k| k.email == email}
    end

    # Raw list of public keys
    #
    def self.installed_public_keys
      pubkey_prefix = Gpgr.version >= 2.0 ? 'uid' : 'pub'

      `#{Gpgr.command} -q --no-verbose --list-public-keys --with-colons`.
        force_encoding('utf-8').split("\n").grep(/^#{pubkey_prefix}.+\<?.+@.+\>?/).
        map {|row| Key.new(row)}
    end
  end

  class Key
    include Comparable

    def initialize(row)
      if row =~ /:/

        key = row.split(':')
        @mail = key[9].downcase
        @mail = $1 if @mail =~ /.+<(.+@.+)>/

        @uid = if Gpgr.version < 2.0
          key[4]
        else
          `#{Gpgr.command} --list-public-keys --with-colons "#@mail"`.
            force_encoding('utf-8').split("\n").grep(/^pub/).first.split(':')[4] rescue nil
        end
      else

        @uid, @mail = row.scan(/pub\s+ \w+\/(\w+) .+ <?(.+@[^>]+)/).first
        @mail.chomp!
      end
    end

    attr_reader :uid
    attr_reader :mail
    alias :email :mail

    def <=>(another)
      mail <=> another.mail
    end

    def hash
      uid.hash
    end

    def eql?(other)
      uid.eql?(other.uid)
    end

    def self.parse(stream)
      row = if Gpgr.version < 2.0
        Gpgr.run("--with-colons", stream)
      else
        Gpgr.run("--keyid-format long", stream)
      end

      raise InvalidKeyError, 'Invalid key' if row.size.zero?
      new(row)
    end
  end

end

