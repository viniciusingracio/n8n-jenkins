#!/usr/bin/perl 

#global variables
$FSuser="freeswitch";
$fdir="/var/freeswitch/meetings";
@errors="";

#get freeswitch user properties
($fuser,$passwd, $uid, $gid, $quota, $comment, $gcos, $dir, $shell) = getpwnam("$FSuser");

        #check if user exists based on its var
        if (defined $fuser) {

                #check if freeswitch dir exists
                if (-d $fdir) {

                        #get uid/gid directory owner
                        my $udir = (stat($fdir))[4];
                        my $gdir = (stat($fdir))[5];

                                #check if dir ownership matches freeswitch user
                                if (($uid == $udir) && ($gid == $gdir)) {

                                        #So its OK, lets try to write a file into freeswitch dir
                                        `su - freeswitch -c 'touch $fdir/test.txt' -s /bin/bash`;

                                                #everything is OK, just remove the test file
                                                if ($? == 0) {
                                                        `su - freeswitch -c "rm $fdir/test.txt" -s /bin/bash`;
                                                }#end if

                                                #oopss, something is wrong, could write a file into freeswitch dir
                                                else {
                                                        push @errors,"Could not write to freeswitch directory($fdir)\n";
                                                }

                                }#end if

                                #oopss, something is wrong, dir ownership does not matches freeswitch user
                                else {
                                        push @errors,"ownership(uid/gid) mismatch on $fdir, it should belongs to $FSuser user/group\n";
                                }#end else
                }#end if

                else {
                        push @errors,"Could not found freeswitch directory($fdir)\n";
                }#end else

        }#end if

        else {
                push @errors,"could not found freeswitch user($FSuser)\n";
        }#end else

if ($#errors > 0) {
        printf "CRITICAL - @errors\n";
        exit 2
}#end if        

else {
        printf "OK - No freeswitch errors found\n";
        exit 0;
}#end else
