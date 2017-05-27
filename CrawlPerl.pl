################################ Perl Document ################################

=head1 NAME

CrawlPerl

=head1 DESCRIPTION

CrawlPerl is a perl script to crawl the web.

     When the function is called initially, it creates a local folder
./Data/ within the same directory that will store all crawled data.
For each crawled site, a subdirectory within ./Data/ is created with
the name derived from url_root. All crawled data will be within there.

     A log file, crawlperl.log will be created in the main directory,
as well as a cookie file, cookie.txt.

=cut

package CrawlPerl;


################################## Packages ##################################

use strict;
use LWP::UserAgent;
use LWP::Protocol::http;
use HTTP::Cookies;
use HTTP::Request;
use HTTP::Response;
use HTML::LinkExtor;
use Time::Local;
use POSIX;
use Encode;
use IO::Handle;
use Data::Dumper;
use CrawlParse;
$|++;


############################### Global Variables ##############################

my $DEBUG = 0;
my $browser;
my $crawled_folder = "./data/";
my $local_root = "";
my $url_root = "";              # Only files under this root will be downloaded.
my $url_start = "";             # Where the crawling starts from.
my $url = "";                   # File url.
my $contents;                   # File contents
my %links_found;                # Hash to store links crawled.
my $links_found_ct = 0;         # Counter for links found.
my @link_queue;                 # Store links already crawled.
my $link_queue_pt = 0;          # pointer in $link_queue.
my $content_type;               # Content type of a file.
my $content_size;               # Content size of a file.
my $header_code;                # Response header code.
my @non_link_queue;             # Stores links that do not contain urls, e.g., images.
my $crawl_count = 0;            # Number of pages to crawl. 0 means infinite.
my $crawl_max_level = 0;        # How deep in levels the crawl can go. 0 => ininite.
my $download_bytes;             # Total bytes of downloaded files.
my $file_min_size = 0;          # Min file size to download.
my $file_max_size = 0;          # Max file size to download. 0 means infinite.
my $crawl_interval = 5;         # Wait (seconds) before crawling next html (startCrawl).
my $wait_interval = 1;          # Wait (seconds) before retrieving next url (getUrl).
my $flat_localpath = 0;         # Use only one level of sub-directory locally.
my $use_agent_firefox = 1;      # Simulate firefox browser in header
my $global_crawl = 0;           # If 1, allow crawl outside $url_root.
my $parse_html = 0;             # Parse bool.
my $total_size;                 # Total size of a file to download.
my $final_data;                 # The content of a downloaded file.
my $use_cookie = 1;             # Use cookie.
my $cookie_file = "cookie.txt"; # Cookie file.
my $referer_default = "http://google.com";    # default referer visiting a page.


############################### Switch Commands ###############################

my $overwrite = 0;
my $callback_t0;
my $verbose = 0;
my $get_outside_file = 1;
my $static_page_only = 0;
my $download_mime_type = 0xFFFFFFFF;

# each switch has its own var. This var simply switches how/what to crawl.
my $OPT_URL_ROOT_S = "-r";
my $OPT_URL_ROOT_L = "--url-root";
my $OPT_URL_START_S = "-u";
my $OPT_START_URL_L = "--url-start";
my $OPT_HELP_S = "-h";
my $OPT_HELP_L = "--help";
my $OPT_CRAWL_NUMBER_S = "-n";
my $OPT_CRAWL_NUMBER_L = "--number-crawl";
my $OPT_STATIC_ONLY_S = "-s";
my $OPT_STATIC_ONLY_L = "--static-only";
my $OPT_OUTSIDE_FILE_S = "-i";
my $OPT_OUTSIDE_FILE_L = "--include-outside-file";
my $OPT_DEBUG_S = "-d";
my $OPT_DEBUG_L = "--debug";
my $OPT_VERSION_S = "-v";
my $OPT_VERSION_L = "--version";
my $OPT_VERBOSE_S = "-b";
my $OPT_VERBOSE_L = "--verbose";
my $OPT_MIME_TYPE_S = "-m";
my $OPT_MIME_TYPE_L = "--mime-type";
my $OPT_WAIT_INTERVAL_S = "-w";
my $OPT_WAIT_INTERVAL_L = "--wait";
my $OPT_CRAWL_INTERVAL_S = "-c";
my $OPT_CRAWL_INTERVAL_L = "--crawl-interval";
my $OPT_MIN_SIZE_L  = "--min-size";
my $OPT_MAX_SIZE_L  = "--max-size";
my $OPT_FLAT_PATH_S = "-f";
my $OPT_FLAT_PATH_L = "--flat-localpath";
my $OPT_OVERWRITE_S = "-o";
my $OPT_OVERWRITE_L = "--overwrite";
my $OPT_CRAWL_MAX_LEVEL_S = "-l";
my $OPT_CRAWL_MAX_LEVEL_L = "--level-crawl";
my $OPT_GLOBAL_CRAWL_S = "-g";
my $OPT_GLOBAL_CRAWL_L = "--global-crawl";
my $OPT_DEFAULT_REFERER_S = "-e";
my $OPT_DEFAULT_REFERER_L = "--referer-default";
my $OPT_PARSE_HTML_S = "-p";
my $OPT_PARSE_HTML_L = "--parse-html";

my $total_size; # Total size of a file to download.
my $final_data; # The content of a downloaded file.


################################ Program Start ################################

MAIN: if (1) {
  &getOptions();

  if ($url_root eq "" && $url_start eq "") {
    print ("\nError: -url_root not provided.\n");
    printf ("For help, use command: perl $0 -h\n");
    exit(0);
  }

  if ($url_root eq "") {
    $url_root = &getUrlRootFromUrlStart();
  }
  if (! ($url_root =~ /\/$/)) {
    $url_root .= "/"; #ensure url_root ends with '/'
  }
  if ($url_root eq "$url_start/") {
    $url_start = "$url_start/";
  }
  if ($url_start eq "") {
    $url_start = $url_root;
  }

  if (! ($url_start =~ m/^$url_root/i)) {
    print ("\nError: url_root must be a prefix of url_start\n");
    exit(0);
  }

  my $log = &getLogName();
  open LOGFILE, ">> $log";

  output("");
  output("|---------- CrawlPerl Started ----------|");
  output("Spider released.");
  output("Url Root: $url_root");
  output("Url Start: $url_start");
  &getSite();

  close LOGFILE;
}

