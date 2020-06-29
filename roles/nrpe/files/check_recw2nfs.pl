#!/usr/bin/perl 

#needs to install liblist-moreutils-perl libexperimental-perl
#apt-get install liblist-moreutils-perl libexperimental-perl

use experimental 'smartmatch';
use List::MoreUtils qw(any all none);
#fstab path file
$fstab="/etc/fstab";

#error variable
our @errors="";

#mount path
$mount='/bin/mount';

our $line;
our $file;

#try to open fstab file
open($file, '<', $fstab) or die "CRITICAL - Could not open '$fstab': $!\n";

#run it
while ($line = <$file>) {

	chomp $line;
	is_nfs($line);
}

#check if file has no fstab lines, out of the loop to print just once
if (! @count) {
	push @errors, "No NFS lines found in $fstab\n";
}

#print if errors were found
if ($#errors > 0) {
	printf "CRITICAL - @errors\n";
        exit 2
}#end if

else {
	printf "OK - Successfully connected to NFS server(s)\n";
	exit 0;
}#end else

sub is_nfs {

#local variables
my @fieldsa;
my @fieldsb;
my $nfs_field;
my $line_starts;
my $line_nfs;
our @count;

	#check if fstab is not blank or has any problem
	if (defined $line) {
		
		#split based on "blank sapace" to get nfs fields
		my @fieldsa = split " " , $line;
		
		#split based on ":" to discard commented(#) lines
		my @fieldsb = split ":", $line;

		$nfs_field = $fieldsa[2];
		$nfs_line = $fieldsa[1];
		$line_starts = $fieldsb[0];
		$nfs_server = $fieldsb[0];
		chomp($nfs_field,$nfs_line,$line_starts);

			#If the line has "nfs" and does not start with #, so its a valid line for NFS
			if ( ($nfs_field =~ /nfs/i) && ($line_starts !~ /^#/) ) {

				#count to check if we have at least 1 fstab line, if not...alarm
				push @count, "$nfs_field";

				#check if we can access mounted point
				is_nfs_ok($nfs_line);
			}#end if

	}#end if

	else {
		push @errors,"Something is wrong in $fstab file\n";
	}#end else

}#end sub

sub is_nfs_ok {
my @mount;

#list all mounted points
@mount =  `$mount`;
chomp @mount;
	#check if the NFS point is mounted
	if ( any { /$nfs_line/i } @mount ) {

		#Check for raw dir, RO check 
		if ($nfs_line =~ /raw/i) {
			#check within 10 seconds of timeout
			`su - bigbluebutton -c 'timeout -s KILL 10 ls $nfs_line' -s /bin/bash`;
				unless ($? == 0) {
					push @errors, "Could NOT READ(ro) $nfs_line mounted point on NFS-SERVER: $nfs_server\n";
				}#end unless
		} #end if

		#other dirs (except raw), RW check
		else {
			#check within 10 seconds of timeout
			`su - bigbluebutton -c 'timeout -s KILL 10 touch $nfs_line/test.txt' -s /bin/bash`;
				unless ($? == 0) {
					push @errors, "Could NOT WRITE(rw) to $nfs_line mounted point on NFS-SERVER: $nfs_server\n";
				}#end unless
				else {
					#remove the test file
					`su - bigbluebutton -c 'timeout -s KILL 10 rm $nfs_line/test.txt' -s /bin/bash`;
				}#end else
		}#end else

	}#end if

	else {
		push @errors, "NFS point $nfs_line is NOT mounted on recw\n";
	}
}#end sub
