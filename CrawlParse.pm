############################### Perl Document ###############################

=head1 NAME

CrawlParse

=head1 DESCRIPTION

CrawlParse parses the contents of a html file, stores the extracted text
in an internal array (@lines). This array can be printed to an output file by
function outputText(), or be returned to the caller by function getLines().
The caller should first call function init_params() to set up options.

=cut


use strict;

package CrawlParse;
use base "HTML::Parser";

############################## Global Variables ###############################

my $DEBUG = 0;                      # Used for development/debug only.
my $OUTFILE = "CrawlParse_out.txt"; # Output file, store parse result.
my $log_outfile = 0;                # If 1, write parse result to output file.
my $filename = "File";              # Default name for the html file to parse.

# lines is the array that will store all lines of code
my @lines = ();

########################### Definition of functions.###########################

# init_params() initializes our parameters.
sub init_params() {
  my ($self, $html_file, $log_mode) = @_;

  $filename = $html_file;

  if ($log_mode == 1) { $log_outfile = 1; }
  else { $log_outfile = 0; }
}


# text extract all texts, store in @lines. Only non-empty lines are stored.
sub text {
  my ($self, $text) = @_;

  # Must first trim, then chomp.
  $text = &trim( $text );
  chomp($text);
  $text = &trim( $text );

  if ($text ne "") {
    if ($DEBUG) { print ": $text\n"; }
    push @lines, $text;
  }
}

# outputText() write @lines array to output text.
sub outputText() {
  if ($log_outfile) {
    open FILE, ">> $OUTFILE" or die "Cannot write to output file $OUTFILE\n";
    print FILE "== $filename ==\n";
    foreach my $line (@lines) {
      print FILE "$line\n";
    }
    close FILE;
  }
}

# getLines() returns the @lines array to caller.
sub getLines() {
  return @lines;
}

# Utility functions.
sub ltrim { my $s = shift; $s =~ s/^\s+//; return $s; }
sub rtrim { my $s = shift; $s =~ s/\s+$//; return $s; }
sub trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s; }


1;