1;

############################## Program Functions ##############################

# getSite() starts to crawl from url_start
sub getSite() {
  my ($ss_s, $mm_s, $hh_s) = localtime(time);

  &createLocalDir(); # create local repository, if not exist.

  # create local root for this crawl task.
  $local_root = $crawled_folder . &getLocalRoot($url_root);

  if ($overwrite && -d $local_root) { clearHistory(); }

  if (! (-d $local_root)) {
    if (! &createPath($local_root)) {
      output("Abort. Cannot create local root: $local_root");
      return; # return instead of die(), to close LOGFILE handle.
    }
    output ("Local root $local_root is created");
    output ("");
  }

  my $history_exist = &findPrevCrawl();

  &logLastUrlStart(); # log which url_start this run uses.
  open LOG_Lnk_Found, ">> " . &getLnkFoundLog();
  open LOG_Lnk_Queue, ">> " . &getLnkQueueLog();
  #open LOG_Lnk_Queue_Index, "> " . &getLnkQueueIndexLog();

  if (! $history_exist) {
    #print "::$url_start\n";
    @link_queue = (@link_queue, $url_start);
    @non_link_queue = ();
    $links_found{$url_start} = -1;
    $links_found_ct = 1;
    &logLnkFound("1. $url_start => $links_found{$url_start}");
    &logLnkQueue("1. $url_start");
    $link_queue_pt = 0;
  }

  # perform the crawl
  &startCrawl();

  #close LOG_Lnk_Queue_Index;
  close LOG_Lnk_Queue;
  close LOG_Lnk_Found;

  my ($ss_t, $mm_t, $hh_t) = localtime(time);
  my $sec = ($hh_t - $hh_s) * 3600 + ($mm_t - $mm_s) * 60 + ($ss_t - $ss_s);
  output ("Total time spent: " . &writeTime($sec) );
}

