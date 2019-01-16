#!/usr/bin/env bats # -*- shell-script -*-

function loop_over_options {
    # Valid options, just incompatible
    for opts in -{d,e,i,v,h}{d,e,i,v,h}; do
        run ../gpgwrapper $opts data/key1
	# printf "debug: $status <- %s %s\n" $opts "$output" >&3
        [ "$status" -ne 0 ] || return 1
        grep 'exiting: can only use one of -d -e -i -h or -v' <<<$output || return 1
    done
    return 0
}


# test recipient when there are multiple keys

# bad options: nonesuch key in -r

# bad options: no public key in -r

# empty r

# @test "missing encryption key" {
#     run GPGWRAPPER_IO -e tmp/missing data/lorem tmp/enc
#     [ "$status" -ne 0 ]
#     grep 'exiting: no such file: tmp/missing' <<<$output
# }

# @test "missing decryption key" {
#     run GPGWRAPPER_IO -d tmp/missing data/lorem tmp/dec
#     [ "$status" -ne 0 ]
#     grep 'exiting: no such file: tmp/missing' <<<$output
# }

# @test "empty keychain" {
#     printf "" >tmp/empty
#     run GPGWRAPPER_IO -e tmp/empty data/lorem tmp/enc
#     [ "$status" -ne 0 ]
#     grep 'exiting: rsaencrypt failed' <<<$output
# }

# @test "empty file encrypting" {
#     printf "" >tmp/empty
#     run GPGWRAPPER_IO -e data/key1.pub tmp/empty tmp/enc
#     [ "$status" -eq 0 ]
#     [ -s tmp/enc ]
# }


# -----

# This wrapper exists to avoid using IO redirection params in tests
# (because bats uses the 'run' wrapper command).  It calls gpgwrapper
# with the last two params defining the file redirection for stdin and
# stdout, respectively.
#
# i.e. This:
#
#   GPGWRAPPER_IO a b c d
#
# becomes:
#
#   ../gpgwrapper a b <c >d
#
# Obviously, it is only needed when redirection is performed.
function GPGWRAPPER_IO {
    local out=${@: -1:1}
    local in=${@: -2:1}
#    echo "gpgwrapper ${@:1:$#-2} <$in >$out" >&3
    ../gpgwrapper "${@:1:$#-2}" <"$in" >"$out"
}


# test normal usage
function standard_usage {
    ../gpgwrapper -ik tmp/pk < data/pub1.key &&
    ../gpgwrapper -ik tmp/sk < data/sec1.key &&
    ../gpgwrapper -ek tmp/pk <data/lorem >tmp/enc1 &&
    ../gpgwrapper -dk tmp/sk -p 9 9<<<passphrase <tmp/enc1 >tmp/lorem
}

# round trip encrypt/decrypt with specified key index
# Note: uses same keychain file
function round_trip {
    local ix=${1:?}
    ../gpgwrapper -ek tmp/sk -r $(<data/$ix.id) <data/lorem >tmp/enc$ix &&
    ../gpgwrapper -dk tmp/sk -r $(<data/$ix.id) -p data/$ix.passphrase <tmp/enc$ix >tmp/lorem
}

function setup {
    # Clear gpg-agent passphrase cache
    GNUPGHOME=tmp/sk gpgconf --reload gpg-agent
    
    # Recreate the tmp directory
    rm -rf tmp
    mkdir -p tmp
}

@test "standard usage case: create, encode, restore" {
    run standard_usage 1 passphrase
    [ "$status" -eq 0 ]
    diff -q data/lorem tmp/lorem
}

@test "resist PATH hijacking" {
    # the dummy dir contains fake commands like cat, base64, openssl
    PATH=dummy:$PATH run standard_usage 1 passphrase
    [ "$status" -eq 0 ] || echo rc $status $output
    diff -q data/lorem tmp/lorem
}

@test "decrypt pre-encrypted data 1, with passphrase from descriptor" {
    ../gpgwrapper -ik tmp/sk <data/sec1.key 
    run GPGWRAPPER_IO -dk tmp/sk -p 9 data/enc1 tmp/dec1 9<<<passphrase
    [ "$status" -eq 0 ]
    diff -q data/lorem tmp/dec1
}

@test "decrypt pre-encrypted data 1, with passphrase from file" {
    ../gpgwrapper -ik tmp/sk <data/sec1.key
    printf "passphrase\n" >tmp/passphrase
    run GPGWRAPPER_IO -dk tmp/sk -p tmp/passphrase data/enc1 tmp/dec1
    [ "$status" -eq 0 ]
    diff -q data/lorem tmp/dec1
}

@test "decrypt pre-encrypted data 1, with passphrase from numeric file" {
    ../gpgwrapper -ik tmp/sk <data/sec1.key
    printf "passphrase\n" >9
    run GPGWRAPPER_IO -dk tmp/sk -p 9 data/enc1 tmp/dec1
    [ "$status" -eq 0 ]
    rm 9
    diff -q data/lorem tmp/dec1
}

@test "decrypt pre-encrypted data 2" {
    ../gpgwrapper -ik tmp/sk <data/sec2.key 
    run GPGWRAPPER_IO -dk tmp/sk -p 9 data/enc2 tmp/dec2 9<<<passphrase2
    [ "$status" -eq 0 ]
    diff -q data/lorem tmp/dec2
}

