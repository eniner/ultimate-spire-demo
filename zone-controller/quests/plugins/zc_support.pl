# Minimal helpers the Zone Controller script calls.
# Skip this file if you already have Ultimate plugins:
#   client_messages.pl (Whisper), formation_tools.pl (Debug),
#   talent_state_tools.pl (TSS*), check_handin.pl (return_items).

sub Whisper {
	my $client = plugin::val('$client');
	my $npc = plugin::val('$npc');
	return if !$client;
	my $name = $npc ? $npc->GetCleanName() : "zone_controller";
	$client->Message(315, "$name whispers, '" . ($_[0] // "") . "'");
}

sub Debug {
	my $client = plugin::val('$client');
	return if !$client;
	$client->Message($_[1] || 326, "[ZC] " . ($_[0] // ""));
}

sub return_items {
	return 1;
}

sub _zc_data_get {
	return "" if !defined(&quest::get_data);
	my $v = quest::get_data($_[0] // "");
	return defined($v) ? $v : "";
}

sub _zc_data_set {
	my ($key, $value, $ttl) = @_;
	return 0 if !defined(&quest::set_data) || !defined($key) || $key eq "";
	$value = "" if !defined($value);
	$ttl = 0 if !defined($ttl);
	if ($ttl && $ttl > 0) {
		quest::set_data($key, $value, $ttl);
	} else {
		quest::set_data($key, $value);
	}
	return 1;
}

sub _zc_data_del {
	return 0 if !defined(&quest::delete_data);
	quest::delete_data($_[0] // "");
	return 1;
}

sub _zc_is_client {
	my $c = $_[0];
	return 0 if !$c || !ref($c);
	return eval { $c->CharacterID(); 1; } ? 1 : 0;
}

sub _zc_client_key {
	my ($client, $suffix) = @_;
	$suffix = "" if !defined($suffix);
	$suffix = "_" . $suffix if $suffix ne "" && substr($suffix, 0, 1) ne "_";
	my $id = 0;
	eval { $id = $client->CharacterID(); };
	return "zc_tss_" . $id . $suffix;
}

sub TSSGet {
	my ($client, $suffix, $default) = @_;
	$default = "" if !defined($default);
	return $default if !_zc_is_client($client);
	my $v = _zc_data_get(_zc_client_key($client, $suffix));
	return $v eq "" ? $default : $v;
}

sub TSSSet {
	my ($client, $suffix, $value, $ttl) = @_;
	return 0 if !_zc_is_client($client);
	return _zc_data_set(_zc_client_key($client, $suffix), $value, $ttl);
}

sub TSSDel {
	my ($client, $suffix) = @_;
	return 0 if !_zc_is_client($client);
	return _zc_data_del(_zc_client_key($client, $suffix));
}

sub TSSGetRaw {
	if (_zc_is_client($_[0])) {
		return plugin::TSSGet($_[0], $_[1], defined($_[2]) ? $_[2] : "");
	}
	my $key = $_[0] // "";
	my $default = defined($_[1]) ? $_[1] : "";
	return $default if $key eq "";
	my $v = _zc_data_get($key);
	return $v eq "" ? $default : $v;
}

sub TSSSetRaw {
	if (_zc_is_client($_[0])) {
		return plugin::TSSSet($_[0], $_[1], $_[2], $_[3]);
	}
	return _zc_data_set($_[0], $_[1], $_[2]);
}

sub TSSDelRaw {
	if (_zc_is_client($_[0])) {
		return plugin::TSSDel($_[0], $_[1]);
	}
	return _zc_data_del($_[0]);
}

1;
