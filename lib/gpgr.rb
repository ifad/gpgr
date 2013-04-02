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
    @version ||= run('--version').match(/gpg \(GnuPG\) (\d+\.\d+\.\d+)/) { $1.to_f }
  end

  # Poor man's IO Loop.
  def self.run(options, input = nil)
    options = [options].flatten.join(' ')

    input  = StringIO.new(input.to_s)
    output = StringIO.new('')

    closed_write = false
    chunk = 65535
    IO.popen [command, options].join(' '), :mode => 'r+' do |pgp|
      loop do

        r = [pgp]
        w = input.eof? ? [] : [pgp] # Select for write only if we have still data to send
        r, w = IO.select(r, w, [], 10)

        begin
          if w[0]
            read    = input.read(chunk)
            written = pgp.write_nonblock(read)

            if written < read.size
              input.seek(written - read.size, IO::SEEK_CUR)
            end
          end

          if r[0]
            output.write pgp.read_nonblock(chunk)
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

  def self.encrypt(data)
    Encrypt.new(data)
  end

  # Encapsulates all the functionality related to encrypting a file. All of the real work
  # is done by the class GpgGileForEncryption.
  #
  class Encrypt
    def initialize(data)
      @data = data
      @keys = Set.new
    end

    # Expects an array of e-mail addresses for people who this file file should be
    # decryptable by.
    #
    def for(*recipients)
      recipients.flatten.each do |email|
        unless key = Key.find(email)
          raise InvalidEmailError, "Public key not found: #{email}"
        end

        @keys << key
      end

      self
    end

    # Encrypts the current file for the list of recipients specific (if they are valid)
    #
    def result
      recipients = @keys.map {|key| "--recipient #{key.mail}"}

      Gpgr.run recipients.push("--yes --encrypt"), @data
    end
  end

  class Key
    include Comparable

    PUB_RE = /^pub:[\w-]:\d+:\d+:(?<uid>[0-9A-f]+):\d+:.*?:.*?:.*?:(?<mail>.*?):/
    UID_RE = /^uid:[\w-]:\d*:\d*:(?<uid>[0-9A-f]*):\d+:.*?:.*?:.*?:(?<mail>.*?):/

    def initialize(row)
      [PUB_RE, UID_RE].each do |re|
        if match = row.match(re)
          @uid  ||= match[:uid]  if match[:uid].size > 0
          @mail ||= match[:mail] if match[:mail].size > 0
        end
      end

      if @uid.nil? || @mail.nil?
        raise InvalidKeyError, "Unable to parse #{row.inspect}"
      end

      if match = @mail.match(/(?<name>.+)\<(?<mail>.+@.+)\>/)
        @name = match[:name].strip
        @mail = match[:mail]
      end
    end

    attr_reader :uid, :mail, :name
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

    class << self
      def parse(stream)
        row = Gpgr.run('--with-colons --fixed-list-mode', stream)
        raise InvalidKeyError, 'Invalid key' if row.size.zero?
        new(row)
      end

      def find(recipient)
        all(recipient).first
      end

      def all(*recipients)
        public_keys(recipients.flatten)
      end

      def import(key_material)
        key = parse(key_material)

        # Already installed
        unless find(key.mail)
          # Import
          Gpgr.run '--import --quiet --yes --no-verbose', key_material

          key = find(key.mail)
          raise InvalidKeyError, 'Unable to import key' unless key # TODO better error handling

          # Mark the key as trusted
          Gpgr.run "--trusted-key #{key.uid} --recipient #{key.mail} --encrypt"
        end

        return key
      end

      private
        def public_keys(*args)
          output = Gpgr.run(['--list-public-keys --with-colons --fixed-list-mode'].concat(args)).
            force_encoding('utf-8')

          # Group pub:: and uid:: stanzas
          return output.scan(/pub:[oqmfu-].+?(?=pub|\Z)/m).map {|k| Key.new(k)}
        end

    end
  end

end