# startCrawl() crawls the site, using BFS with a queue.
#
# Note:
# 1) A file is saved only when its mime type is wanted.
#    For text files, even if mime type is not wanted, the
#    contents have to be crawled to retrieve links.
# 2) text/html files, when first found, are inserted to %links_found
#    but have negative value, which means they have been found  but
#    have not been crawled yet. When they are crawled, their value is
#    changed to positive. This make crawl starting from different
#    url_start manageable.
#
sub startCrawl() {
  my $link_queue_len = @link_queue;
  my $resource_download_ct = 0;
  my %referers;
  $browser = getBrowser();
  $download_bytes = 0;  # Initialize total download size.

  while ($link_queue_pt < $link_queue_len) {
    # For testing, only get first $crawl_count number of links.
    if ( &crawlMaxNumReached($link_queue_pt) ) { last; }
    print ("wait for $crawl_interval seconds ...                   \r");
    sleep($crawl_interval);
    &clearProgressBar(); # clear the previous wait message.

    $url = $link_queue[$link_queue_pt];     # get next url to crawl.
    my $cur_url_level = $links_found{$url}; # should alwasy exist and < 0.
    if ($cur_url_level < 0) {
      $cur_url_level = - $cur_url_level;
      $links_found{$url} = - $links_found{$url};
    }

    # Do not crawl more than max levels.
    if ( &crawlMaxLevelReached($cur_url_level) ) { last; }

    # Otherwise, continue crawl.
    output( "link #" . (1 + $link_queue_pt) . ": $url" );

    # No longer get content type/size at the beginning of getUrl(), to save
    #      one head request per file. So the type is always "text/html" here,
    #      and the file is always downloaded no matter what the size is.
    $content_size = -1;
    $content_type = "text/html";
    $contents = &getUrl($url, $browser, $referers{$url} // $referer_default);
    my $content_len = length($contents);

    if ($content_len <= 0) { # if == 0, then may be "403 Access Forbidden".
      $link_queue_pt ++;
      &logLnkQueueIndex($link_queue_pt);
      next;
    }

    if (&mimeTypeMatch("text") && &fileSizeMatch($content_len)) {
      &saveContent($url, $contents, $content_type, $content_len);
    }
    # if don't get outside files, then dont parse links on this page.
    if (! $get_outside_file && &crawlMaxNumReached($link_queue_pt + 1) ) { last; }

    if ($parse_html) { &parseHtml($url, $contents); } # Parse through the page.

    print "parsing links, please wait..\r";
    my @new_urls = &parseLinks($url, $contents);

    foreach my $new_url (@new_urls) {
      # Remove link anchor like in "http://jacobsteves.ca/index.html#section_1".
      if ($new_url =~ /\#[a-z0-9\-\_\%\.]*$/i) {
        $new_url =~ s/\#[a-z0-9\-\_\%\.]*$//i;
      }

      # isWantedFile() calls getFileHeader(), and gets type/size for wanted files.
      my $isWanted = isWantedFile($new_url, $url);
      if ( $isWanted == 1 ) {
        #print "::$new_url, $content_type, $content_size\n";
        if ($content_type =~ /text\/html/i || $content_type eq "") {
          if (! exists($links_found{$new_url})) {
            #print "add to link Q: $new_url, type: $content_type\n";
            @link_queue = (@link_queue, $new_url);

            $link_queue_len ++; #= @link_queue;
            logLnkQueue("$link_queue_len. $new_url");
            $referers{$new_url} = $url; # record referer of page $new_url.

            # add found new_url with level, label as not crawled.
            $links_found{$new_url} = - ( $cur_url_level + 1 );
            $links_found_ct ++;
            &logLnkFound("$links_found_ct. $new_url => $links_found{$new_url}");
          }
        }
        else {
          if (! &mimeTypeMatch($content_type)) { # from getFileHeader().
            if ($verbose & 2) { print "* ignore (type_mismatch): $new_url\n"; }
          }
          elsif (! &fileSizeMatch($content_size)) { # from getFileHeader().
            if ($verbose & 4) { print "* ignore (size_mismatch): $new_url\n"; }
          }
          else {
            #print "add to non-link Q, and save: $new_url\n";
            $resource_download_ct += 1;
            output ("file #$resource_download_ct: $new_url");
            @non_link_queue = (@non_link_queue, $new_url);
            my $content = &getUrl($new_url, $browser, $url);
            my $content_len = length($content);
            &saveContent($new_url, $content, $content_type, $content_len);
          }
        }
      }
      else {
        if ($verbose & 4) {
          print "* reject (" . getRejectReason($isWanted) . "): $new_url\n";
        }
      }

      if (! exists($links_found{$new_url})) {
        $links_found{$new_url} = $cur_url_level + 1; # record crawl level.
        if ($content_type =~ /text\/html/i) { # html files should keep crawlable.
          $links_found{$new_url} = - $links_found{$new_url};
        }
        $links_found_ct ++;
        &logLnkFound("$links_found_ct. $new_url => $links_found{$new_url}");
      }
    }

    # Set this url as crawled.
    # If program crashes before this, next re-run will pick up this page.
    &logLnkFound("$links_found_ct. $url => $links_found{$url}");

    $link_queue_len = @link_queue;
    $link_queue_pt ++;
    &logLnkQueueIndex($link_queue_pt);
  }

  &clearProgressBar();
  &writeSummary($link_queue_pt);
}

# saveContent() saves a file to its respective local root
sub saveContent() {
  my ($url, $content, $content_type, $content_len) = @_;
  my $outfile;

  $content_type ||= "";
  if ($verbose & 1) {
    clearProgressBar();
    output( "   type: $content_type, Size: $content_len" );
  }
  if ($content_len <= 0) { return; }
  $download_bytes += $content_len; # public variable for total download size.

  &clearProgressBar();

  my $filename = getFilename($url);
  #print "saveContent(). url = $url, filename = $filename\n"  ;
  my $localpath = getLocalPath($url, $filename);
  &createPath($localpath);
  #print "saveContent(). url=$url, localpath = $localpath, filename=$filename\n";

  # This happens for default page under a directory.
  if ($filename eq "") {
    $filename = "index_";
  }

  if ($filename =~ /\?/) {
    $filename =~ s/\?/-/g; # replace "?" with "-", for dynamic page.

    my $t = &getMimeSubType($content_type);
    if ($t ne "") { $filename .= ".$t"; }
  }
  elsif (! ($filename =~ /\./)) {
    # this happens when the url ends with "/",
    # and the file to save is the default under this.
    # for example, index.html or default.html
    if ($filename eq "") {
      $filename = "index_";
    }

    # this happens when the file does not have a suffix,
    # e.g., when this is the index file under a directory.
    # then the directory name is used as a file name,
    # and no directory is created locally.
    my $t = &getMimeSubType($content_type);
    if ($t ne "") {
      $filename .= ".$t";
    }
    else {
      $filename .= ".html";
    } # default guess
  }

  if ($localpath =~ /\/$/) {
    $outfile = "$localpath$filename";
  }
  else {
    $outfile = "$localpath/$filename";
  }

  if ($DEBUG) {
    output ("save content to: $outfile");
  }

  if ($flat_localpath && -e $outfile) {
    $outfile = &resolveConflictName($outfile);
  }

  if (open OUTFILE, "> $outfile") {
    binmode(OUTFILE);
    print OUTFILE $content;
    close OUTFILE;
    if ($verbose & 2) { output ("* saved: $outfile"); }
  } else {
    output ("saveContent() error: cannot open file to save to: $outfile");
  }
}

# writeSummary() simply writes a download summary of the crawled data
sub writeSummary() {
  my ($link_queue_pt) =@_;
  my $link_queue_len = @link_queue;
  my $non_link_file_ct = @non_link_queue;

  my @keys = keys %links_found;
  my $links_found = @keys;

  output (" ");
  output ("Links found: $links_found");
  output ("Links crawlable: $link_queue_len");
  output ("Links crawled (A): $link_queue_pt");
  output ("Other files downloaded (B): $non_link_file_ct");
  output ("Total files downloaded (A+B): " . ($link_queue_pt + $non_link_file_ct));
  output ("Total download size: $download_bytes bytes, or "
          . getDownloadSize());
}

# crawlMaxNumReached() determines if the max crawl number has been reached
sub crawlMaxNumReached() {
  my ($link_queue_pt) = @_;
  return $crawl_count > 0 && $link_queue_pt >= $crawl_count;
}

# crawlMaxLevelReached() determies if the max crawl level has been reached
sub crawlMaxLevelReached() {
  my ($cur_url_level) = @_;
  return $crawl_max_level > 0 && ($cur_url_level > $crawl_max_level);
}

# clearHistory() overwrites crawl history for a previous crawl
# moves previous directory to dir_(k), k = 2, 3, ...
sub clearHistory() {
  if (! $overwrite) { return; }

  if (-d $local_root) {
    if ($overwrite == 1) {
      execCmd("mv $local_root " . &resolveConflictDirName($local_root));
    }
    elsif ($overwrite == 2) {
      execCmd("rm -rf $local_root");
    }
  }
}

# findPrevCrawl() reads the log of a previous crawl and resumes from a breaking
#     point, rather than crawling the same place again unless overwritten
sub findPrevCrawl() {
  my $file = &getLnkFoundLog();
  if (! (-e $file)) { return 0; }
  open FILE, "< $file" or die "findPrevCrawl(): cannot read file $file";
  while(<FILE>) {
    chomp();
    #print "$_\n";
    if (m/(\d+)\.\s(.+)\s=\>\s([-]?\d+)/) {
      #print "$2 ... $3\n";
      $links_found{$2} = $3;
      #print "links_found{$2} = $3;\n";
    }
  }
  close FILE;
  my @keys = keys %links_found;
  $links_found_ct = @keys;

  $file = &getLnkQueueLog();
  if (! (-e $file)) {
    return 0;
  }
  # otherwise, initialize history.

  # link_queue
  $file = &getLnkQueueLog();
  open FILE, "< $file" or die "findPrevCrawl(): cannot read file $file";
  while(<FILE>) {
    chomp();
    if (m/(\d+)\.\s(.+)/) {
      @link_queue = (@link_queue, $2);
    }
  }
  close FILE;

  # link_queue_pt
  $file = &getLnkQueueIndexLog();
  if (! -e $file) {
    $link_queue_pt = 0;
    return 1;
  }

  open FILE, "< $file" or die "findPrevCrawl(): cannot read file $file";
  while(<FILE>) {
    chomp();
    #print "$_\n";
    $link_queue_pt = $_;
  }
  close FILE;

  @non_link_queue = ();

  return 1;
}

sub dumpHash() {
  my $h = shift;
  my %hash = %$h;
  my @keys = keys %hash;
  my $i = 0;
  foreach my $key (@keys) {
    ++ $i;
    print "$i. $key => $hash{$key}\n";
  }
}

sub getBrowser() {
  push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, SendTE=>0);
  my $browser = LWP::UserAgent->new(keep_alive=>1);
  $browser->timeout(10);

  # Use cookie.
  if ($use_cookie) {
    my $cookie_jar = HTTP::Cookies->new(
      file => "$cookie_file",
      autosave => 1,
      ignore_discard => 1,
    );
    $browser->cookie_jar( $cookie_jar );
  }

  # Simulate Firefox Agent.
  if ($use_agent_firefox) {
    $browser->default_headers(HTTP::Headers->new(
      'User-Agent' => 'Mozilla/5.0 (Windows NT 5.1; rv:30.0) Gecko/20100101 Firefox/30.0',
      'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language' => 'en-US,en;q=0.5',
    ));
  }

  return $browser;
}

