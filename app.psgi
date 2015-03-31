use Share::IRC;
use Text::Xslate;
use Plack::Request;
use Share::Util;
use Encode;

my $irc = Share::IRC->new;
my $template = Text::Xslate->new(path => "share/templates");
my %ips = {};

sub {
  my $env = shift;
  my $req = Plack::Request->new($env);

  my $ip = $req->address;
  my $time = time;
  my $limit = $ips{$ip} && $time - $ips{$ip} < 60;

  if ($req->method eq "GET") {
    if ($req->path eq "/demo") {
      my $html = $template->render("demo.html");
      return [200, ["Content-Type", "text/html; charset=utf-8"], [encode utf8 => $html]];
    }
    if (!defined($req->parameters->{url})) {
      return [400, [qw{Content-Type text/plain}], ["invalid url"]];
    }

    return sub {
      my $cb = shift;
      Share::Util::resolve_title $req->parameters->{url}, sub {
        my $title = shift;
        my $diff = $limit && 60 - ($time - $ips{$ip});
        my $html = $template->render("index.html", {
            url => $req->parameters->{url},
            title => $title,
            limit => $limit,
            diff  => $diff,
          });
        $cb->([200, ["Content-Type", "text/html; charset=utf-8"], [encode utf8 => $html]]);
      };
    };
  }

  if ($req->method ne "POST") {
    return [404, [qw{Content-Type text/plain}], ["not found"]];
  }

  if ($limit) {
    my $diff = 60 - ($time - $ips{$ip});
    return [420, [qw{Content-Type text/plain}], ["Too soon to share another URL (wait $diff seconds)"]];
  }

  $ips{$ip} = time;

  for (qw{host chan url}) {
    if (!defined($req->parameters->{$_})) {
      return [400, [qw{Content-Type text/plain}], ["invalid $_"]];
    }
  }

  return sub {
    my $cb = shift;
    my $cv = AE::cv;

    $cv->cb(sub {
      my $log = eval { shift->recv };
      if ($@) {
        $cb->([500, [qw{Content-Type text/plain}], ["error: $@"]]);
        delete $ips{$ip};
        return;
      }
      $cb->([200, [qw{Content-Type text/plain}], [join "\n", @$log]]);
    });

    my %options = map {$_ => $req->parameters->{$_}}
      qw{host port chan pass url ircuser ircpass};

    $options{ssl} = defined($req->parameters->{ssl})
      && $req->parameters->{ssl} eq "on";

    $irc->enqueue(%options, $cv);
  }
};
