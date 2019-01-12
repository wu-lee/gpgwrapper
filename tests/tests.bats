#!/usr/bin/env bats # -*- shell-script -*-


# test normal usage
function standard_usage {
    ../gpgwrapper -ik tmp/pk < data/pub.key &&
    ../gpgwrapper -ik tmp/sk < data/sec.key &&
    ../gpgwrapper -ek tmp/pk <data/lorem >tmp/enc &&
    ../gpgwrapper -dk tmp/sk -p 9 9<<<passphrase <tmp/enc >tmp/lorem
}

function setup {
    # Recreate the tmp directory
    rm -rf tmp
    mkdir -p tmp
}

@test "standard usage case: create, encode, restore" {
    run standard_usage
    [ "$status" -eq 0 ]
    diff -q data/lorem tmp/lorem
}

