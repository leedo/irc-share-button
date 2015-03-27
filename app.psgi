use Share::IRC;
use Plack::Request;

my $irc = Share::IRC->new;

sub {
  my $env = shift;
  my $req = Plack::Request->new($env);

  if ($req->method ne "POST") {
    return [404, [qw{Content-Type text/plain}], ["not found"]];
  }

  for (qw{host chan url}) {
    if (!defined($req->parameters->{$_})) {
      return [400, [qw{Content-Type text/plain}], ["invalid $_"]];
    }
  }

  return sub {
    my $cb = shift;
    my $cv = AE::cv;

    $cv->cb(sub {
      eval { shift->recv };
      if ($@) {
        $cb->([500, [qw{Content-Type text/plain}], ["error: $@"]]);
        return;
      }
      $cb->([200, [qw{Content-Type text/plain}], ["success"]]);
    });

    my %options = map {$_ => $req->parameters->{$_}} qw{host port ssl chan pass url};
    $irc->enqueue(%options, $cv);
  }
};
