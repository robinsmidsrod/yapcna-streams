#!/usr/bin/env plackup

use strict;
use warnings;
use feature 'say';

# Install Mojolicious, DateTime and Web::Machine from CPAN to fix dependencies

use Web::Machine;

package YAPCNA::Streams::Resource;
use parent 'Web::Machine::Resource';
use JSON ();

sub content_types_provided {[
    { 'text/html'        => 'to_html' },
    { 'application/json' => 'to_json' },
    { 'text/plain'       => 'to_text' },
]}

sub to_text {
    # Output stream information sorted by timestamp
    my $output = "";
    foreach my $stream ( sort { $a->{dt} cmp $b->{dt} } YAPCNA::Streams::get_streams() ) {
        my $url = YAPCNA::Streams::convert_stream_url( $stream )
               || $stream->{url};
        next unless $url;
        $output .= $stream->{dt} . " "
                .  YAPCNA::Streams::pad($stream->{status}, 9) . " "
                .  YAPCNA::Streams::pad(YAPCNA::Streams::convert_title($stream->{title}), 26) . " "
                .  YAPCNA::Streams::pad($url, 85) . " "
                .  YAPCNA::Streams::convert_duration($stream->{duration})
                .  "\n";
    }
    return $output;
}

sub to_html {
    # Output stream information sorted by timestamp
    my $output = "<style>td { border: solid 1px grey;</style><table><tbody>";
    foreach my $stream ( sort { $a->{dt} cmp $b->{dt} } YAPCNA::Streams::get_streams() ) {
        my $url = YAPCNA::Streams::convert_stream_url( $stream )
               || $stream->{url};
        $output .= qq!<tr><td>! . $stream->{dt} . qq!</td>!
                .  qq!<td>! . $stream->{status} . qq!</td>!
                .  qq!<td>! . YAPCNA::Streams::convert_title($stream->{title}) . qq!</td>!
                .  qq!<td><a href="! . $url . qq!" target="_blank">Video URL</a></td>!
                .  qq!<td><a href="! . $stream->{url} . qq!" target="_blank">Viewer URL</a></td>!
                .  qq!<td>! . YAPCNA::Streams::convert_duration($stream->{duration}) . qq!</td></tr>!
                   if $url;
    }
    return $output . qq!</tbody></table>!;
}

sub to_json {
    # Output stream information sorted by timestamp
    my @output;
    foreach my $stream ( sort { $a->{dt} cmp $b->{dt} } YAPCNA::Streams::get_streams() ) {
        next unless $stream->{url};
        my $url = YAPCNA::Streams::convert_stream_url( $stream );
        push @output, {
            timestamp => "" . $stream->{dt},
            status    => $stream->{status},
            title     => YAPCNA::Streams::convert_title($stream->{title}),
            url       => $stream->{url},
            video_url => $url,
            duration  => YAPCNA::Streams::convert_duration($stream->{duration}),
        }
    }
    return JSON->new->utf8->pretty->encode(\@output);
}

package YAPCNA::Streams;
use ojo;
use DateTime;

sub get_streams {

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

    return @streams;
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
    return $str . ( " " x $pad_length );
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

sub convert_duration {
    my ($duration) = @_;
    return "" unless $duration;
    $duration =~ s/ \s* hours? \s* /h/ix;
    $duration =~ s/ \s* minutes? \s* /m/ix;
    $duration =~ s/ \s* seconds? \s* /s/ix;
    return "($duration)";
}

package main;

Web::Machine->new(
    resource => 'YAPCNA::Streams::Resource'
)->to_app;
