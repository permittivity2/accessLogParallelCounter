#!/usr/local/perl/bin/perl -w

# This TEMPLATE is GPL v3 licensed.  You can get this license at http://www.gnu.org/licenses/gpl-3.0.html

# Original author, writer, and content must remain in place or may be commented out.
# Original information may not be deleted except as specifically noted
#   Top line may be edited as necessary to call the interpreter as needed by your environment
# Original document kept at:
# https://docs.google.com/document/d/1bSQN1zHHfMMPLxr_nbMYTf8nb2a7HVFzLxdE4bb_d8I/edit?usp=sharing 

#############################################################################
# Author:       Jeff Gardner <perltemplate AT forge name>
# Description:  This is my generic "template" for my perl scripts
#               The "runProgram" sub is a good place to run the actual
#               program/script that is being written.  
#
# Template Version: 13.05.19
#                   13.08.20 - Minor edits for spelling/grammatical errors
#                   13.08.28 - Very minor edit to change form the word 
#                              “script” to Template above
#
# Future improvement ideas:
# 1. Make it easier to convert from threads to not threads
# 2. Add a sub for UTC time
#############################################################################

# Modules that are necessary for this template
use DateTime;
use File::Basename;
use Getopt::Long;
use File::Lockfile;
use threads;
use strict;

# The “Program Information may be edited and modified as necessary for your
# specific script
#############################################################################
# Program Information
# Author:  Jeffrey Gardner jeffrey.gardner@sprint.com
# Script version:
#                14.10.01 Alpha
#                
# Description:
# This script will look at access logs for Gemalto determine number of 
# parallel connections for each connection point 
# 
#############################################################################

#Signal handlers
$SIG{'INT'} = 'SIG_INT';
$SIG{'QUIT'} = 'SIG_INT';
$SIG{'HUP'} = 'SIG_HUP';

# Specific Program modules
# These should be modified/edited as necessary for your specific script
use DateTime;
#use Net::DNS::Dig;

#Date Time stuff that always needs to be done.  <sigh>
my $sec;        my $mday;               my $wday;
my $min;        my $mon;                my $yday;
my $hour;       my $year;               my $isdst;

# Obligatory thread variables
my $thr;
my @tids;
my %thrCleared;

# Config information
# Notice how everything is in the %configs hash for configurations?  That makes it easy later on for slurping 
# up a <programname>.conf file and just applying information.  You’ll see this later.
# I’m still having an issue of command line arguments taking precedent over conf file
# arguments.  Oh, well.  Not a big deal.
my %configs;
$configs{'verbose'}=0 if ( ! defined $configs{'verbose'} );
$configs{'basefilename'}=fileparse($0,".pl") if ( ! defined $configs{'basefilename'} );
$configs{'configFile'}="/etc/".$configs{'basefilename'}."conf" if ( ! defined $configs{'configFile'} );
$configs{'cycles'}=0 if ( ! defined $configs{'cycles'} );
$configs{'sleep'}=0 if ( ! defined $configs{'sleep'} );
$configs{'nice'}=19 if ( ! defined $configs{'nice'} );
$configs{'lockdir'}="/var/run" if ( ! defined $configs{'lockdir'} );
$configs{'lockfilename'}=$configs{'basefilename'}.".lock" if ( ! defined $configs{'lockfilename'} );
$configs{'procid'}="$$" if ( ! defined $configs{'procid'} );
$configs{'logdir'}="/var/logs" if ( ! defined $configs{'logdir'} );
$configs{'rundir'}="/opt/".$configs{'basefilename'} if ( ! defined $configs{'rundir'} );
$configs{'accessLogFile'}="/var/downloads/gemalto/09/tom.log.2014.09.19.9002" if ( ! defined $configs{'accessLogFile'} );
$configs{'startTime'}="2014-09-3 00:00:00" if ( ! defined $configs{'startTime'} );
$configs{'duration'}=3600 if ( ! defined $configs{'duration'} );

GetOptions(
        'verbose+' => \$configs{'verbose'},             'help' => \$configs{'help'},            'stop' => \$configs{'stop'}, 
        'cycles:0' => \$configs{'cycles'},              'sleep:0' => \$configs{'sleep'},        'nice:19' => \$configs{'nice'},
        'lockdir=s' => \$configs{'lockdir'},            'lockfilename=s' => \$configs{'lockfilename'}, 
        'configFile=s' => \$configs{'configFile'},      'procid' => \$configs{'procid'},
        'basefilename=s' => \$configs{'basefilename'},  'logdir=s' => \$configs{'logdir'},      'rundir=s' => \$configs{'rundir'},
        'printConfigs=s' => \$configs{'printConfigs'},
        'accessLogFile=s' => \$configs{'accessLogFile'},
        'startTime=s' => \$configs{'startTime'},
        'duration:3600' => \$configs{'duration'}
        );

