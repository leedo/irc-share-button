package Share::IRC;

use AnyEvent;
use AnyEvent::IRC::Connection;
use Data::Dump qw{pp};
use Share::Util;

sub new {
  my ($class, %options) = @_;
  my $self = bless {
    recent => [],
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

  Share::Util::resolve_title $options{url}, sub {
    $options{title} = shift;
    $options{cv} = $cv;
    push @{$self->{queue}}, \%options;
  };
}

sub share {
  my ($self, $options) = @_;
  my $irc = AnyEvent::IRC::Connection->new;
  $irc->connect($options->{host}, $options->{port} || 6667); 
  $irc->reg_cb(
    connect => sub {
      my ($irc) = @_;
      $irc->send_msg(NICK => $self->{nick});
      $irc->send_msg(USER => $self->{nick}, '*', '0', $self->{nick});
    },
    irc_001 => sub {
      my ($irc) = @_;
      $irc->send_msg(JOIN => $options->{chan}, $options->{pass} || ());
    },
    irc_join => sub {
      my ($irc) = @_;
      my $msg = encode utf8 => "$options->{title} - $options->{url}";
      $irc->send_msg(PRIVMSG => $options->{chan}, $msg);
      $irc->disconnect("beep boop");
    },
    disconnect => sub {
      $options->{cv}->send;
    }
  );
}

1;