@test "encrypt with key specified by -r with multiple keys" {
    ../gpgwrapper -ik tmp/sk <data/sec1.key 
    ../gpgwrapper -ik tmp/sk <data/sec2.key
    
    run round_trip 1
    [ "$status" -eq 0 ]
    diff -q data/lorem tmp/lorem
    
    run round_trip 2
    [ "$status" -eq 0 ]
    diff -q data/lorem tmp/lorem
}

@test "wrong key decrypt failure" {
    ../gpgwrapper -ik tmp/sk <data/sec2.key 
    # sec2.key is wrong decrypt key for pub1.key
    run GPGWRAPPER_IO -dk tmp/sk data/enc1 tmp/dec
    [ "$status" -ne 0 ]
    grep 'gpg: encrypted with RSA key' <<<$output
    grep 'gpg: decryption failed: No secret key' <<<$output
    grep 'exiting: decryption failed' <<<$output
}

@test "wrong passphrase decrypt failure" {
    ../gpgwrapper -ik tmp/sk <data/sec2.key 
    # 'passphrase' is wrong passphrase for sec2.key
    run GPGWRAPPER_IO -dk tmp/sk -p 9 data/enc2 tmp/dec2 9<<<passphrase
    [ "$status" -ne 0 ]
    grep 'gpg: public key decryption failed: Bad passphrase' <<<$output
    grep 'gpg: decryption failed: No secret key' <<<$output
    grep 'exiting: decryption failed' <<<$output
}

@test "no options or parameters" {
    run ../gpgwrapper
    [ "$status" -ne 0 ]
    grep 'exiting: you must supply one of the options -d -e -i -v or -h' <<<$output
}

@test "too many parameters" {
    # Valid options, just too many.
    run GPGWRAPPER_IO -ik tmp/sk data/pub1.key data/pub1.key tmp/out
    [ "$status" -ne 0 ]
    grep 'exiting: superfluous parameters were supplied' <<<$output
}

@test "incompatible options" {
    # bats uses preprocessing magic, so doesn't support looping tests,
    # and we need to loop in a helper function
    run loop_over_options
    [ "$status" -eq 0 ]
}

@test "help" {
    run ../gpgwrapper -h
    [ "$status" -eq 0 ]
    grep 'USAGE:' <<<$output
}

@test "bad options: nonnumeric, non-file -p" {
    ../gpgwrapper -ik tmp/sk <data/sec1.key
    mkdir tmp/passphrase
    run GPGWRAPPER_IO -dk tmp/sk -p tmp/passphrase data/enc1 tmp/dec1
    [ "$status" -ne 0 ]
    grep 'exiting: -p option argument is neither a file nor numeric' <<<$output
}

@test "bad options: missing -p argument" {
    ../gpgwrapper -ik tmp/sk <data/sec1.key
    run GPGWRAPPER_IO -dk tmp/sk -p data/enc1 tmp/dec1
    [ "$status" -ne 0 ]
    grep 'gpgwrapper: option requires an argument -- p' <<<$output
}

@test "bad options: negative -p" {
    ../gpgwrapper -ik tmp/sk <data/sec1.key
    run GPGWRAPPER_IO -dk tmp/sk -p -9 data/enc1 tmp/dec1
    [ "$status" -ne 0 ]
    grep 'exiting: -p option argument is neither a file nor numeric' <<<$output
}

@test "bad options: empty -p option" {
    ../gpgwrapper -ik tmp/sk <data/sec1.key
    run GPGWRAPPER_IO -dk tmp/sk -p data/enc2 tmp/dec2
    [ "$status" -ne 0 ]
    grep 'gpgwrapper: option requires an argument -- p' <<<$output
}

@test "bad options: pre-existing file for -k" {
    touch tmp/pk
    run GPGWRAPPER_IO -ek tmp/pk data/lorem tmp/out
    [ "$status" -ne 0 ]
    grep 'exiting: cannot create keychain directory' <<<$output
}

@test "bad options: empty dir for -k" {
    mkdir tmp/pk
    chmod 0700 tmp/pk
    run GPGWRAPPER_IO -ek tmp/pk data/lorem tmp/out
    [ "$status" -ne 0 ]
    grep 'exiting: encryption failed' <<<$output
}

@test "bad options: unknown key with -r while encrypting" {
    ../gpgwrapper -ik tmp/pk <data/pub1.key 
    run GPGWRAPPER_IO -ek tmp/pk -r $(<data/2.id) data/lorem tmp/enc1
    [ "$status" -ne 0 ]
    grep 'No public key' <<<$output
    grep 'exiting: encryption failed' <<<$output
}

@test "bad options: unknown key while decrypting" {
    ../gpgwrapper -ik tmp/sk <data/sec1.key 
    run GPGWRAPPER_IO -dk tmp/sk -p data/2.passphrase data/enc1 tmp/dec1
    [ "$status" -ne 0 ]
    grep 'No secret key' <<<$output
    grep 'exiting: decryption failed' <<<$output
}

@test "bad options: unknown key with -r while decrypting" {
    ../gpgwrapper -ik tmp/sk <data/sec1.key 
    run GPGWRAPPER_IO -dk tmp/sk -r $(<data/2.id) -p data/2.passphrase data/enc1 tmp/dec1
    [ "$status" -ne 0 ]
    grep 'No secret key' <<<$output
    grep 'exiting: decryption failed' <<<$output
}


@test "Use GNUPGHOME if -k unused" {
    ../gpgwrapper -ik tmp/sk <data/sec1.key 
    GNUPGHOME=tmp/sk run round_trip 1
    [ "$status" -eq 0 ]
    diff -q data/lorem tmp/lorem
}