setConfigsFromFile();

my $LOCKFILE = File::Lockfile->new(
        $configs{'lockfilename'},
        $configs{'lockdir'} 
        );

main();

sub main {
  warn "Running sub main\n" if ($configs{'verbose'}>1);
# Description: Having "main" is kind of a throwback to the ANSI C days.  Just thought having this would be easier to read.  Maybe not
# This sub really just does 2 things:
#       1. It looks to see if a stop has been called
#       2. Runs the "runProgram" sub as a thread

#So, let's have a small talk about main and threads.
#It's very easy to just throw a bunch of code into "main" and then move along or even to throw a bunch of 
#new threads into main but, ideally, you'd either have the meat of your code in "runProgram" or more threads or
#more sub calls in runProgram.
#Of course, every program has it's own unique necessities so do as you please

        helpDescribe() if ( defined $configs{'help'} );
        SIG_INT() if ( defined $configs{'stop'} );
        setLockFile();

        # Re-nice this to $NICE.  This may not be necessary on multi-core/cpu systems 
        my @output = `renice +$configs{'nice'} $configs{'procid'} > /dev/null 2>&1`;

        if ( $configs{'cycles'} == 0 ) {
                while ( 1 ) {
                        SIG_INT() if ( defined $configs{'stop'} );
                        if ( $#tids < 1 ) {
                                $thr=threads->create(\&runProgram($configs{'cycles'}));
                                push(@tids, $thr);
                        }
                        sleep $configs{'sleep'};
                }
        }
        else {
                while ( $configs{'cycles'} > 0 ) {
                        warn "\tEpoch of this cycle: ".time."\n" if ($configs{'verbose'} > 0);
                        SIG_INT() if ( defined $configs{'stop'} );
                        $configs{'cycles'} = $configs{'cycles'} - 1;
                        if ( $#tids < 1 ) {
                                $thr=threads->create(\&runProgram($configs{'cycles'}));
                                push(@tids, $thr);
                        }
                        sleep $configs{'sleep'};
                }
        }
        $LOCKFILE->remove;
}


sub setLockFile {
        warn "Running sub setLockFile \n" if ($configs{'verbose'}>1);
#Description: If PID in lockfile already exists then the program is exitted else 
#       A new lockfile is created
#Uses:
#       File::Lockfile

        if ( my $pid = $LOCKFILE->check ) {
                warn "\tProgram is already running with PID: $pid";
                exit;
        } else {
                $LOCKFILE->write;
        }
}
sub helpDescribe {
        warn "Running sub helpDescribe\n" if ($configs{'verbose'}>1);
# Description: Provides info to screen for user

        system 'clear';
        print "--verbose -> more uses provides more verbosity.  Be carefull.  You may get more than you bargained for.\n";
        print "--help -> uhm, you obviously know what that does. \n";
        print "\n\n";
        print "--stop -> To have the running program gracefully exit then use this switch. \n\t\tExample: --stop \n";
        print "--printConfigs -> Just print a list of all configs. \n\t\tExample: --printConfigs \n";
        print "--cycles -> To have the running program gracefully exit after a certain numbers of cycles use this switch. \n\t\tExample: --cycles ".$configs{'cycles'}."\n";
        print "--sleep -> Amount of time in seconds to pause between cycles. \n\t\tExample --sleep ".$configs{'sleep'}."\n";
        print "--nice -> Priority level to run this program.\n\t\tExample: --nice ".$configs{'nice'}."\n"; 
        printf "--lockdir -> Directory of the lockfile for this program to use.\n\t\tExample --lockdir ".$configs{'lockdir'}."\n";
        print "--lockfilename -> Name of the lockfile for this program to use. \n\t\tExample --lockfilename ".$configs{'lockfilename'}."\n";
        print "--configFile -> If defined, this will be the config file to be used. \n\t\tConfigurations in the config file override any default configs ond override command line settings, \n\t\twith the exception of the configFile setting itself.\n\t\tExample --configFile ".$configs{'configFile'}."\n";
        print "--procid -> If you want to override the process ID then use this to set it. \n\t\tSeems silly to do this but hey, whatever floats your boat..\n\t\tExample --procid ".$configs{'procid'}."\n";
        print "--basefilename -> This is really the program name.\n\t\tBy default the program name is the base filename of the initiating script.\n\t\tExample --basefilename ".$configs{'basefilename'}."\n";
        print "--logdir -> Path of directory for this program to use for logging. \n\t\tExample --logdir ".$configs{'logdir'}."\n";
        print "--rundir -> Path of directory for this program to use for various running information. \n\t\tExample --rundir ".$configs{'rundir'}."\n";

        print "--accessLogFile -> Full path of access log file to crunch through. \n\t\tExample --accessLogFile".$configs{'accessLogFile'}."\n";
        print "--startTime -> The access log file is for an entire day of logs.  We only want to analzye for a particular portion of that day. \n";
        print "\t Give the start time of when we want to analyze.  Format must be: YYYY-MM-DD-HH-MM-SS in 24hr format. ";
        print "\n\t\tExample --startTime ".$configs{'startTime'}."\n";
        print "--duration -> The access log file is for an entire day of logs.  We only want to analzye for a particular portion of that day. \n";
        print "\t Give the duration in seconds from the start time for which the logs will be analyzed.  \n\t\tExample --duration ".$configs{'duration'}."\n";
        exit 0;
}

