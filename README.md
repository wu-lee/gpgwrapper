# NAME

gpgwrapper - simplified batch-mode GPG encryption for scripts

# SYNOPSIS

Let's say you've created a keychain (as described later), in a
directory path denoted by `$keyhome` in the following examples.

Import a GPG public key into the encrypting machine's keychain:

    gpgwrapper -ik $keydir <pubkey

Then you can encrypt like this:

    gpgwrapper -ek $keydir <file >encoded

Then on a machine with the private key installed in `$keyhome` you can
decrypt like this:

    gpgwrapper -dk $keydir <encoded >decoded


# DESCRIPTION

This script executes gpg in a way which can be used in scripts and
cron jobs, without human intervention.  GPG by itself is not designed
to make this easy, instead it is designed for manual interaction with
a human via a terminal.  See for
example [Revisiting the GnuPG discussion][1] on the Mailpile blog.

[1]: https://www.mailpile.is/blog/2015-02-26_Revisiting_the_GnuPG_discussion.html

The main use-case in mind when writing this script was for encrypting
large archives for storage in public or semi-public places like S3,
using only a public key which resides on the server creating the
archives.  The private key is kept safe elsewhere, for use only when
restoring the archives.


# USAGE

Before anything else, you need a keychain directory.  You *can* use
the default location used by GnuPG but this may interfere with other
keys being used by the same user account. For encrypting at least,
you're advised to select another path, either setting it beforehand
with the `GNUPGHOME` environment variable, or overriding it with the
`-k` option.  When `-k` is supplied, the script will attempt to create
the supplied `<path>` if not present, and make it unreadable by all
except the current effective user. Otherwise the keychain directory is
assumed to be set up already.

Given that, these are the basic operations.


    gpgwrapper -i [ -r <keyid> ] [ -k <path> ]

Imports a GPG key read on stdin into the keychain.  You can use this
to import a key exported from another GPG keychain. (Note, the trust
model is `always`, so this won't explicitly mark it trusted, because
all keys are trusted.) 


    gpgwrapper -e [ -r <keyid> ] [ -k <path> ]

Encrypts stdin to stdout using a public key from the keychain
identified by `<keyid>` (it defaults to using the first key listed if
the `-r` option is omitted.)


	gpgwrapper -d [ -k <path> ] [ -p <passphrase-source> ]

Decrypts stdin to stdout using the private key identified by the
encrypted stream, which must be in the keychain.

By default if a passphrase is needed, and `gpg-agent` doesn't already
know it, the decryption will fail.  However if `-p` is supplied with
either a numeric file-descriptor, or the path to an exising file, the
passphrase will be read from that (and `gpg-agent` will remember it
forthwith)

    gpgwrapper -v

Prints out version information for this script and GPG.


    gpgwrapper -h
	
Prints this usage.


# PREPARING KEYS

Create a keypair as normal with gnupg

```
$ gpg2 --gen-key
[ answer the questions interactively here... ]

[ GPG prints the new key's info... ]
pub   2048R/44DFC561 2019-01-09
      Key fingerprint = AFE1 5370 4920 711D 3C39  5F97 AE80 0A29 44DF C561
uid                  Foo Bar <foo@example.com>
sub   2048R/D35B5383 2019-01-09

```

If you have one already, you can list public keys and their IDs with

    $ gpg2 --list-keys

Export the public key you want to use. Use the public key ID printed
when it was generated: the short ID is the second number after
`pub`. The full ID is the fingerprint, minus spaces.

    $ gpg2 --export --armor 44DFC561 >pub.key

Now you can copy the resulting file onto the target machine, and
import it into the keychain. Note, the path defined by `$keydir` does
not have to exist in advance if you use `gpgwrapper`'s `-k` option.

    $ gpgwrapper -ik "$keydir" <pub.key

In general, you should *not* keep the private key on the target
machine.  Keep this safe elswhere, and only use it when decrypting.
GPG can be used to manage this directly.

See USAGE for how to encrypt and decrypt.
   

# IMPLEMENTATION NOTES

Alternatives to GnuPG were sought, because of the difficulty of using
it in scripts. For
example: [OpenSSL][11], [NaCl][13], [libsodium][14], [gpgme-tool][7],
[reop][10], [rgpg][4], [enchive][5], [python-gpg][8],
[python-gpgme][18], [Perl GnuPG][15], [Crypt::GPG][16],
[Crypt::GpgME][17], and [ruby-gpg][9]. All of these
either don't do what I want (OpenSSL), or are too difficult to use
casually (NaCl, GpgME etc.), or aren't widely used (Enchive, Reop
etc.)  or just add extra layers and dependencies I can do without.

