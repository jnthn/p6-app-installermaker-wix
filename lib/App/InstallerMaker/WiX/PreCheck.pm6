unit module App::InstallerMaker::WiX::PreCheck;

my constant @programs = lines q:to/CHECKS/;
    perl: perl -v
    git: git --version
    nmake: nmake /?
    cl: cl /?
    WiX heat: heat
    WiX candle: candle
    WiX light: light
    CHECKS

class Outcome {
    has Str $.name;
    has Bool $.success;
}

sub pre-check(--> Supply) is export {
    supply {
        for @programs {
            my ($name, $try) = .split(': ');
            my $try-proc = Proc::Async.new(|$try.split(' '));
            .tap: :quit{;} for $try-proc.stdout, $try-proc.stderr;
            whenever $try-proc.start {
                emit Outcome.new(:$name, :success(.exitcode == 0));
                QUIT { default { emit Outcome.new(:$name, :!success); } }
            }
        }
    }
}
