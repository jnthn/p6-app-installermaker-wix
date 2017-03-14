unit module App::InstallerMaker::WiX::InstallerBuilder;
use App::InstallerMaker::WiX::Configuration;

class Task {
    has Str $.id;
    has Str $.name;
    has Str @.dependencies;
    has Bool $.success is rw;
    has Str $.error is rw;
}
class CommandTask is Task {
    has Str $.command;
}
class GeneratorTask is Task {
    has &.generator;
}

my @all-tasks = [
    CommandTask.new(
        :id<cleanup>, :name('Remove target directory if it exists'),
        :command('rd /s /q $INSTALL-LOCATION || echo')
    ),
    CommandTask.new(
        :id<fetch-moarvm>, :name('Fetch MoarVM'),
        :command('git clone git@github.com:MoarVM/MoarVM.git $TMP\\MoarVM && ' ~
                 'cd $TMP\\MoarVM && git checkout $MOAR-VERSION')
    ),
    CommandTask.new(
        :id<fetch-nqp>, :name('Fetch NQP'),
        :command('git clone git@github.com:perl6/nqp.git $TMP\\nqp && ' ~
                 'cd $TMP\\nqp && git checkout $NQP-VERSION')
    ),
    CommandTask.new(
        :id<fetch-rakudo>, :name('Fetch Rakudo'),
        :command('git clone git@github.com:rakudo/rakudo.git $TMP\\rakudo && ' ~
                 'cd $TMP\\rakudo && git checkout $RAKUDO-VERSION')
    ),
    CommandTask.new(
        :id<configure-moarvm>, :name('Configure MoarVM'),
        :dependencies<cleanup fetch-moarvm>,
        :command('cd $TMP\\MoarVM && perl Configure.pl --prefix=$INSTALL-LOCATION'),
    ),
    CommandTask.new(
        :id<build-moarvm>, :name('Build MoarVM'),
        :dependencies<configure-moarvm>,
        :command('cd $TMP\\MoarVM && nmake install'),
    ),
    CommandTask.new(
        :id<configure-nqp>, :name('Configure NQP'),
        :dependencies<fetch-nqp build-moarvm>,
        :command('cd $TMP\\nqp && perl Configure.pl --prefix=$INSTALL-LOCATION'),
    ),
    CommandTask.new(
        :id<build-nqp>, :name('Build NQP'),
        :dependencies<configure-nqp>,
        :command('cd $TMP\\nqp && nmake install'),
    ),
    CommandTask.new(
        :id<configure-rakudo>, :name('Configure Rakudo'),
        :dependencies<fetch-rakudo build-nqp>,
        :command('cd $TMP\\rakudo && perl Configure.pl --prefix=$INSTALL-LOCATION'),
    ),
    CommandTask.new(
        :id<build-rakudo>, :name('Build Rakudo'),
        :dependencies<configure-rakudo>,
        :command('cd $TMP\\rakudo && nmake install'),
    ),
    CommandTask.new(
        :id<fetch-zef>, :name('Fetch Zef'),
        :command('git clone https://github.com/ugexe/zef.git $TMP\\zef')
    ),
    CommandTask.new(
        :id<install-zef>, :name('Install Zef'),
        :dependencies<fetch-zef build-rakudo>,
        :command('cd $TMP\\zef && $INSTALL-LOCATION\\bin\\perl6.bat -Ilib bin/zef --/test install .')
    ),
    CommandTask.new(
        :id<install-application>, :name('Install Application'),
        :dependencies<install-zef>,
        :command('$INSTALL-LOCATION\\bin\\perl6 ' ~
            '$INSTALL-LOCATION\\share\\perl6\\site\\bin\\zef ' ~
            '--/test --install-to=site install $APPLICATION')
    ),
    GeneratorTask.new(
        :id<generate-entrypoints>, :name('Generating entrypoint scripts'),
        :dependencies<install-application>,
        :generator(&generate-entrypoints)
    ),
    CommandTask.new(
        :id<heat-files>, :name('Gathering files'),
        :dependencies<install-application generate-entrypoints>,
        :command('heat dir $INSTALL-LOCATION -gg -sfrag -cg ApplicationFiles ' ~
            '-dr INSTALLROOT -srd -out files.wxs')
    ),
    CommandTask.new(
        :id<candle-files>, :name('Compiling files install module'),
        :dependencies<heat-files>,
        :command('candle files.wxs')
    ),
    GeneratorTask.new(
        :id<product-wxs>, :name('Generating product module XML'),
        :generator(&generate-prodcut-wxs)
    ),
    CommandTask.new(
        :id<candle-product>, :name('Compiling product install module'),
        :dependencies<product-wxs>,
        :command('candle product.wxs')
    ),
    CommandTask.new(
        :id<msi>, :name('Linking MSI'),
        :dependencies<candle-files candle-product>,
        :command('light -b $INSTALL-LOCATION -ext WixUIExtension files.wixobj ' ~
            'product.wixobj -o $MSI')
    )
];

