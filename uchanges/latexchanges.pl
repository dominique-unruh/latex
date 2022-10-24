### Copyright Dominique Unruh

#!/usr/bin/perl

#BEGIN {
#    $SIG{__DIE__} = sub {
#	warn $_[0];
#	print STDERR "\nPress enter\n";
#	<STDIN>;
#	exit 1;
#    }
#}

use strict;

use Getopt::Long;
use Data::Dumper;
#use Regexp::Common;
#use File::Slurp;
use IO::File;
use MIME::Base64;

our $currenttime = time();

#our $balanced0 = $RE{balanced}{-parens=>'{}'};
our $balanced0;
$balanced0 = qr/(?-xism:(?:\{(?:(?>[^\{\}]+)|(??{$balanced0}))*\}))/;

our $balanced = "[^\{\}]*(?:${balanced0}[^\{\}]*)*";

#our $balancedkeep = "$RE{balanced}{-parens=>'{}'}{-keep=>1}";
our $balancedkeep; 
$balancedkeep = qr/((?-xism:(?-xism:(?:\{(?:(?>[^\{\}]+)|(??{$balancedkeep}))*\}))))/;


sub removefirstlast($) {
    my ($str) = @_;
    die "To short a string" unless length $str >= 2;
    $$str =~ s/^.//;
    $$str =~ s/.$//;
}

