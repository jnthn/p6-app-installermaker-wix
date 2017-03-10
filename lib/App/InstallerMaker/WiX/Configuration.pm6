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

    has Versions $.versions;
    has $.install-location;
    has $.application;

    method new() {
        die "Use the parse method to parse a configuration";
    }

    method parse($configuration-file) {
        my $yaml = load-yaml(slurp($configuration-file));
        self.bless(|%$yaml)
    }

    submethod BUILD(:$!install-location, :$!application, :$versions, :$wix,
                    *%other) {
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
        if %other {
            die "Unexpected top-level key '{%other.keys[0]}'";
        }
    }
}
