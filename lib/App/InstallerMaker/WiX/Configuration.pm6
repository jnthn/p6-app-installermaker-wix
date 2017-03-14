use YAMLish;

class App::InstallerMaker::WiX::Configuration {
    class Versions {
        has $.rakudo;
        has $.nqp;
        has $.moar;

        submethod BUILD(:$!rakudo, :$!nqp, :$!moar, *%other) {
            with $!rakudo {
                $!nqp //= $_;
                $!moar //= $_;
            }
            else {
                die "Missing 'rakudo' key in version section";
            }
            if %other {
                die "Unexpected version key '{%other.keys[0]}'";
            }
        }
    }

    class WiXOptions {
        has $.guid;
        has $.name;
        has $.manufacturer;
        has $.version;
        has $.language;
        has $.component-guid;

        submethod BUILD(:$!guid = no-key('guid'), :$!name = no-key('name'),
                        :$!manufacturer = no-key('manufacturer'),
                        :$!version = no-key('version'), :$!language = '1033',
                        :$!component-guid = no-key('component-guid'),
                        *%other) {
            if %other {
                die "Unexpected key '{%other.keys[0]}' in wix section";
            }
        }

        sub no-key($key) {
            die "wix section is missing required key '$key'"
        }
    }

    has Versions $.versions;
    has $.install-location;
    has $.application;
    has $.msi;
    has @.expose-entrypoints;
    has WiXOptions $.wix;

    method new() {
        die "Use the parse method to parse a configuration";
    }

    method parse($configuration-file) {
        my $yaml = load-yaml(slurp($configuration-file));
        self.bless(|%$yaml)
    }

    submethod BUILD(:$!install-location, :$!application, :$versions, :$wix,
                    :$!msi = 'output.msi', :@!expose-entrypoints, *%other) {
        with $versions {
            when Map {
                $!versions = Versions.new(|%$_);
            }
            die "Malformed 'versions' section"
        }
        else {
            die "Missing top-level key 'versions'";
        }
        without $!install-location {
            die "Missing top-level key 'install-location'";
        }
        without $!application {
            die "Missing top-level key 'application'";
        }
        with $wix {
            when Map {
                $!wix = WiXOptions.new(|%$_);
            }
            die "Malformed 'wix' section"
        }
        else {
            die "Missing top-level key 'wix'";
        }
        if %other {
            die "Unexpected top-level key '{%other.keys[0]}'";
        }
    }
}
