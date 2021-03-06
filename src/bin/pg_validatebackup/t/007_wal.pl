# Test pg_validatebackup's WAL validation.

use strict;
use warnings;
use Cwd;
use Config;
use File::Path qw(rmtree);
use PostgresNode;
use TestLib;
use Test::More tests => 7;

# Start up the server and take a backup.
my $master = get_new_node('master');
$master->init(allows_streaming => 1);
$master->start;
my $backup_path = $master->backup_dir . '/test_wal';
$master->command_ok(['pg_basebackup', '-D', $backup_path, '--no-sync' ],
					"base backup ok");

# Rename pg_wal.
my $original_pg_wal = $backup_path . '/pg_wal';
my $relocated_pg_wal = $master->backup_dir . '/relocated_pg_wal';
rename($original_pg_wal, $relocated_pg_wal) || die "rename pg_wal: $!";

# WAL validation should fail.
command_fails_like(['pg_validatebackup', $backup_path ],
				   qr/WAL parsing failed for timeline 1/,
				   'missing pg_wal causes failure');

# Should work if we skip WAL verification.
command_ok(['pg_validatebackup', '-n', $backup_path ],
		   'missing pg_wal OK if not verifying WAL');

# Should also work if we specify the correct WAL location.
command_ok(['pg_validatebackup', '-w', $relocated_pg_wal, $backup_path ],
		   '-w can be used to specify WAL directory');

# Move directory back to original location.
rename($relocated_pg_wal, $original_pg_wal) || die "rename pg_wal back: $!";

# Get a list of files in that directory that look like WAL files.
my @walfiles = grep { /^[0-9A-F]{24}$/ } slurp_dir($original_pg_wal);

# Replace the contents of one of the files with garbage of equal length.
my $wal_corruption_target = $original_pg_wal . '/' . $walfiles[0];
my $wal_size = -s $wal_corruption_target;
open(my $fh, '>', $wal_corruption_target)
	|| die "open $wal_corruption_target: $!";
print $fh 'w' x $wal_size;
close($fh);

# WAL validation should fail.
command_fails_like(['pg_validatebackup', $backup_path ],
				   qr/WAL parsing failed for timeline 1/,
				   'corrupt WAL file causes failure');
