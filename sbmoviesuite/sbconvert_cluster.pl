#!/usr/bin/perl

use strict;
use Cwd;
use Getopt::Long;

# setup options;
# Ignore args with no options (eg, the list of files)
$Getopt::Long::passthrough = 1;  
# Be case sensitive
$Getopt::Long::ignorecase = 0;
my $options = { };
GetOptions($options, "-H", "-help", "--help", "-bp:s", "-cp:s", "-R", "-OR" );
my $USAGE = qq~
Usage:
        sbconvert_cluster.pl <Optional parameter files>
        
        You must first ssh into the server login2 to run this script.
        It will only work with the new cluster.

        Example: sbconvert_cluster.pl 

        Set parameter files (optional):
                -bp     specify a parameter file to calculate background
                -cp     specify a parameter file to do avi to sbfmf conversion
                -R      remove avi file
                -OR     for Fly Olympiad only, removes source tube.avi if seq.avi file exists
~;
if ( $options->{'H'} || $options->{'-help'} || $options->{'help'}) {
        print $USAGE;
        exit 0;
}

my $calcbg_param_file = "/groups/reiser/home/boxuser/lib/sbmoviesuite/sbparam-calcbg.txt";
$calcbg_param_file = $options->{'bp'} if ($options->{'bp'});

my $usebg_param_file = "/groups/reiser/home/boxuser/lib/sbmoviesuite/sbparam-usebg.txt";
$usebg_param_file = $options->{'cp'} if ($options->{'cp'});

my $current_dir = getcwd;
print "current_dir: $current_dir\n";

my $random = int(rand($$));
my $bg_run_id = "sbconvert_" . $random;


my $cmd = qq~/groups/reiser/home/boxuser/lib/sbmoviesuite/sbconvert.sh "$current_dir/" -p $calcbg_param_file~;

print "generating background: $cmd\n";

system($cmd);

unless (-e "all-bg.pickle") {
        print "Error: No background file generated.";
        exit(1);
}

opendir ( DIR, $current_dir ) || die "Error in opening dir $current_dir\n";
while( (my $filename = readdir(DIR))){
     if ($filename =~ /\.avi$/) {
        my $sgeid = "sbconvert_" . $filename . "_" . $$;
        my $shfilename = $sgeid . ".sh";
        write_qsub_sh($shfilename,$filename,$usebg_param_file);
        #my $sbconvert_cmd = qq~bsub -J $sgeid -oo ./$shfilename.stdouterr.txt -eo ./$shfilename.stdouterr.txt -n 2 ./$shfilename~;
        my $sbconvert_cmd = qq~bsub -J $sgeid -o /dev/null -e /dev/null -n 2 ./$shfilename~;
        print "submitting to cluster: $sbconvert_cmd\n";
        system($sbconvert_cmd);
     }
}
closedir(DIR);

print "It will take a few minutes for the sbfmf conversion to finish\n";

exit;

sub write_qsub_sh {
	my ($shfilename,$filename,$usebg_param_file) = @_;
	
	open(SHFILE,">$shfilename") || die 'Cannot write $shfilename';

	print SHFILE qq~#!/bin/csh -f
# sbconvert.py test script: calculate background on cluster; this
#   script will be qsub'd

# adapted from Mark Bolstad's "mtrax_batch"; removed the xvfb calls
#   since sbconvert doesn't require a screen

# set up the environment
source /misc/local/SCE/SCE/build/Modules-3.2.6/Modules/3.2.6/init/tcsh
module use /misc/local/SCE/SCE/build/COTS
module avail
module load cse-build
module load cse/ctrax/latest

# call the main script, passing in all command-line parameters
/misc/local/old_software/python-2.7.11/bin/python /groups/reiser/home/boxuser/lib/sbmoviesuite/sbconvert.py $filename -p $usebg_param_file

~;

	if ($options->{'R'}) {
print SHFILE qq~#delete avi file
rm -f $filename
~;	
}

	if ($options->{'OR'}) {
	    my $seqfile = $filename;
	    $seqfile =~ s/_tube\d+//;
	    if (-e "../$seqfile") {
print SHFILE qq~#delete olympiad source avi file
rm -f ../$filename
~;
	    }
	}
	
	print SHFILE qq~#delete itself
rm -f \$0
~;	
	
	close(SHFILE);
	
	chmod(0755, $shfilename);
}