sub replacemacro($$$$) {
    use re 'eval';
    my ($options,$macro,$spec,$string) = @_;
    my $regexp = "\Q$macro\E";
    my $t = $spec;
    $t =~ s{.}{
	if ($& eq '+' || $& eq '-') {
	    $regexp .= $balancedkeep;
	} elsif ($& eq '[') { # Only for very simple content (no nesting of {}), simply dropped
	    $regexp .= "(\\[[^\\]]*\\])";
	} else {
	    die "Invalid macro spec '$&'";
	}
    }eg;
    my $count = 0;
    $$string =~ s{$regexp((?:\s*\n)?)}{
	$count++;
	#print "Match: $&\n";
	my $result = '';
	for my $i (1..($#- - 1)) {
	    my $match = substr $$string, $-[$i], $+[$i]-$-[$i];
	    my $s = substr $spec,$i-1,1;
	    #print "$#-, i=$i, match=$match, s=$s\n";
	    #print "$regexp\n";
	    #print Dumper \@-, \@+;
	    if ($s eq '-') {
	    } elsif ($s eq '+') {
		removefirstlast(\$match);
		$result .= $match;
	    } elsif ($s eq '[') {
	    } else {
		die "Invalid macro spec '$s'";
	    }
	}
	my $trailing = substr $$string, $-[$#-], $+[$#-]-$-[$#-];
	if ($result =~ m{^\s*$}) {
	  # Replacing by empty string => remove following newline if immediately followed by one
	  $result;
	} else {
	  # Keep trailing newline
	  $result.$trailing;
	}
    }eg;
    $options->{stats}->{replace}->{$macro} = $count;
}

sub replacemacros($$) {
    my ($options,$string) = @_;
    while (my ($macro,$spec) = each %{$options->{replace}}) {
	replacemacro($options,$macro,$spec,$string);
    }
}

sub fillinusers($$$) {
    my ($options,$string,$macro) = @_;
    die "need --users" if $options->{users} eq '';
    my $count = 0;
    my $users = $options->{users};
    my $user = substr $macro, length($macro)-1;
    if (!$options->{keepself}) {
      $users =~ s/\Q$user\E//g; # Don't show a users changes to himself
    }
    my $time = encodetime($currenttime);
    $$string =~ s{\\\Q$macro\E\s*(?=\{)}{
	$count++;
	"\\${macro}for\{$users\}\{$time\}"
	}ges;
    $options->{stats}->{fillin}->{$macro} = $count;
}

sub encodetime($) {
    my $t = shift;
#    my $e = MIME::Base64::encode_base64(pack("I", $t),'');
#    $e =~ s/=+$//;
#    return $e;
    my @t = localtime($t);
    return sprintf("%02d%02d%02d",$t[5]%100,$t[4]+1,$t[3]); # YYMMDD
}

sub changemacrostats($$$) {
  use re 'eval';
    my ($options,$mac,$string) = @_;
    my $t = $$string;
    $t =~ s{\\\Q${mac}\Efor\s*\{($balanced)\}}{
	for my $c (split '', $1) {
	    $options->{stats}->{users}->{$c}->{$mac} ++;
	}
    }ge;
}

sub removeuser($$$) {
  use re 'eval';
  my ($options,$string,$mac) = @_;
  if ($$string =~ m{(\\\Q${mac}for\E\s*\[)}s) {
    # sed -e 's/\(\\\\[A-Z]\+for\)\[\([A-Z]*\)\]\[\([a-zA-Z\/0-9]*\)\]/\1{\2}{\3}/g' -i filename
    die "Found old syntax \"$1...\" in file $$options{currentfile}. Please replace [] by {}.";
  }
  my $user = $options->{removeuser};
  return unless defined $user;
  my $f = sub {
    my $user = $_[0];
    $$string =~ s{
		   (\\\Q${mac}\Efor\s*\{$balanced)
		   \Q$user\E
		   ($balanced\}\s*)\{([0-9]+)\}}{
		     if (defined $$options{before} && $$options{before} lt $3) {
		       "$&";
		     } else {
		       $options->{stats}->{removeduser}->{$user}->{$mac} ++;
		       "$1${2}{$3}";
		     }
		   }gex;
  };
  if ($user eq '*') {
    for my $u (split //, $options->{users}) {
      &$f($u); }
  } else {
    &$f($user);
  }
}

sub dochangemacros($$) {
    my ($options,$string) = @_;
    while (my ($mac,$spec) = each %{$options->{changemacro}}) {
	fillinusers($options,$string,$mac);
	removeuser($options,$string,$mac);
	replacemacro($options,"\\${mac}for{}","-".$spec,$string)
	  unless $options->{noremove};
	changemacrostats($options,$mac,$string);
    }
}

sub parseoptions() {
    my %options = (
		   replace => {},
		   files => [],
		   changemacro => {},
		   );
    GetOptions('replace=s' => $options{replace},
	       'users=s' => \$options{users},
	       'changemacro=s' => $options{changemacro},
	       'removeuser=s' => \$options{removeuser},
	       'removeme' => \$options{removeme},
	       'removeall' => \$options{removeall},
	       'keepself' => \$options{keepself},
	       'noremove' => \$options{noremove},
	       'before=s' => \$options{before}, # Actually: before and including
	       )
	or die "Invalid options";
    push @{$options{files}}, @ARGV;
    return \%options;
}

sub printstatistics($) {
    my ($options) = @_;
    while (my ($mac,$count) = each %{$options->{stats}->{fillin}}) {
	print "Added $count \\${mac}for\n" if $count>0;
    }
    while (my ($mac,$count) = each %{$options->{stats}->{replace}}) {
	print "Removed $count $mac\n" if $count>0;
    }
    while (my ($u,$stat) = each %{$options->{stats}->{removeduser}}) {
	print "Removed user $u from: ";
	my $first = 1;
	while (my ($mac,$count) = each %$stat) {
	    print ", " unless $first;
	    print "$count \\${mac}for";
	    $first = 0;
	}
	print "\n";
    }
    while (my ($u,$stat) = each %{$options->{stats}->{users}}) {
	print "User $u: ";
	my $first = 1;
	while (my ($mac,$count) = each %$stat) {
	    print ", " unless $first;
	    print "$count \\${mac}for";
	    $first = 0;
	}
	print "\n";
    }
}


sub read_file($) {
  my ($file) = @_;
  my $f = new IO::File($file,"<") or die "Could not open $file for reading: $!";
  $f->binmode() or die;
  my @content = (<$f>);
  close $f or die "Could not close $file: $!";
  return join '',@content;
}

sub write_file($$) {
  my ($file,$string) = @_;
  my $f = new IO::File($file,">") or die "Could not open $file for writing: $!";
  $f->binmode() or die;
  print $f $string or die "Could not write to $file: $!";
  close $f or die "Could not close $file: $!";
}



sub defaultactions($) {
    my ($options) = @_;
    return if $options->{noauto};
    unless (@{$options->{files}}) {
	@{$options->{files}} = grep {
	  $_ ne '_region_.tex'
	} <*.tex *.bib>;
    }
    my $found = 0;
    my $whoami = read_file("whoami.txt");
    $whoami =~ s/\r//g;
    if ($whoami =~ /^\\iam (.)$/m) {
	$options->{myself} = $1;
    } else {
	die "Please create whoami.txt";
    }
    if ($options->{removeme}) { $options->{removeuser} =
				    $options->{myself}; };
    if ($options->{removeall}) { $options->{removeuser} = '*'; };

    if (!defined $options->{users}) {
    my $packageoptions;

    # Scanning for \usepackage[...]{uchanges}
    for my $f (@{$options->{files}}) {
      #print "Scanning for parameters: $f\n";
	my $fh = new IO::File($f,"r");
	while (defined (my $line = <$fh>)) {
#	    if ($line =~ m/^\\def\\ch\@users{(.*)}/) {
#		$options->{users} = $1 
#		    unless defined $options->{users};
#		$foundhere = 1;
#	    }
	    if ($line =~ m/^\s*\\usepackage(?:\[([^\]]*)\])?\{uchanges\}/) {
		if ($found && $packageoptions ne $1) {
		    die "Found \\usepackage{uchanges} twice with different options ($packageoptions vs $1)"; }
		$packageoptions = $1;
		$found = 1;
	    }
	}
    }
    if ($found == 0) {
	warn "Could not find \\usepackage{uchanges} call. No automatic action";
	return;
    }

    print "Package options: $packageoptions\n";
    my %packageoptions = 
	map { my ($k,$v) = (/^(.*?)(?:=(.*))?$/); $k=>$v; }
    split /\s*,\s*/, $packageoptions;
    unless ($packageoptions{users}) {
	warn "No users given to \\usepackage{uchanges}. No automatic action";
	return;
    }
    $options->{users} = $packageoptions{users};
  }


    my %templates = (
		     'NEW' => '+',
		     'REPLACE' => '-+',
		     'REMOVE' => '-',
		     'MESSAGE' => '-',
		     );
    for my $u (split //, $options->{users}) {
	while (my ($k,$v) = each %templates) {
	    $options->{changemacro}->{$k.$u} = $v;
	}
    }
}

sub write_if_changed($$) {
    my ($file,$string) = @_;
    my $curr = read_file($file);
    return if $curr eq $string;
    print "Writing file $file\n";
    write_file($file,$string);
}

my $options = parseoptions();
defaultactions($options);
for my $file (@{$options->{files}}) {
  #print "File: $file\n";
  $$options{currentfile} = $file;
  my $string = read_file($file);
  replacemacros($options,\$string);
  dochangemacros($options,\$string);
  #print $string;
  write_if_changed($file,$string);
  delete $$options{currentfile};
}
printstatistics($options);