sub build-installer(App::InstallerMaker::WiX::Configuration $conf, $work-dir) is export {
    my %vars =
        TMP => $work-dir,
        MOAR-VERSION => $conf.versions.moar,
        NQP-VERSION => $conf.versions.nqp,
        RAKUDO-VERSION => $conf.versions.rakudo,
        INSTALL-LOCATION => $conf.install-location,
        APPLICATION => $conf.application,
        MSI => $conf.msi;
    sub subst-vars($command) {
        $command.subst(/\$(<[\w-]>+)/, { %vars{$0} // die "Unknown var $0" }, :g)
    }

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
                $active++;
                if $task ~~ CommandTask {
                    my $proc = Proc::Async.new("cmd.exe", "/c", subst-vars($task.command));
                    my $out = '';
                    my $err = '';
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
                else {
                    whenever start $task.generator()($conf) {
                        $task.success = True;
                        emit $task;
                        %completed-ids{$task.id} = True;
                        $active--;
                        add-doable-work();
                        QUIT {
                            default {
                                $task.success = False;
                                $task.error = ~$_;
                                $active--;
                                emit $task;
                            }
                        }
                    }
                }
            }
        }
    }
}

sub generate-prodcut-wxs($conf) {
    my $paths = $conf.expose-entrypoints
        ?? '[INSTALLROOT]'
        !! '[INSTALLROOT]bin;[INSTALLROOT]share\\perl6\\site\\bin';
    spurt 'product.wxs', Q:c:to/XML/
        <?xml version="1.0" encoding="utf-8"?>
        <Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
            <Product Id="*" Name="{$conf.wix.name}" Manufacturer="{$conf.wix.manufacturer}"
                     Version="{$conf.wix.version}" Language="{$conf.wix.language}"
                     UpgradeCode="{$conf.wix.guid}">
                <Package Compressed="yes" InstallerVersion="200" />

                <Property Id="ROOTDRIVE"><![CDATA[{$conf.install-location.substr(0, 3)}]]></Property>

                <Directory Id="TARGETDIR" Name="SourceDir">
                    <Directory Id="INSTALLROOT" Name="{$conf.install-location.substr(3)}" />
                    <Component Id="ApplicationPath" Guid="{$conf.wix.component-guid}">
                        <Environment Id="MYPATH" Name="PATH" Action="set" Part="last"
                            Value="{$paths}" System="no" Permanent="no" />
                    </Component>
                </Directory>

                <Feature Id="ProductFeature" Level="1" Title="{$conf.wix.name}">
                    <ComponentGroupRef Id="ApplicationFiles" />
                    <ComponentRef Id="ApplicationPath" />
                </Feature>
                <Media Id="1" Cabinet="product.cab" EmbedCab="yes" />
            </Product>
        </Wix>
        XML
}

sub generate-entrypoints($conf) {
    for $conf.expose-entrypoints -> $name {
        state $base = "$conf.install-location()\\share\\perl6\\site\\bin";
        state $perl6 = "$conf.install-location()\\bin\\perl6.bat";
        my $target = "$base\\$name";
        if $target.IO.e {
            spurt "$conf.install-location()\\$name.bat", Q:c:to/NA-NA-NA-NA-BATCHFILE!/
                @echo off
                if "%OS%" == "Windows_NT" goto WinNT
                "{$perl6}" "{$target}" %1 %2 %3 %4 %5 %6 %7 %8 %9
                goto endofperl
                :WinNT
                "{$perl6}" "{$target}" %*
                if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
                if %errorlevel% == 9009 echo Could not start {$name}.
                if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
                goto endofperl
                __END__
                :endofperl
                NA-NA-NA-NA-BATCHFILE!
        }
        else {
            die "No entrypoint '$name' was installed";
        }
    }
}
