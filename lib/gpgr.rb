# Gpgr by Ryan Stenhouse <ryan@ryanstenhouse.eu>, March 2010
# on behalf of Purchasing Card Consultancy Limited.
#
# Rewrite by Marcello Barnaba <vjt@openssl.it>
#
# gpgr is a very light interface to the command-line GPG (GNU
# Privacy Guard) tool which is soley concerned with making it
# as easy as possible to encrypt files with one (or more) public
# keys.
#
# Usage:
#
#   require 'gpgr'
#
#   # Encrypt
#   #
#   recipients = %w( foo@example.com bar@example.com )
#   Gpgr.encrypt("clear text").for(recipients).result
#
#   # Import public key
#   #
#   Gpgr::Key.import(File.read('/path/to/pubkey'))
#
#   # List available public keys
#   #
#   Gpgr::Key.all
#
#   # Find public key for given recipient
#   #
#   Gpgr::Key.find('foo@example.com')
#
#   # Encrypt for every single person you have a public key for
#   #
#   Gpgr.encrypt("clear text").for(Gpgr::Keys.all)
#
#   # Decrypt
#   #
#   Gpgr.decrypt("ciphered data")
#
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

  def self.decrypt(data)
    Decrypt.new(data)
  end

  # Encapsulates all the functionality related to encrypting data.
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
      recipients.flatten.each do |rcpt|
        mail = rcpt.respond_to?(:mail) ? rcpt.mail : rcpt
        key  = Key.find(mail)
        raise InvalidEmailError, "Public key not found: #{mail}" unless key

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

  class Decrypt
    def initialize(data)
      @data = data
    end

    def result
      Gpgr.run '--batch --decrypt', @data
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

