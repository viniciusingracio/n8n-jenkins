#!/usr/bin/perl -w

for (my $num = 1; $num <= 3; $num += 1) {
our $countqueue = qx(/usr/local/rbenv/shims/passenger-status -v | grep "Requests in queue" | cut -d " " -f 6);
push @queue, "$countqueue";
chomp @queue;
sleep(5);
}
if ($countqueue >= 50) {
	printf ("CRITICAL - passenger queue is greater than 50 | passenger_last=$queue[2] passenger_queue1=$queue[1] passenger_queue2=$queue[0]\n");
	exit 2;
}
else
{
	printf "OK - passenger queue is less than 50  | passenger_last=$queue[2] passenger_queue1=$queue[1] passenger_queue2=$queue[0]\n";
}
