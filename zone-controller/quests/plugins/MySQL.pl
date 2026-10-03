#::: Akkadius
#::: Description: These plugins are MySQL loaders in use with Perl DBI
#::: For plug and play, LoadMysql will load your database credentials from eqemu_config.json

my $MYSQL_CONFIG_CACHE = undef;
my $MYSQL_DSN_CACHE = "";
my $MYSQL_USER_CACHE = "";
my $MYSQL_PASS_CACHE = "";
my $MYSQL_DBH_CACHE = undef;

sub _LoadMysqlConfigCached {
	use JSON::PP;

	return $MYSQL_CONFIG_CACHE if ref($MYSQL_CONFIG_CACHE) eq "HASH";

	my $json = JSON::PP->new();

	my $content;
	open(my $fh, '<', "eqemu_config.json") or die "cannot open eqemu_config.json";
	{
		local $/;
		$content = <$fh>;
	}
	close($fh);

	$MYSQL_CONFIG_CACHE = $json->decode($content);
	return $MYSQL_CONFIG_CACHE;
}

sub _EnsureMysqlConnectionDetails {
	my $config = _LoadMysqlConfigCached();
	my $db = $config->{"server"}{"database"}{"db"};
	my $host = $config->{"server"}{"database"}{"host"};
	$MYSQL_USER_CACHE = $config->{"server"}{"database"}{"username"};
	$MYSQL_PASS_CACHE = $config->{"server"}{"database"}{"password"};
	$MYSQL_DSN_CACHE = "dbi:mysql:$db:$host:3306";
	return 1;
}

sub LoadMysql {
	use DBI;
	use DBD::mysql;

	if($MYSQL_DBH_CACHE) {
		my $alive = eval { $MYSQL_DBH_CACHE->ping() ? 1 : 0; };
		if($alive) {
			return $MYSQL_DBH_CACHE;
		}
		$MYSQL_DBH_CACHE = undef;
	}

	_EnsureMysqlConnectionDetails();
	$MYSQL_DBH_CACHE = DBI->connect(
		$MYSQL_DSN_CACHE,
		$MYSQL_USER_CACHE,
		$MYSQL_PASS_CACHE,
		{
			RaiseError => 0,
			PrintError => 0,
			AutoCommit => 1,
			mysql_auto_reconnect => 1
		}
	);

	return $MYSQL_DBH_CACHE;
}
