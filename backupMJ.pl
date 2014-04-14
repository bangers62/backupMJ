#!/usr/bin/perl -w
use strict;
use warnings;
use 5.10.16;

use File::Copy          qw( cp );
use File::Compare;
use File::Path          qw( make_path );
use Cwd;
use Getopt::Long;
use Sys::Hostname;



my ( $source, $target, %skip );
my $host = hostname();

if ( $host eq 'roe' ) {
  $source = '/mnt/monkjack';
  $target = '/mnt/usb';
}
elsif ($host eq 'elk' or $host eq 'elk.local' ) {
  $source = '/Volumes/Public';
  $target = '/Volumes/backup/data';
}
else {
  die "No config for host $host\n";
}

my $path   = '';

my $all   = 0 ; 
my $fast  = 0;

GetOptions(
  'all!'  => \$all,
  'fast!' => \$fast,
  to      => \$target,
);

if ( !$all ) {
  my $cwd = getcwd();
  if ( $cwd =~ /^($source)\/?(.*)/ ) {
    $path = $2;
  }
  else {
    die "not ready for that yet";
  }
  
}


my $start  = time();
my %report = ( bu => {}, cu => {} ); 
my %file   = ( bu => [], cu => [] );

say "Backing up from $source to $target";

walkTree( from    => $source,
          to      => $target,
          path    => $path,
          skip    => \%skip,
          fast    => $fast,
          report  => $report{bu},
          files   => $file{bu},
          );


cleanTree(backup    => $target,
          original  => $source,
          path      => $path,
          report    => $report{cu},
          files     => $file{cu},
          );




say "Durration: " . getSecondsAsTime( time() - $start);
for my $section ( sort keys %report ) {
  for my $key ( sort(keys %{$report{$section}}) ) {
    say sprintf "%-20s %6d", $key, $report{$section}{$key};
  }
  say "Files: " if scalar  @{$file{$section}};
  for my $file ( @{$file{$section}} ) {
    say " $file";
  }
  say "";
  say '-'x50;
}

#-----------------------------------------------------------------------------------------
sub walkTree {
  my ( %dir ) = @_;
  
  $dir{report}{"Directories scanned"}++;
  
  if ( $dir{path} ) {
    $dir{from}  .= "/$dir{path}";
    $dir{to}    .= "/$dir{path}";
  }  
  
  my @files = getDir($dir{from});
  say "Walking $dir{from}: ".scalar(@files);

  for my $file (  sort @files ) {
    my $fullname = $dir{from} . "/" . $file;
    if ( $file eq '.' or $file eq '..' ) {
      #say "Skipping: $fullname";
      next;
    }
    elsif ( -f $fullname ) { 
      backup( %dir, source => $fullname, to => $dir{to}, file => $file, );
    }
    elsif ( -d $fullname ) {    
      walkTree( %dir, path => $file,  );
    } 
    else {
       say "WTF is $fullname";
       die;
    }
  }
}
#-----------------------------------------------------------------------------------------
sub cleanTree {
  my ( %dir ) = @_;
  
  $dir{report}{"Directories scanned"}++;
  
  if ( $dir{path} ) {
    $dir{backup}    .= "/$dir{path}";
    $dir{original}  .= "/$dir{path}";
  }  
  
  my @files = getDir($dir{backup});
  say "Cleaning $dir{backup}: ".scalar(@files);

  for my $file (  sort @files ) {
    my $fullname = $dir{backup} . "/" . $file;
    if ( $file eq '.' or $file eq '..' ) {
      #say "Skipping: $fullname";
      next;
    }
    elsif ( -f $fullname ) { 
      cleanup( %dir, file => $file, );
    }
    elsif ( -d $fullname ) {    
      cleanTree( %dir, path => $file,  );
    } 
    else {
       say "WTF is $fullname";
       die;
    }
  }
}

#-----------------------------------------------------------------------------------------
sub backup {
  my %arg = @_;
  
  $arg{report}{"Files checked"}++;

  return if filesMatch( @_ );
  
  if (! -d $arg{to} ) {
    $arg{report}{"Directories created"}++;
    makeDir($arg{to}) unless -d $arg{to};
  }
    
  return unless -d $arg{to};
  
  my $to = $arg{to} . '/' . $arg{file};
  say "backupingup $arg{source} to $to";  

  $arg{report}{"Files backed up"}++;
  push @{$arg{files}}, $arg{source};
  cp($arg{source}, $to) or die $!;
  
  
}
#-----------------------------------------------------------------------------------------
sub cleanup {
  my %arg = @_;
  
  $arg{report}{"Files checked"}++;
  
  my $original = $arg{original} . '/' . $arg{file};
  
  if (! -f $original ) {
  my $file = "$arg{backup}/$arg{file}";
    say "removing $file";
    $arg{report}{"Files removed"}++;
    push @{$arg{files}}, $file;
    unlink $file or say "can not unlink $file";
  }
  else {
    #say "keeping because $original";
  }
  
}
#-----------------------------------------------------------------------------------------
sub makeDir {
  my ($to) = @_;
  
  say "making $to";
  
  my $err;
  eval { make_path($to, { error => \$err } )  };
  if ( scalar @$err ) {
    for my $error ( @$err ) {
      for my $key ( sort keys %$err ) {
        say "$key: $error->{$key}";
      }
    }
    die;
  }
#  else {
#    say "Happy";
#  }
    
  #seems to help reduce errors
  #sleep 1;

}
#-----------------------------------------------------------------------------------------
sub filesMatch {
  my %arg = @_;

  my $to = $arg{to} . '/' . $arg{file};
  
  my $match = 0;
  if ( $arg{fast} ) {
    $match = 1 if -d $arg{to} and -f $to;
  }
  else {
    $match = 1 if -d $arg{to} and -f $to and !compare( $arg{source}, $to, );
  }
    
  #my $source = getFileInfo( $arg{source} ) ;
  #my $dest   = getFileInfo( $to );
    
  #return 0 unless $source->{size} == $dest->{size};
  
  return $match;

}
#-----------------------------------------------------------------------------------------
sub getFileInfo {
  my ($file) = @_;

  my %file;
  
  @file{ qw(dev ino mode nlink uid gid rdev size
            atime mtime ctime blksize blocks) }
           = stat($file);

  return \%file;
}
#-----------------------------------------------------------------------------------------
sub getDir {
  my ( $path ) = @_;
  
  my @files;
  opendir (DIR, $path) or die $!;

  while (my $file = readdir(DIR)) {
    push @files, $file;
  }  

  closedir(DIR);
  
  return @files;

}
#-----------------------------------------------------------------------------------------
sub getSecondsAsTime {
  my $time = shift;

  my $hours   = int($time/3600);
  my $minutes = int(($time - $hours*3600)/60);
  my $seconds = $time % 60;

 
  my $return = substr('00'.int($seconds),-2);
  $return    = substr('00'.$minutes,-2) . ':' . $return if $minutes or $hours;
  $return    = substr('00'.$hours,-2)   . ':' . $return if $hours;
  
  return $return;
}