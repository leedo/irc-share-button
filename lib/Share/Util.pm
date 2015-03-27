package Share::Util;

use AnyEvent::HTTP ();
use URI::Escape;
use HTML::Parser;
use HTML::Entities;
use Encode;

my %defaults = (
  headers => {
    "Referer"   => "http://www.google.com/",
    "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/28.0.1500.71 Safari/537.36",
  }
);

sub resolve_title {
  my ($url, $cb) = @_;

  Share::Util::http_get($url, sub {
    my ($body, $headers) = @_;
    my ($in_title, $title);
    if ($headers->{Status} == 200) {
      my $p = HTML::Parser->new(
        api_version => 3,
        start_h => [
          sub {
            $in_title = 1 if $_[1] eq "title";
            if ($_[1] eq "meta" and $_[2]->{property} eq "og:title") {
              $title = decode_entities $_[2]->{content};
              $_[0]->eof;
            }
          },
          "self,tag,attr",
        ],
        text_h  => [
          sub {
            if ($in_title) {
              $title = decode_entities $_[1];
            }
          },
          "self,dtext",
        ],
        end_h => [
          sub {
            $_[0]->eof if $_[1] eq "/head";
            $in_title = 0 if $_[1] eq "/title";
          },
          "self,tag",
        ],
      );
      $p->parse(decode "utf8", $body);
      $p->eof;
    }
    # cleanup
    if ($title) {
      $title =~ s/[\n\t]//g;
      $title =~ s/^\s+//g;
      $title =~ s/\s+$//g;
    }
    $cb->($title);
  });
}

sub http_get {
  my $cb = pop;
  my ($url, %opts) = @_;

  for (keys %defaults) {
    $opts{$_} = $defaults{$_} unless defined $opts{$_};
  }

  $opts{cookie_jar} = {} unless defined $opts{cookie_jar};

  AnyEvent::HTTP::http_get $url, %opts, sub {
    my ($body, $headers) = @_;
    my $enc = $headers->{"content-encoding"};
    if (defined $enc and $enc eq "gzip") {
      eval { "use IO::Uncompress::Gunzip qw{gunzip};" };
      die "missing IO::Uncompress::Gunzip" if $@;
      my $unzipped;
      IO::Uncompress::Gunzip::gunzip(\$body, \$unzipped);
      $body = $unzipped;
    }

    $cb->($body, $headers);
  };
}

1;
