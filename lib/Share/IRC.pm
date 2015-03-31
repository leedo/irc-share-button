package Share::IRC;

use AnyEvent;
use AnyEvent::IRC::Client;
use Data::Dump qw{pp};
use Share::Util;
use AnyEvent::IRC::Util;
use URI;
use Encode;

our @EXEMPT = (
  ["irc.arstechnica.com", "#sharehole"]
);

sub new {
  my ($class, %options) = @_;
  my $self = bless {
    seen => {},
    log  => {},
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
  my $key = join "-", map {lc $options{$_}} qw{host chan url};

  if ($self->{seen}{$key}) {
    my $skip = 0;

    for my $e (@EXEMPT) {
      if ($options{host} eq $e->[0] && $options{chan} eq $e->[1]) {
        $skip = 1;
        last;
      }
    }

    if (!$skip) {
      $cv->croak("already shared\n");
      return;
    }
  }

  Share::Util::resolve_title $options{url}, sub {
    my $title = shift;
    $title =~ s/[\r\n]//g;
    $title = substr($title, 0, 255);
    $options{title} = $title;
    $options{cv} = $cv;
    $options{key} = $key;
    push @{$self->{queue}}, \%options;
  };
}

sub share {
  my ($self, $options) = @_;
  my $irc = AnyEvent::IRC::Client->new;

  my $log = ["-> connecting to $options->{host}"];
  $self->{seen}{$options->{key}}++;

  my $timer; $timer = AE::timer 2, 0, sub {
    undef $timer;
    push @$log, "-> connection timed out";
    $options->{cv}->croak(join "\n", @$log);
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
        $irc->send_msg(PART => $options->{chan});
        $irc->disconnect;
        push @$log, "-> disconnecting from $options->{host}";
        $options->{cv}->send(join "\n", @$log);;
      }
    },
    send => sub {
      my @params = @{$_[1]};
      push @$log, join " ", "->", @params[1 .. $#params];
    },
    read => sub {
      my ($command, $params) = @{$_[1]}{qw{command params}};
      push @$log, join " ", "<-", $command, @$params;
    },
    disconnect => sub {
      undef $timer;
      undef $irc;
    }
  );
}

1;