sub displayVersion() {
  print "\nCrawlPerl version 1.0.\n\n";
}

# Get specific log name by replacing the .pl with .log
sub getLogName() {
  my $log = $0;
  if ($log =~ /\.pl/i) { $log =~ s/\.pl/\.log/i; }
  else { $log .= ".pl"; }
  return $log;
}

sub getLnkFoundLog() {
  return "$local_root/.crawlperl_lnk_found.log";
}

sub getLnkQueueLog() {
  return "$local_root/.crawlperl_" . getQueueLogName() . "_lnk_Q.log";
}

sub getLnkQueueIndexLog() {
  my $name = $url_start;
  $name =~ s/^$url_root//;
  $name = encodePath($name);
  return "$local_root/.crawlperl_" . getQueueLogName() . "_lnk_Q_ID.log";
}

sub getLastUrlStartLog() {
  return "$local_root/.crawlperl_last_url_start.log";
}

# Get a logname specific to each url_start
sub getQueueLogName() {
  my $name = $url_start;
  $name =~ s/^$url_root//;
  $name = encodePath($name);
  $name =~ s/[\/\.]/_/g; # replace all "/" and "." with "_".
  return $name;
}

# createLocalDir() creates a local repository to store crawled data
sub createLocalDir() {
  if (! (-d $crawled_folder)) {
    if (! &createPath($crawled_folder)) {
      output("Cannot create local repository: $crawled_folder");
      die();
    }
    output ("Local repository $crawled_folder is created");
  }
}