sub setCurrentLocalDateTimeValues {
        warn "Running setCurrentLocalTimeValues \n" if ($configs{'verbose'}>1);
#Description: Sets various date time values to the current time
# I wish there was an easier way but everybody seems to have their own time methods so whatever.

        ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
        $mon+=1;                $year += 1900;
        $mday = sprintf("%02d", $mday % 100);           $mon = sprintf("%02d", $mon  % 100);
        $hour = sprintf("%02d", $hour  % 100);          $min  = sprintf("%02d", $min  % 100);           $sec = sprintf("%02d", $sec % 100);
        my @abbr = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
}

sub setConfigsFromFile{
#       warn "Running setConfigsFromFile\n" if ($configs{'verbose'}>1);
#Description: Slurps and sets configurations from the config file
        if (-e $configs{'configFile'}) {
                open FILE, $configs{'configFile'};
                while (<FILE>) {
                        warn "$_ \r is being evaluated. \n" if ($configs{'verbose'}>2);
                        if ( $_ !~ m/^#/ ) {
                                chomp;
                                my @line = split('=', $_, 2);
                                warn "$_ \r has been split. \n" if ($configs{'verbose'}>2);
                                $configs{$line[0]}=$line[1];
                                warn $line[0]." equals ".$configs{$line[0]}."\n";
                        }
                }
        } else {
                warn "$configs{'configFile'} does not exist. \n" if ($configs{'verbose'}>2);
        }
}

sub SIG_INT {
        warn "Running SIG_INT\n" if ($configs{'verbose'}>1);
#Description: This sub is run when signal interrupt is caught
#               There are lots of ways to set this up and should be modified for your particular program
#               The "stock" method is to stop each thread and then exit the program

        warn "Sig INT caught \n" if ($configs{'verbose'}>0);
        $configs{'help'}="";
        $LOCKFILE->remove;
        exit;
}

sub SIG_HUP {
        warn "Running SIG_INT\n" if ($configs{'verbose'}>1);
#Description: This sub is run when signal hup is caught
#               It reloads the config file
#               Take note that the runtime config file location is not changed
        my $runTimeConfigFile = $configs{'configFile'};

        warn "Sig HUP caught \n";
        warn "Configs will now be reloaded from ".$configs{'configFile'}."\n";
        setConfigsFromFile();
        if ( $configs{'configFile'} eq $runTimeConfigFile ) {
                $configs{'configFile'}=$runTimeConfigFile;
                warn "Config File locations has been changed back to: ".$configs{'configFile'} if ($configs{'verbose'}>2);
        }
}

sub printConfigurations {
        warn "Running printConfigurations\n" if ($configs{'verbose'}>1);
#Description: Prints to stdout the keys and values in %configs

        foreach ( keys %configs ) {
                print "Configuration: ".$_." has this value -> ".$configs{$_};
        }

}

sub runProgram {
        warn "Running runProgram\n" if ($configs{'verbose'}>1);
#Description: This could be a sub for running the real program or you might delete this and have a different call to 
#               some other sub.  This is more or less for testing this template.
# Assumptions: 
#               This sub is assumed to be running as a thread.
# Requires:  Some argument of any type to be passed to it
        my $someArgument = $_[0];
        my $i=0;

        $i=threads->tid();
        $thrCleared{$i}=0;

        $i=0;

#        while ( $i < 100 ) {
#                print $someArgument."\n";
#                sleep 3;
#        }
        
        my @startTimeArray = split(/-/, $configs{startTime});
        
        my $dt = DateTime->new(
            year    => $startTimeArray[0],
            month   => $startTimeArray[1],
            day     => $startTimeArray[2],
            hour    => $startTimeArray[3],
            minute  => $startTimeArray[4],
            second  => $startTimeArray[5],
            nanosecond => 0,
            time_zone => 'America/Chicago',
        );
        
        open FILE, $configs{accessLogFile} or die "$! file not able to be opened. Death! \n";        

        $i=threads->tid();
        $thrCleared{$i}=1;
}