I also wrote [hencrypt][12] as an excercise in writing a hybrid
encryption tool in Bash wrapping `openssl`, but ultimately haven't
used it: it seems too much out on a limb, and Bash may be adequate but
is not well suited for this job. Instead I've opted for the more
direct and minimal wrapping of `gpg` employed here.  The relative
complexity and awkwardness of GPG's key management is not avoided but
it can be minimised enough for our purposes, and the various
command-line options hidden.

I use `gpg` version2 as it has options for controlling pinentry. Since
for security we deliberately avoid using the `PATH` to find
executables, it is assumed that this is at `/usr/bin/gpg`. If this is
not the case you may need to either insert a symlink to the right
executable, or modify the script appropriately for your system.

I use built-in Bash commands instead of external commands where
possible, to reduce dependencies.

When preparing the keychain path supplied to the `-k` option, `mkdir`,
`chmod` and `chown` are all invoked.  They are also invoked explicitly
with a full path, and are assumed to be in `/bin/`

The `pipefail` and `errexit` options are enabled, to ensure all errors
result in the script terminating with an error code.

For security, we avoid placing any sensitive information either in:

 - the process environment
 - parameters of subcommands
 - temporary files or otherwise


# TESTS

There are some test cases in the `test/` directory.

These use the [bats][3] testing framework. This can be installed a
number of ways, and a `package.json` file is included to support
installation with `npm` (although this is not mandatory). A bonus of
adding a `package.json` is that it provides licence and version
management.

    npm install --save-dev bats

If you use npm, then you can run the tests like this:

    npm test

Or directly like this:

    (cd tests; bats .)


# CAVEATS / DISCLAIMER

Other than the caveats below, this script works correctly to the best
of my knowledge. However, as ever with open source software: inspect
the source code and use at your own risk.

## GPG < v2.1.11 are not supported.

This script does not support `gpg` versions < 2.1.11, as it requires
the `--pinentry-mode` option.

Therefore the executable `/usr/bin/gpg2` will be used if it exists,
and `/usr/bin/gpg` otherwise (since some systems can install
both). The output with the `--version` option is checked, and a
warning printed if it is unsupported.

If you see this warning you may need to install the correct version
and either symlink it to one of these paths, or alter the GPG variable
assignment in the script.

## Loopback pinentry should be enabled

For versions of `gpg-agent` <2.1.12 loopback pinentry is not enabled
by default, and you need to enable it to decrypt without a passphrase
prompt by adding `allow-loopback-pinentry` into
`$GNUPGHOME/gpg-agent.conf` and restarting it with `gpgconf --reload
gpg-agent`

https://lists.gnutls.org/pipermail/gnupg-devel/2016-November/032093.html

Note that `gpgagent` will insert this option for you whenever it
creates a new keychain directory because the `-k` option is supplied.

Otherwise, to decrypt, you need to supply gpg-agent with your
passphrase beforehand by using `gpg` directly and entering it into the
pin-entry dialog which pops up. (This dialog is disabled in
`gpgwrapper`.)

# REQUIREMENTS

 - `/usr/bin/gpg2` or `/usr/bin/gpg`
 - `/bin/bash`
 - `/bin/mkdir`
 - `/bin/chown`
 - `/bin/chmod`

The script aims to be self-contained so far as possible, and
deliberately does not use any other non built-in commands than these.


# BUGS / CONTRIBUTIONS

See the project page at https://github.com/wu-lee/gpgwrapper


# AUTHOR / CREDITS

Original author: [Nick Stokoe][2], January 2019

[2]: https://github.com/wu-lee
[3]: https://github.com/bats-core/bats-core "A testing framework for Bash"
[4]: https://github.com/rcook/rgpg "Interfaces with GPG to avoid interacting with default keyring"
[5]: https://github.com/skeeto/enchive "A simple CLI encyption tool"
[6]: https://nullprogram.com/blog/2017/03/12/
[7]: http://manpages.ubuntu.com/manpages/cosmic/man1/gpgme-tool.1.html "A socket API for gpgme"
[8]: https://launchpad.net/ubuntu/bionic/amd64/python-gpg "Python API for GpgME (the official one at the time of writing)"
[9]: https://github.com/ueno/ruby-gpgme "Ruby API for GpgME"
[10]: https://https.www.google.com.tedunangst.com/flak/post/reop "Another encryption tool"
[11]: https://www.openssl.org/ "OpenSSL"
[12]: https://github.com/wu-lee/hencrypt "Bash wrapper implementing hybrid-encryption using openssl"
[13]: https://nacl.cr.yp.to/ "A modern crypto library"
[14]: https://libsodium.gitbook.io/doc/ "An cross-platform fork of NaCl"
[15]: https://metacpan.org/pod/GnuPG "Perl API for GnuPG"
[16]: https://metacpan.org/pod/Crypt::GPG "Perl API for GnuPG"
[17]: https://metacpan.org/pod/Crypt::GpgME "Perl API for GPGME"
[18]: https://launchpad.net/ubuntu/+source/pygpgme "Python API for GpgME"