# getLocalRoot grabs data from url_root
sub getLocalRoot() {
  my ($root) = @_;
  if ($DEBUG) { output ("getLocalRoot(): root = $root" ); }

  $root = &removeHttpHdr($root);
  if ($root =~ /\/$/) { $root =~ s/\/$//; } # remove trailing "/" if any.

  $root =~ s/\//_/g; # replace all "/" with "_".
  $root = encodePath($root);

  #$root = $crawled_folder . $root;
  if ($DEBUG)
  {
    output ("getLocalRoot(): local_root = $root" );
  }

  return $root;
}

# removeHttpHdr() removes "http://" or "https://" from head of string
sub removeHttpHdr() {
  my ($s) = @_;
  if ($s =~ /^http:\/\//i) { $s =~ s/^http:\/\///i; }
  elsif ($s =~ /^https:\/\//i) { $s =~ s/^https:\/\///i; }
  return $s;
}

sub displayHelp() {
  my $usage = <<"END_USAGE";

Usage: perl $0 $OPT_URL_START_S <url_start> [$OPT_URL_ROOT_S <url_root>] [-options]

  NOTE: <val> represents a value. Example,
    -b <verbose>
          would be implemented with verbose level 3 like..
    -b 3

  Options:
    -b <verbose>: print more details of crawling.
        0 (default value) - print only basic information of urls/links crawled.
        0x1 = 1 - print the type/size and file download information.
        0x2 = 2 - print the saved file local path.
        0x4 = 4 - print the reject/ignore file reason.
    --verbose: same as -b

    -c <seconds>: wait time in seconds before crawling next html page.

    -d: debug, print debug information.
    --debug: same as -d

    -e <default referer>: default referer when crawling a url, if none exists.
        This is used when crawling the first page, when no referer exists yet.
    --referer-default: same as -e

    -f: use flat local path: only one level under local root.
    --flat-localpath: same as -f

    -g: allow global crawl outside url_root.
    --global-crawl: same as -g

    -h: print this help message.
    --help: same as -h

    -i <0 || 1>: download non-text files outside the url_root. Value is on(1)/off(0). Default is on.
        Used when some linked files are stored outside the url_root.
    --include-outside-file: same as -i

    -l <level number>: max levels to crawl. Default to 0, 0 means inifinite.
    --level-crawl: same as -l

    -m <mime type>: file MIME type. Only files with given MIME types are downloaded.
        text - 0x1 = 1
        image - 0x2 = 2
        audio - 0x4 = 4
        video - 0x8 = 8
        For more options, head to: http://en.wikipedia.org/wiki/Internet_media_type
    --mime_type: same as -m

    -n <number of links>: the number of links to crawl. 0 means inifinite.

    -o <0 || 1 || 2>: overwrite previous download result.
        0: do not overwrite; 1: move from Dir to Dir-2; 2: remove.
        When not specify -o, is 0; when use -o without a value, default to 1.
    --overwrite: same as -o

    -r <url_root>: root url.
        Only files under this path are downloaded. Except when -o is used.
    --url-root: same as -r

    -s: only download static pages.
        Dynamic pages with parameters like http://test.php?a=b are ignored.
    --static-only: same as -s

    -u <url_start>: start url.
        This is where a crawling task starts from.
    --url_start: same as -u

    -v: show version information.
    --version: same as -v

    -V: verbose.
    --verbose: same as -V

    -w <seconds>: wait time (seconds) before getting next url. Difference of this
        with -c is: on each html page, there can be several urls. -c is
        for each html page, -w is for each url.
    --wait: same as -w

  Other Options:
    --min-size: min file size to download, in bytes.
    --max-size: max file size to download, in bytes. 0 means infinite.
    --number-crawl: same as -t

  The two crucial options are:
  -r or --url-root : url_root is needed, if not provided, use longest path of url_start.
  -u or --url-start: url_start, if not provided, use url_root as default.

  -r, -u, or both must be provided for the spider to be released.

  If an url contains special characters, like space or '&', then
  it may need to be enclosed in double quotes.

  To see perldoc document, type: perldoc $0

  Examples:
    perl $0 -h
    perl $0 -r http://test.com
    perl $0 -u http://test.com/index.html
    perl $0 -r http://test.com -u http://test.com/about.html
    perl $0 --url-root http://test.com
    perl $0 --url-root http://test.com --url-start http://test.com/
    perl $0 --url-root http://test.com -n 1 -m 2 -f --min-size 15000

  Remember to be specific when specifing crawlers.
  http://test.com may not work, while http://test.com/index.html may work.

  Happy Crawling.

END_USAGE

  print $usage;
}

# this function gets the longest possible path as root
sub getUrlRootFromUrlStart() {
  my $f = &getUrlPath($url_start);
  return $f;
}

# getDomain() returns the domain of a url
# example: returns "http://reddit.com" from "http://reddit.com/r/uwaterloo"
sub getDomain() {
  my ($f) = @_;
  $f = &removeHttpHdr($f);
  my $index = index($f, "/");
  if ($index >= 0) {
    $f = substr($f, 0, $index);
  }
  return $f;
}

# getOptions() grabs the command line switch and sets it to a global variable
# effects: creates and alters $state;
sub getOptions() {
  my $ARGV_LEN = @ARGV;
  my $state = "";

  for (my $i = 0; $i < $ARGV_LEN; ++ $i) {
    if ($DEBUG) {
      print "argv[$i]. " . $ARGV[$i] . "\n";
    }

    my $a = $ARGV[$i];

    # Options followed with a value.
    if ($a eq $OPT_URL_ROOT_S || $a eq $OPT_URL_ROOT_L) {
      $state = $OPT_URL_ROOT_S;
    }
    elsif ($a eq $OPT_URL_START_S || $a eq $OPT_START_URL_L) {
      $state = $OPT_URL_START_S;
    }
    elsif ($a eq $OPT_MIME_TYPE_S || $a eq $OPT_MIME_TYPE_L) {
      $state = $OPT_MIME_TYPE_S;
    }
    elsif ($a eq $OPT_WAIT_INTERVAL_S || $a eq $OPT_WAIT_INTERVAL_L) {
      $state = $OPT_WAIT_INTERVAL_S;
    }
    elsif ($a eq $OPT_CRAWL_INTERVAL_S || $a eq $OPT_CRAWL_INTERVAL_L) {
      $state = $OPT_CRAWL_INTERVAL_S;
    }
    elsif ($a eq $OPT_CRAWL_MAX_LEVEL_S || $a eq $OPT_CRAWL_MAX_LEVEL_L) {
      $state = $OPT_CRAWL_MAX_LEVEL_S;
    }
    elsif ($a eq $OPT_DEFAULT_REFERER_S || $a eq $OPT_DEFAULT_REFERER_L) {
      $state = $OPT_DEFAULT_REFERER_S;
    }
    elsif ($a eq $OPT_OUTSIDE_FILE_S || $a eq $OPT_OUTSIDE_FILE_L) {
      $state = $OPT_OUTSIDE_FILE_S;
    }
    elsif ($a eq $OPT_VERBOSE_S || $a eq $OPT_VERBOSE_L) {
      $verbose = 2; # default verbase level is 2, if no value provided.
      $state = $OPT_VERBOSE_S;
    }
    elsif ($a eq $OPT_OVERWRITE_S || $a eq $OPT_OVERWRITE_L) {
      $overwrite = 1; # default to 1: move previous dir D to D-2.
      $state = $OPT_OVERWRITE_S;
    }
    elsif ($a eq $OPT_MIN_SIZE_L) {
      $state = $OPT_MIN_SIZE_L;
    }
    elsif ($a eq $OPT_MAX_SIZE_L) {
      $state = $OPT_MAX_SIZE_L;
    }

    # Options whose value is on/off, and do not follow with a value.
    elsif ($a eq $OPT_CRAWL_NUMBER_S || $a eq $OPT_CRAWL_NUMBER_L) {
      $crawl_count = 1; $state = $OPT_CRAWL_NUMBER_S;
    }
    elsif ($a eq $OPT_STATIC_ONLY_S || $a eq $OPT_STATIC_ONLY_L) {
      $static_page_only = 1; $state = "";
    }
    elsif ($a eq $OPT_DEBUG_S || $a eq $OPT_DEBUG_L) {
      $DEBUG = 1; $state = "";
    }
    elsif ($a eq $OPT_FLAT_PATH_S || $a eq $OPT_FLAT_PATH_L) {
      $flat_localpath = 1; $state = "";
    }
    elsif ($a eq $OPT_GLOBAL_CRAWL_S || $a eq $OPT_GLOBAL_CRAWL_L) {
      $global_crawl = 1; $state = "";
    }
    elsif ($a eq $OPT_PARSE_HTML_S || $a eq $OPT_PARSE_HTML_L) {
      $parse_html = 1; $state = "";
    }

    # Options that cause the program to display a message and exit.
    elsif ($a eq $OPT_VERSION_S || $a eq $OPT_VERSION_L) {
      &displayVersion(); exit(0);
    }
    elsif ($a eq $OPT_HELP_S || $a eq $OPT_HELP_L) {
      &displayHelp(); exit(0);
    }

    # Get values for options with a value.
    elsif ($state eq $OPT_URL_ROOT_S) {
      $url_root = $a; $state = "";
    }
    elsif ($state eq $OPT_URL_START_S) {
      $url_start = $a; $state = "";
    }
    elsif ($state eq $OPT_CRAWL_NUMBER_S) { # max links to crawl.
      $crawl_count = getPosInt($a); $state = "";
    }
    elsif ($state eq $OPT_MIME_TYPE_S) {
      $download_mime_type = getPosInt($a); $state = "";
    }
    elsif ($state eq $OPT_WAIT_INTERVAL_S) {
      $wait_interval = getPosInt($a); $state = "";
    }
    elsif ($state eq $OPT_CRAWL_INTERVAL_S) {
      $crawl_interval = getPosInt($a); $state = "";
    }
    elsif ($state eq $OPT_MIN_SIZE_L) {
      $file_min_size = getPosInt($a); $state = "";
    }
    elsif ($state eq $OPT_MAX_SIZE_L) {
      $file_max_size = getPosInt($a); $state = "";
    }
    elsif ($state eq $OPT_CRAWL_MAX_LEVEL_S) {
      $crawl_max_level = getPosInt($a); $state = "";
    }
    elsif ($state eq $OPT_DEFAULT_REFERER_S) {
      $referer_default = $a; $state = "";
    }
    elsif ($state eq $OPT_VERBOSE_S) {
      $verbose = getPosInt($a); $state = "";
    }
    elsif ($state eq $OPT_OVERWRITE_S) {
      $overwrite = getPosInt($a); $state = "";
      if ($overwrite > 2) { $overwrite = 2; }
    }
    elsif ($state eq $OPT_OUTSIDE_FILE_S) {
      $get_outside_file = getPosInt($a); $state = "";
    }

    else {
      print "Warning: unknown option $a\n";
      $state = "";
    }
  }
}

# getPosInt() converts a string to a positive integer
sub getPosInt() {
  my ($n) = @_;
  $n = 0 + $n; # convert string to integer.
  if ($n < 0) { $n = 0; }
  return $n;
}

# getDownloadSize() returns the size of the currently downloading file
sub getDownloadSize() {
  my $size;
  if ($download_bytes < 1000000) { # less than 1 MB.
    $size = sprintf("%.3f", $download_bytes/1024) . " KB";
  }
  elsif ($download_bytes < 1000000000) { # less than 1 GB.
    $size = sprintf("%.3f", $download_bytes/1024/1024) . " MB";
  }
  else {
    $size = sprintf("%.3f", $download_bytes/1024/1024/1024) . " GB";
  }
  return $size;
}

# writeTime() returns a string of the time of the download
sub writeTime() {
  my ($sec) = @_;
  my ($h, $m, $s);

  $h = floor($sec / 3600);
  if ($h < 10) { $h = "0$h"; }

  $m = floor(($sec - ($h * 3600)) / 60);
  if ($m < 10) { $m = "0$m"; }

  $s = $sec - ($h * 3600) - ($m * 60);
  if ($s < 10) { $s = "0$s"; }

  return "$h:$m:$s";
}

sub getUrl() {
  #wait a bit, so that the request doesnt overload
  sleep($wait_interval);

  my ($url, $browser, $referer) = @_;
  $final_data = "";

  $total_size = $content_size // -1;

  $callback_t0 = time(); # Download start time.
  # now do the downloading.
  my $request = new HTTP::Request('GET', "$url");
  if ($referer ne "") { $request->referer("$referer"); }
  my $response = $browser->request($request, \&callback, 8192);

  return $final_data; # File content.
}

# callback updates the progressbar in chunks
sub callback {
   my ($data, $response, $protocol) = @_;
   $final_data .= $data;
   #print "callback: len = " . length($final_data) . "\n";

   my $time_left = 0;
   my $t_used = time() - $callback_t0; # Time used so far.
   if ($t_used > 0) {
     my $cur_size = length($final_data);
     $time_left = (($total_size - $cur_size) / $cur_size) * $t_used;
   }
   print progressBar( length($final_data), $total_size, 25, '=', $time_left );
}

# progressBar simply prints the progress bar
sub progressBar {
  my ( $got, $total, $width, $char, $time_left ) = @_;
  $width ||= 25; $char ||= '-'; # "||=": default to if not defined.
  $time_left ||= 0;

  # Some web servers don't give "content-length" field.
  # In such case don't print progress bar.
  if ($total == -1) { return; }

  my $num_width = length ($total);

  if ($got == -1) {
    # removes the previous print out.
    # 79 is used since in standard console, 1 line has 80 chars.
    # 79 spaces plus a "\r" is 80 chars.
    # Besides, this should be enough to cover reasonable file sizes.
    # e.g. the progress bar below has 64 chars, when file size is 6-digit.
    # |========================>| Got 100592 bytes of 100592 (100.00%)
    # So 12 chars are used for file size, 52 chars for the rest bytes.
    # This gives 79 - 52 = 27 bytes for file size, so file size
    # can be up to 13 digits without interrupting the format.
    sprintf (' ' x 79) . "\r";
  }
  else {
    sprintf
      "|%-${width}s| Got %${num_width}s bytes of %s (%.2f%%, %.1fsec)   \r",
      $char x (($width-1)*$got/$total). '>',
      $got, $total, 100*$got/+$total,
      $time_left;
  }
}

# clearProgressBar() resets the bar for the next useage
sub clearProgressBar() {
  print progressBar(-1, 0, 0, '');
}

# parseHtml() parses though the html files
# Implmentation is in crawlparse.pm.
sub parseHtml() {
  my ($url, $contents) = @_;

  my $parser = new CrawlParse;
  $parser->init_params($url, 1);
  $parser->parse($contents)->eof;
  $parser->outputText();
}

# parseLinks() grabs links thorugh parseHTML and opens them
sub parseLinks() {
  my ($url, $contents) = @_;
  my ($page_parser) = HTML::LinkExtor->new(undef, $url);

  $contents = &getCustomLinks($contents);

  $page_parser->parse(decode_utf8 $contents)->eof;

  my @links = $page_parser->links;
  my @urls;

  foreach my $link (@links) {
    @urls = (@urls, $$link[2]);
  }
  return @urls;
}

# linkIsCrawled() returns true (1) if the link has been crawled successfully
sub linkIsCrawled() {
  my ($new_link) = @_;
  if (exists($links_found{$new_link}) # file found, may or may not crawled.
      && $links_found{$new_link} > 0  # text/html file, found but not crawled.
      ) {
    return 1;
  }
  return 0;
}

# isInsideDomain() returns true (1) if the link is within all searchable roots
#    and false (0) otherwise
#    ie, within url_root
sub isInsideDomain() {
  my ($link) = @_;
  if ($link =~ /^$url_root/i) { return 1; }
  return 0;
}

# fileSizeMatch() returns true (1) if the file size is between max and min limit
#     inclusively, false (0) otherwise.
sub fileSizeMatch() {
  my ($content_len) = @_;
  #print "content: $content_len. min=$file_min_size, max=$file_max_size\n";
  if ($content_len == -1) { return 1; } # Header contains no size, download anyway.
  if ($content_len < $file_min_size) { return 0; }
  if (($file_max_size > 0) && ($content_len > $file_max_size)) { return 0; }
  return 1;
}

# getFileHeader() gets file type and size.
# content_size is undefined => size = -1
# $result->is_error() is true => the code is 403, 404, 500 error etc
sub getFileHeader() {
  my ($link, $referer) = @_;

  my $request = new HTTP::Request('HEAD', "$link");
  if ($referer ne "") { $request->referer("$referer"); }
  my $result = $browser->request($request);

  if (0) {
    print "status line: " . $result->status_line() . "\n";
    print "status code: " . $result->code() . "\n";
    print "status msg: " . $result->message() . "\n";
    print "status is_error: " . $result->is_error() . "\n";
    print "status is_success: " . $result->is_success() . "\n";
    print "status is_info: " . $result->is_info() . "\n";
    print "status is_redirect: " . $result->is_redirect() . "\n";
    print "header('Location'): " . $result->request->uri . "\n";
    print "status last_modified: " .
          getLocaltime( $result->last_modified() ) . "\n";
    print "status encoding: " . ($result->content_encoding() // "") . "\n";
    print "status language: " . ($result->content_language() // "") . "\n";
    print "status current_age: " . $result->current_age() . "\n";     # seconds
    print "status lifetime: " . $result->freshness_lifetime() . "\n"; # seconds
    print "status is_fresh: " . $result->is_fresh() . "\n";
    print "status fresh_until: " .
          getLocaltime( $result->fresh_until() ) . "\n";
    print "status base: " . $result->base() . "\n";
    print Dumper($result->headers);
    exit(0);
  }

  $header_code = $result->code() // ""; # response header code.

  if ($result->is_error()) {
    if ($DEBUG) { print "error ($link): code = " . $result->code() . "\n"; }
    return 0;
  }

  my $remote_headers = $result->headers;
  if ($DEBUG)
  { print "getFileHeader(): " . Dumper($remote_headers); }

  # Most servers return content-length, but not always.
  $content_size = $remote_headers->content_length // -1;
  $content_type = $remote_headers->content_type // "";

  if ($DEBUG)
  {
    output ("getFileHeader(): $link type: $content_type, size: $content_size");
  }

  return 1;
}

# getLocaltime() returns the time local to the user
sub getLocaltime() {
  my ($t) = @_;
  if ($t eq "") { return ""; }
  return scalar(localtime($t));
}

# isWantedFile() determies if the possible link is a wanted file.
# In our cases, we want either text/html/image files, so this checks that.
sub isWantedFile() {
  my ($link, $referer) = @_;

  $content_type = "";
  $content_size = 0;
  $header_code = "";

  if (&linkIsCrawled($link)) {
    return -1;
  }
  if ($static_page_only && $link =~ /\?(\S+=\S*)+$/i) {
    return -2;
  }

  if (! &getFileHeader($link, $referer)) {
    return -3;
  }

  if (! $global_crawl && ! &isInsideDomain($link)) {

    if ($get_outside_file && ! ($content_type =~ /^text/i)) {
      return 1;
    }

    return -4;
  }

  return 1;
}

# getRejectReason() returns the reason a file is rejected by isWantedFile()
sub getRejectReason() {
  my ($code) = @_;
  my $msg;
  if ($code == -1) { $msg = "is_crawled"; }
  elsif ($code == -2) { $msg = "is_dynamic"; }
  elsif ($code == -3) { $msg = "header_code: $header_code"; }
  elsif ($code == -4) { $msg = "outside_domain"; }
  else { $msg = "unknown"; }

  return $msg;
}

# getMimeSubType returns a file's mime sub type
sub getMimeSubType() {
  my ($type) = @_;
  if (($type // "") ne "") {
    my @tmp = split(';', $type); # for cases like: "text/html; charset=utf-8"
    my @tmp2 = split('/', $tmp[0]);
    #print "mime type: $tmp2[1]\n";
    if (length(@tmp2 >= 2) && $tmp2[1] ne "") {
      return $tmp2[1];
    }
  }
  return "";
}

# getMimeTypeCode() returns the hex-code of a specific mime type
sub getMimeTypeCode() {
  my ($mime) = @_;
  $mime = lc($mime);
  if ($mime =~ /^text/) { return 0x1; }
  elsif ($mime =~ /^image/) { return 0x2; }
  elsif ($mime =~ /^audio/) { return 0x4; }
  elsif ($mime =~ /^video/) { return 0x8; }
  elsif ($mime =~ /^application/) { return 0x10; }
  elsif ($mime =~ /^message/) { return 0x20; }
  elsif ($mime =~ /^model/) { return 0x40; }
  elsif ($mime =~ /^multipart/) { return 0x80; }
  elsif ($mime =~ /^example/) { return 0x100; }
  elsif ($mime =~ /^application\/vnd/) { return 0x200; }
  elsif ($mime =~ /^application\/x/) { return 0x400; }
  else { return 0xFFFFFFFF; } # unknown type, download anyway.
}

# mimeTypeMatch() returns true (1) if the file's mime type is wanted, false
#     otherwise
sub mimeTypeMatch() {
  my ($content_type) = @_;
  #print "(&getMimeTypeCode($content_type) & $download_mime_type) != 0 ?\n";
  return (&getMimeTypeCode($content_type) & $download_mime_type) != 0;
}

# execCmd() executes a command and records in with output()
sub execCmd() {
  my $cmd = shift;
  output($cmd);
  `$cmd`;

  if ($? == -1) {
    output( "execCmd() warning: failed to execute: $!" );
  }
  elsif ($? & 127) {
    output( "execCmd() warning: command died with signal " . ($? & 127) .
            ", " . (($? & 128) ? 'with' : 'without') . " coredump" );
  }
  elsif ($? != 0) {
    output( "execCmd() warning: command exited with value " . ($? >> 8) );
  }

  return $?;
}

# getLocalPath() returns the local path from the remote url, creating a local
#    directory if need be
sub getLocalPath() {
  my ($path, $filename) = @_;
  if ($DEBUG) {
    print "getLocalPath(): remote path=$path, filename=$filename\n";
  }

  # When global_crawl is on, path is outside url_root.
  # Call the extension function.
  if ($global_crawl && ! &isInsideDomain($path)) {
    return &getLocalPath_outsideDomain($url, $filename);
  }
  # Otherwise, path is inside url_root. Process below.

  if ($flat_localpath) { return $local_root; } # Use flat path.

  # Remove filename from path.
  $path = substr($path, 0, length($path) - length($filename));
  if ($path =~ /^\//) { $path =~ s/^\///; } # remove trailing /.
  #print "after remove filename: $path\n";

  if ($path =~ /^$url_root/i) {
    $path =~ s/^$url_root//i;
    if ($local_root =~ /\/$/) { $path = "$local_root$path"; }
    else {$path = "$local_root/$path"; }
  } else { # not under the same $url_root. create different local root.
    $path = $crawled_folder . &getLocalRoot($path);
  }

  $path = encodePath($path);
  if($DEBUG) { print "getLocalPath(): local dir=$path\n"; }

  return $path;
}

# getLocalPath_outsideDomain() is similar to getLocalPath(), just outside
#     of the original domain
sub getLocalPath_outsideDomain() {
  my ($path, $filename) = @_;

  if ($flat_localpath) {
    $path = encodePath( &getDomain($path) );
    $path = "$crawled_folder/$path";
    return $path;
  }

  $path = &removeHttpHdr($path);

  $path = substr($path, 0, length($path) - length($filename));
  $path = "$crawled_folder" . encodePath($path);
  #print "getLocalPath_outsideDomain: path=$path, file=$filename\n";

  return $path;
}

#encodePath() returns the correctly encoded path. In windows, the path name
#    cannot be any of: \/:*?"<>| so it gets replaced with "-".
sub encodePath() {
  my ($path) = @_;
  if ($path =~ m/[\:\*\?\"\<\>\|]/) {
    $path =~ s/[\:\*\?\"\<\>\|]/-/g;
  }
  return $path;
}

sub createPath() {
  my ($path) = @_;
  if (-d $path) {
    return 1;
  }
  &execCmd("mkdir -p \"$path\"");
  if (! -d $path) {
    return 0;
  }
  return 1;
}

# getUrlPath() returns the path without filename, to go back and crawl more
sub getUrlPath() {
  my ($path) = @_;

  # if $path ends with "/", just return it.
  if ($path =~ m/\/$/) { return $path; }

  # else, remove the filename path and return the rest.
  my $file = &getFilename($path);
  $path =~ s/$file$//;

  return $path;
}

# output prints to both the log file and STDOUT
sub output {
  my ($msg) = @_;

  print "$msg\n";

  # Log for every change by flush log file handle.
  # If log in batch mode, may lose intermediate
  # information when the program process is killed.
  print LOGFILE (localtime(time) . " $msg\n");
  LOGFILE->autoflush;
}

# resolveConflictName() will resolve files with name conflicts.
# example: two file.txt => creates file.txt and file_(2).txt
sub resolveConflictName() {
  my ($outfile) = @_;

  my $filename = getFilename($outfile);
  my $outpath = $outfile;
  $outpath =~ s/$filename$//;
  my $suffix = getFileSuffix($filename);
  $filename =~ s/$suffix$//;
  # $outfile is now split to 3 parts: path, name, suffix.

  my $ct = 2;
  while (1) {
    my $outfile = "$outpath$filename\_($ct)$suffix";
    if (! -e $outfile) { return $outfile; }
    ++ $ct;
  }

  return ""; # should never happen.
}

#getFileSuffix() returns the suffix path of a filename
sub getFileSuffix() {
  my ($file) = @_;
  my $i = rindex($file, ".");
  my $suffix = substr($file, $i);
  return $suffix;
}

# resolveConflictDirName() is similar to resolveConflictName() except it
#     resovle conflicts for directory folders
sub resolveConflictDirName() {
  my ($outfile) = @_;

  my $endChar = "";
  if ($outfile =~ /\/$/) {
    $endChar = "/";
    $outfile =~ s/\/$//;
  } # remove trailing "/" if any.

  my $ct = 2;
  while (1) {
    my $outfile = "$outfile\-$ct";
    if (! -e $outfile) { return $outfile . $endChar; }
    ++ $ct;
  }

  return ""; # should never happen.
}

# getFilename() returns the extracted file name from the url
sub getFilename() {
  my ($path) = @_;
  my $filename = "";

  $path = &removeHttpHdr($path);

  my $i = rindex($path, "/");
  if ($i > 0) { $filename = substr($path, $i + 1); }
  return $filename;
}

############################### Log Functions ################################

sub logLnkFound() {
  my ($msg) = @_;
  print LOG_Lnk_Found ("$msg\n");
  LOG_Lnk_Found->autoflush;
}

sub logLnkQueue() {
  my ($msg) = @_;
  print LOG_Lnk_Queue ("$msg\n");
  LOG_Lnk_Queue->autoflush;
}

sub logLnkQueueIndex() {
  my ($msg) = @_;
  open LOG_Lnk_Queue_Index, "> " . &getLnkQueueIndexLog();
  print LOG_Lnk_Queue_Index ("$msg\n");
  close LOG_Lnk_Queue_Index;
}

sub logLastUrlStart() {
   my $file = &getLastUrlStartLog();
   open FILE, "> $file" or die "Cannot open file to save: $file";
   print FILE ($url_start);
   close FILE;
}

sub getCustomLinks() {
  my ($s) = @_;

  if ($s =~ m/data\-original/i) {
    $s =~ s/data\-original/src/gi; # for <img />
  }

  return $s;
}
