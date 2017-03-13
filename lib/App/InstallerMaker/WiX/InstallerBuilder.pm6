unit module App::InstallerMaker::WiX::InstallerBuilder;
use App::InstallerMaker::WiX::Configuration;

class Task {
    has Str $.id;
    has Str $.name;
    has Str @.dependencies;
    has Str $.command;
    has Bool $.success is rw;
    has Str $.error is rw;
}

my constant @all-tasks = [
    Task.new(
        :id<cleanup>, :name('Remove target directory if it exists'),
        :command('rd /s /q $INSTALL-LOCATION')
    ),
    Task.new(
        :id<fetch-moarvm>, :name('Fetch MoarVM'),
        :command('git clone git@github.com:MoarVM/MoarVM.git $TMP\\MoarVM && ' ~
                 'cd $TMP\\MoarVM && git checkout $MOAR-VERSION')
    ),
    Task.new(
        :id<fetch-nqp>, :name('Fetch NQP'),
        :command('git clone git@github.com:perl6/nqp.git $TMP\\nqp && ' ~
                 'cd $TMP\\nqp && git checkout $NQP-VERSION')
    ),
    Task.new(
        :id<fetch-rakudo>, :name('Fetch Rakudo'),
        :command('git clone git@github.com:rakudo/rakudo.git $TMP\\rakudo && ' ~
                 'cd $TMP\\rakudo && git checkout $RAKUDO-VERSION')
    ),
    Task.new(
        :id<configure-moarvm>, :name('Configure MoarVM'),
        :dependencies<cleanup fetch-moarvm>,
        :command('cd $TMP\\MoarVM && perl Configure.pl --prefix=$INSTALL-LOCATION'),
    ),
    Task.new(
        :id<build-moarvm>, :name('Build MoarVM'),
        :dependencies<configure-moarvm>,
        :command('cd $TMP\\MoarVM && nmake install'),
    ),
    Task.new(
        :id<configure-nqp>, :name('Configure NQP'),
        :dependencies<fetch-nqp build-moarvm>,
        :command('cd $TMP\\nqp && perl Configure.pl --prefix=$INSTALL-LOCATION'),
    ),
    Task.new(
        :id<build-nqp>, :name('Build NQP'),
        :dependencies<configure-nqp>,
        :command('cd $TMP\\nqp && nmake install'),
    ),
    Task.new(
        :id<configure-rakudo>, :name('Configure Rakudo'),
        :dependencies<fetch-rakudo build-nqp>,
        :command('cd $TMP\\rakudo && perl Configure.pl --prefix=$INSTALL-LOCATION'),
    ),
    Task.new(
        :id<build-rakudo>, :name('Build Rakudo'),
        :dependencies<configure-rakudo>,
        :command('cd $TMP\\rakudo && nmake install'),
    ),
    Task.new(
        :id<fetch-zef>, :name('Fetch Zef'),
        :command('git clone https://github.com/ugexe/zef.git $TMP\\zef')
    ),
    Task.new(
        :id<install-zef>, :name('Install Zef'),
        :dependencies<fetch-zef build-rakudo>,
        :command('cd $TMP\\zef && $INSTALL-LOCATION\\bin\\perl6.bat -Ilib bin/zef --/test --force install .')
    ),
    Task.new(
        :id<install-application>, :name('Install Application'),
        :dependencies<install-zef>,
        :command('$INSTALL-LOCATION\\share\\perl6\\site\\bin\\zef.bat ' ~
            '--/test --force --install-to=site install $APPLICATION')
    ),
    Task.new(
        :id<heat-files>, :name('Gathering files'),
        :dependencies<install-application>,
        :command('heat dir $INSTALL-LOCATION -gg -sfrag -cg Application ' ~
            '-dr INSTALLROOT -srd -out files.wxs')
    ),
    Task.new(
        :id<candle-files>, :name('Compiling files install module'),
        :dependencies<heat-files>,
        :command('candle files.wxs')
    ),
    Task.new(
        :id<candle-product>, :name('Compiling product install module'),
        :command('candle product.wxs')
    ),
    Task.new(
        :id<msi>, :name('Linking MSI'),
        :dependencies<candle-files candle-product>,
        :command('light -b $INSTALL-LOCATION -ext WixUIExtension files.wixobj ' ~
            'product.wixobj -o output.msi')
    )
];

sub build-installer(App::InstallerMaker::WiX::Configuration $conf, $work-dir) is export {
    my %vars =
        TMP => $work-dir,
        MOAR-VERSION => $conf.versions.moar,
        NQP-VERSION => $conf.versions.nqp,
        RAKUDO-VERSION => $conf.versions.rakudo,
        INSTALL-LOCATION => $conf.install-location,
        APPLICATION => $conf.application;
    sub subst-vars($command) {
        $command.subst(/\$(<[\w-]>+)/, { %vars{$0} // die "Unknown var $0" }, :g)
    }

    generate-prodcut-wxs($conf);

    supply {
        my @remaining = @all-tasks;
        my %completed-ids;
        my $active = 0;
        add-doable-work();

        sub add-doable-work() {
            my (@do-now, @new-remaining);
            for @remaining {
                if all %completed-ids{.dependencies} {
                    @do-now.push($_);
                }
                else {
                    @new-remaining.push($_);
                }
            }
            @remaining = @new-remaining;
            if !$active && @new-remaining && !@do-now {
                die "Stuck on task(s) with unsatisfied dependencies: " ~
                    @remaining.map(*.id).join(', ');
            }

            for @do-now -> $task {
                my $proc = Proc::Async.new("cmd.exe", "/c", subst-vars($task.command));
                my $out = '';
                my $err = '';
                $active++;
                whenever $proc.stdout { $out ~= $_ }
                whenever $proc.stderr { $err ~= $_ }
                whenever $proc.start {
                    if .exitcode == 0 {
                        $task.success = True;
                        emit $task;
                        %completed-ids{$task.id} = True;
                        $active--;
                        add-doable-work();
                    }
                    else {
                        $task.success = False;
                        $task.error = $err || $out;
                        $active--;
                        emit $task;
                    }
                }
            }
        }
    }
}

sub generate-prodcut-wxs($conf) {
    # XXX Lots to fill out here
    spurt 'product.wxs', Q:c:to/XML/
        <?xml version="1.0" encoding="utf-8"?>
        <Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
        </Wix>
        XML
}
