#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

# Install Mojolicious and DateTime from CPAN to fix dependencies

use ojo;
use DateTime;

my @catalog_ids = (
    '1de9c319-010c-4585-8617-210873935dfa',
    '90b5b79a-ceb6-4084-8cca-8977ff1aa729',
    '1c56eaf7-1178-4cb9-bf47-53e717ea74c2',
    '5b80d7ae-5fc7-46c4-98ba-5f770a8be940',
);

my @streams;
foreach my $catalog_id ( @catalog_ids ) {
    my $catalog_url = 'http://ics.webcast.uwex.edu/mediasite/Catalog/pages/catalog.aspx?catalogId=' . $catalog_id;
    g($catalog_url)
        ->dom("table.PresentationTableView tr.PresentationTableView_GridItem,table.PresentationTableView tr.PresentationTableView_GridAltItem")
        ->each(sub {
            # Parse table rows
            my ($dom, $index) = @_;
            my $stream = {};
            $dom->find("a.cardLink")
                ->each(sub {
                    # Parse stream links
                    my ($dom, $index) = @_;
                    $stream->{title}   = $dom->all_text;
                    $stream->{url}     = $dom->{href};
                });
            $dom->find("td")
                ->each(sub {
                    # Parse other stream info
                    my ($dom, $index) = @_;
                    $stream->{status}   = $dom->all_text || "" if $index == 3;
                    $stream->{date}     = $dom->all_text || "" if $index == 4;
                    $stream->{time}     = $dom->all_text || "" if $index == 5;
                    $stream->{duration} = $dom->all_text || "" if $index == 6;
                });
            # Create a DateTime object and convert to local timezone
            if ( $stream->{date} and $stream->{time} ) {
                my ($month, $day, $year) = split("/", $stream->{date});
                my ($hour, $minute, $part_of_day, $tz) = $stream->{time} =~ m/(\d+) : (\d+) \s+ (AM|PM) \s+ CDT/x;
                $hour = ( ( ( $part_of_day eq 'PM' and $hour < 12 ) ? $hour + 12 : $hour ) || 0 );
                $stream->{dt} = DateTime->new(
                    day   => $day,
                    month => $month,
                    year  => $year,
                    hour  => $hour,
                    minute => ( $minute || 0 ),
                    time_zone => 'America/Chicago',
                );
                $stream->{dt}->set_time_zone('local');
            }
            push @streams, $stream;
          });
}

# Output stream information sorted by timestamp
foreach my $stream ( sort { $a->{dt} cmp $b->{dt} } @streams ) {
    my $url = convert_stream_url( $stream ) || $stream->{url};
    say $stream->{dt} . " "
      . pad($stream->{status}, 9) . " "
      . pad(convert_title($stream->{title}), 26) . " "
      . pad($url, 85) . " "
      . ( $stream->{duration} ? "(" . $stream->{duration} . ")" : "" )
        if $url;
}

# Convert web page stream URL to ASF URL usable by VLC or other video player
sub convert_stream_url {
    my ($stream) = @_;
    my $url = $stream->{url};
    my @parts = ( $url =~ /peid=(\w{8})(\w{4})(\w{4})(\w{4})(\w+)\w\w\z/ );
    return unless @parts;
    if ( $stream->{status} eq 'On Air' ) {
        return "http://video.ics.uwex.edu/" . join('-', @parts);
    }
    if ( $stream->{status} eq 'On Demand' ) {
        return "http://video.ics.uwex.edu/Video/ICS/" . join('-', @parts) . ".wmv";
    }
    return;
}

sub pad {
    my ($str, $len) = @_;
    return $str unless $len;
    my $pad_length = $len - length $str;
    return $str if $pad_length < 1;
    return $str . ( " " x $pad_length);
}

sub convert_title {
    my ($title) = @_;
    return "" unless defined $title;
    return "Pyle Vandenburg Auditorium" if $title =~ /aud/i;
    return "Pyle 313"                   if $title =~ /313/;
    return "Pyle 325"                   if $title =~ /325/;
    return "Lowell Dining Room"         if $title =~ /lowell/i;
    return $title;
}
