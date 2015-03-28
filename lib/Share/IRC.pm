package Share::IRC;

use AnyEvent;
use AnyEvent::IRC::Client;
use Data::Dump qw{pp};
use Share::Util;
use URI;
use Encode;

sub new {
  my ($class, %options) = @_;
  my $self = bless {
    seen => {},
    queue  => [],
    timer => undef,
    nick => ($options{nick} || "sharebot2000"),
  }, $class;

  $self->{timer} = AE::timer 0, 2, sub { $self->check_queue };
  return $self;
}

sub check_queue {
  my $self = shift;
  if (my $item = shift @{$self->{queue}}) {
    $self->share($item);
  }
}

sub enqueue {
  my $self = shift;
  my $cv = pop;
  my %options = @_;

  for (qw{host chan url}) {
    if (!defined($options{$_})) {
      $cv->croak("$_ is required");
      return;
    }
  }

  $options{url} = URI->new($options{url})->canonical;
  my $key = join "-", map {lc $_} qw{host chan url};

  if ($self->{seen}{$key}) {
    $cv->croak("already shared");
  }

  $self->{seen}{$key}++;

  Share::Util::resolve_title $options{url}, sub {
    $options{title} = shift;
    $options{cv} = $cv;
    push @{$self->{queue}}, \%options;
  };
}

sub share {
  my ($self, $options) = @_;
  my $irc = AnyEvent::IRC::Client->new;

  my $timer; $timer = AE::timer 3, 0, sub {
    undef $timer;
    $options->{cv}->croak("timeout");
    $irc->disconnect
  };

  $irc->enable_ssl if $options->{ssl};
  $irc->connect($options->{host}, ($options->{port} || 6667), {
      nick => $self->{nick},
      $options->{ircuser} ? (user => $options->{ircuser}) : (),
      $options->{ircpass} ? (password => $options->{ircpass}) : (),
  });

  $irc->reg_cb(
    registered => sub {
      my ($irc) = @_;
      $irc->send_msg(JOIN => $options->{chan}, $options->{pass} || ());
    },
    join => sub {
      my ($irc, $nick, $channel, $is_myself) = @_;
      if ($is_myself) {
        my $msg = encode utf8 => "$options->{title} - $options->{url}";
        $irc->send_msg(PRIVMSG => $options->{chan}, $msg);
        $irc->disconnect;
        $options->{cv}->send;
      }
    },
    disconnect => sub {
      undef $timer;
      undef $irc;
    }
  );
}

1;
