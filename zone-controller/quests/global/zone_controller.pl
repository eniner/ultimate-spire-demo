#----------------------------------------------------------------------------------------#
#---Event Handler Block: Handlers for controller NPC to automate zone scaling and loot---#
#----------------------------------------------------------------------------------------#

sub FIRSTIDX_IN_HASH_ARRAY_BY_KEY {
	my ($array_ref, $key, $value) = @_;
	return -1 if ref($array_ref) ne "ARRAY";

	for (my $idx = 0; $idx < scalar(@{$array_ref}); $idx++) {
		next if ref($array_ref->[$idx]) ne "HASH";
		if (defined($array_ref->[$idx]{$key}) && $array_ref->[$idx]{$key} eq $value) {
			return $idx;
		}
	}

	return -1;
}

my $UEQ_ZC_SPAWN_SIGNAL_BASE = 1000000;
my $UEQ_ZC_STATE_KEY = "UEQ_ZC_STATE";
my $UEQ_ZC_RECONCILE_TIMER_1 = "ueq_zc_reconcile_boot_1";
my $UEQ_ZC_RECONCILE_TIMER_2 = "ueq_zc_reconcile_boot_2";
my $UEQ_ZC_RECONCILE_TIMER_3 = "ueq_zc_reconcile_boot_30";
my $UEQ_ZC_RECONCILE_TIMER_STEADY = "ueq_zc_reconcile_steady";
my $UEQ_ZC_SPIRE_CMD_TIMER = "ueq_zc_spire_cmd";
my $UEQ_ZC_RECONCILE_STEADY_ACTIVE_SEC = 1;
my $UEQ_ZC_RECONCILE_STEADY_IDLE_SEC = 30;
my $UEQ_ZC_BOOTSTRAP_TS_KEY = "UEQ_ZC_BOOTSTRAPPED_AT";
my $UEQ_ZC_BOOTSTRAP_REASON_KEY = "UEQ_ZC_BOOTSTRAP_REASON";
my %UEQ_ZC_DIAG = ();

sub _ueq_zc_is_spawn_signal {
	my $signal = $_[0];
	return 0 if !defined($signal) || $signal !~ /^-?\d+$/;
	return int($signal) >= $UEQ_ZC_SPAWN_SIGNAL_BASE ? 1 : 0;
}

sub _ueq_zc_spawn_id_from_signal {
	my $signal = $_[0];
	return int($signal) - $UEQ_ZC_SPAWN_SIGNAL_BASE;
}

sub _ueq_zc_mark_mob_state {
	my ($mob, $state) = @_;
	return if !$mob;
	$state = "" if !defined($state);
	$mob->SetEntityVariable($UEQ_ZC_STATE_KEY, $state);
}

sub _ueq_zc_number_or_undef {
	my $value = $_[0];
	return undef if !defined($value);
	return undef if $value eq "-1";
	return undef if $value !~ /^-?\d+(?:\.\d+)?$/;
	return $value + 0;
}

sub _ueq_zc_debug_value {
	my $value = $_[0];
	return defined($value) ? $value : "undef";
}

sub _ueq_zc_diag_reset {
	%UEQ_ZC_DIAG = (
		signals_received => 0,
		reconcile_runs => 0,
		reconcile_candidates => 0,
		reconcile_reconciled => 0,
		reconcile_terminal_skips => 0,
		timeout_seen => 0,
		bootstrap_30_runs => 0,
		bootstrap_30_forced_runs => 0,
		steady_runs => 0,
		stale_buffed_state_seen => 0,
		apply_attempts => 0,
		apply_ok => 0,
		verify_fail => 0,
		ignored => 0,
		depop => 0,
		already_buffed_skip => 0,
		filtered_skip => 0,
		missing_target => 0
	);
}

sub _ueq_zc_diag_inc {
	my $key = $_[0];
	$UEQ_ZC_DIAG{$key} = 0 if !defined($UEQ_ZC_DIAG{$key});
	$UEQ_ZC_DIAG{$key} = $UEQ_ZC_DIAG{$key} + 1;
}

sub _ueq_zc_diag_add {
	my $key = $_[0];
	my $amount = $_[1];
	$amount = 0 if !defined($amount) || $amount !~ /^-?\d+$/;
	$UEQ_ZC_DIAG{$key} = 0 if !defined($UEQ_ZC_DIAG{$key});
	$UEQ_ZC_DIAG{$key} = $UEQ_ZC_DIAG{$key} + $amount;
}

sub _ueq_zc_has_bootstrap {
	return 0 if !$npc;
	return 0 if !$npc->EntityVariableExists($UEQ_ZC_BOOTSTRAP_TS_KEY);

	my $ts = $npc->GetEntityVariable($UEQ_ZC_BOOTSTRAP_TS_KEY);
	return 0 if !defined($ts) || $ts !~ /^\d+$/ || int($ts) <= 0;
	return 1;
}

sub _ueq_zc_bootstrap_runtime {
	my $reason = $_[0];
	$reason = "unknown" if !defined($reason) || $reason eq "";

	INITIALIZE_DATA();
	_ueq_zc_diag_reset();

	$npc->SetEntityVariable("Is_Doing_Initial_Fast_Zone_Buff", 0);
	$npc->SetEntityVariable($UEQ_ZC_BOOTSTRAP_TS_KEY, time());
	$npc->SetEntityVariable($UEQ_ZC_BOOTSTRAP_REASON_KEY, $reason);

	quest::stoptimer($UEQ_ZC_RECONCILE_TIMER_1);
	quest::stoptimer($UEQ_ZC_RECONCILE_TIMER_2);
	quest::stoptimer($UEQ_ZC_RECONCILE_TIMER_3);
	quest::stoptimer($UEQ_ZC_RECONCILE_TIMER_STEADY);
	quest::stoptimer($UEQ_ZC_SPIRE_CMD_TIMER);
	quest::stoptimer("trigger_initial_fast_zone_buff");

	quest::settimer($UEQ_ZC_RECONCILE_TIMER_1, 1);
	quest::settimer($UEQ_ZC_RECONCILE_TIMER_2, 5);
	quest::settimer($UEQ_ZC_RECONCILE_TIMER_3, 30);
	quest::settimer($UEQ_ZC_RECONCILE_TIMER_STEADY, $UEQ_ZC_RECONCILE_STEADY_ACTIVE_SEC);
	quest::settimer($UEQ_ZC_SPIRE_CMD_TIMER, 2);
}

sub PRINT_ZC_DIAG {
	_ueq_zc_diag_reset() if !defined($UEQ_ZC_DIAG{signals_received});
	my $boot_ts = $npc->GetEntityVariable($UEQ_ZC_BOOTSTRAP_TS_KEY);
	$boot_ts = 0 if !defined($boot_ts) || $boot_ts !~ /^\d+$/;
	my $boot_reason = $npc->GetEntityVariable($UEQ_ZC_BOOTSTRAP_REASON_KEY);
	$boot_reason = "unknown" if !defined($boot_reason) || $boot_reason eq "";
	PRINT_DETAIL_HEADER("Debug", "Zone Controller Runtime");
	plugin::Whisper("Zone [" . $zoneid . "] instance [" . $instanceid . "]");
	plugin::Whisper("Bootstrap state: " . ($boot_ts > 0 ? "ready" : "missing") . " (reason: " . $boot_reason . ")");
	plugin::Whisper("Signals received: " . $UEQ_ZC_DIAG{signals_received});
	plugin::Whisper("Reconcile runs: " . $UEQ_ZC_DIAG{reconcile_runs} . " (boot30 runs: " . $UEQ_ZC_DIAG{bootstrap_30_runs} . ", boot30 forced: " . $UEQ_ZC_DIAG{bootstrap_30_forced_runs} . ")");
	plugin::Whisper("Reconcile candidates: " . $UEQ_ZC_DIAG{reconcile_candidates} . ", reconciled: " . $UEQ_ZC_DIAG{reconcile_reconciled} . ", terminal skipped: " . $UEQ_ZC_DIAG{reconcile_terminal_skips});
	plugin::Whisper("Steady reconcile runs: " . $UEQ_ZC_DIAG{steady_runs} . ", stale buffed state seen: " . $UEQ_ZC_DIAG{stale_buffed_state_seen});
	plugin::Whisper("Timeout seen (recoverable): " . $UEQ_ZC_DIAG{timeout_seen});
	plugin::Whisper("Apply attempts: " . $UEQ_ZC_DIAG{apply_attempts} . ", success: " . $UEQ_ZC_DIAG{apply_ok} . ", verify_fail: " . $UEQ_ZC_DIAG{verify_fail});
	plugin::Whisper("Ignored: " . $UEQ_ZC_DIAG{ignored} . ", depop: " . $UEQ_ZC_DIAG{depop} . ", already_buffed_skip: " . $UEQ_ZC_DIAG{already_buffed_skip});
	plugin::Whisper("Filtered skip: " . $UEQ_ZC_DIAG{filtered_skip} . ", missing target: " . $UEQ_ZC_DIAG{missing_target});
	plugin::Whisper("[" . quest::saylink("viewzcdiag", 1, "Refresh This View") . "] [" . quest::saylink("viewquickactions", 1, "View Quick Actions") . "]");
}

sub _ueq_zc_verify_mob_buffs {
	my $mob = $_[0];
	return (0, "missing_mob", undef, undef, undef, undef) if !$mob;

	my $mobName = $mob->GetCleanName();
	my $mobType = GET_MOB_TYPE($mobName);
	my %buffHash = GET_BUFF_HASH($mobType, $mobName);

	my $expectedLevel = _ueq_zc_number_or_undef($buffHash{level});
	my $expectedMaxHP = _ueq_zc_number_or_undef($buffHash{max_hp});
	my $actualLevel = $mob->GetLevel();
	my $actualMaxHP = $mob->GetMaxHP();

	my $levelOK = 1;
	if(defined($expectedLevel)) {
		$levelOK = (defined($actualLevel) && int($actualLevel) >= int($expectedLevel)) ? 1 : 0;
	}

	my $maxHPOK = 1;
	if(defined($expectedMaxHP)) {
		$maxHPOK = (defined($actualMaxHP) && int($actualMaxHP) >= int($expectedMaxHP)) ? 1 : 0;
	}

	my $isOK = ($levelOK && $maxHPOK) ? 1 : 0;
	my $reason = "ok";
	if(!$isOK) {
		if(!$levelOK && !$maxHPOK) {
			$reason = "level_and_max_hp_mismatch";
		} elsif(!$levelOK) {
			$reason = "level_mismatch";
		} else {
			$reason = "max_hp_mismatch";
		}
	}

	return ($isOK, $reason, $expectedLevel, $actualLevel, $expectedMaxHP, $actualMaxHP);
}

sub _ueq_zc_reconcile_unbuffed_spawns {
	my $reason = $_[0];
	$reason = "unknown" if !defined($reason) || $reason eq "";
	_ueq_zc_diag_inc("reconcile_runs");

	my @mobList = $entity_list->GetNPCList();
	my $reconciledCount = 0;
	my $terminalStateCount = 0;
	my $candidateCount = 0;

	foreach my $mob (@mobList) {
		next if !$mob;
		next if $mob->GetID() == $npc->GetID();
		next if !plugin::FilterSpawnTypes($mob, $zoneid);

		$candidateCount++;
		my $state = $mob->GetEntityVariable($UEQ_ZC_STATE_KEY);
		$state = "" if !defined($state);

		if($state eq "buffed") {
			my ($verifyOK) = _ueq_zc_verify_mob_buffs($mob);
			if(!$verifyOK) {
				_ueq_zc_diag_inc("stale_buffed_state_seen");
				_ueq_zc_mark_mob_state($mob, "pending");
				$state = "pending";
			}
		}

		if($state eq "timeout") {
			_ueq_zc_diag_inc("timeout_seen");
		}

		if($state eq "buffed" || $state eq "ignored" || $state eq "depop") {
			$terminalStateCount++;
			next;
		}

		TRIGGER_NEW_SPAWN_ACTIONS($mob->GetID(), 0);
		$reconciledCount++;
	}

	_ueq_zc_diag_add("reconcile_candidates", $candidateCount);
	_ueq_zc_diag_add("reconcile_reconciled", $reconciledCount);
	_ueq_zc_diag_add("reconcile_terminal_skips", $terminalStateCount);

	if($zoneid == 65) {
		plugin::Debug(
			"UEQ_ZC_RECONCILE zone=[" . $zoneid . "] instance=[" . $instanceid . "] reason=[" . $reason .
			"] candidates=[" . $candidateCount . "] reconciled=[" . $reconciledCount .
			"] terminal_skipped=[" . $terminalStateCount . "]"
		);
	}
}

sub EVENT_SPAWN {
	_ueq_zc_bootstrap_runtime("spawn");
}

sub EVENT_SIGNAL {
	if (!_ueq_zc_has_bootstrap()) {
		_ueq_zc_bootstrap_runtime("signal");
	}

	if(_ueq_zc_is_spawn_signal($signal)) {
		_ueq_zc_diag_inc("signals_received");
		my $spawnNPCID = _ueq_zc_spawn_id_from_signal($signal);
		TRIGGER_NEW_SPAWN_ACTIONS($spawnNPCID, 0);
	} elsif($signal > 19) {
		# New deterministic spawn-signal path: direct entity ID.
		my $spawnMob = $entity_list->GetNPCByID($signal);
		if($spawnMob) {
			_ueq_zc_diag_inc("signals_received");
			TRIGGER_NEW_SPAWN_ACTIONS($signal, 0);
			return;
		}
	} elsif($signal == 1) {
		INITIALIZE_DATA();
	} elsif($signal == 2) {	
		REPOP_STATIC_MOBS();
	} elsif($signal == 3) {	
		DEPOP_STATIC_MOBS();
	} elsif($signal == 4) {
		TRIGGER_FORCED_ZONEWIDE_NEW_SPAWN_ACTIONS(1);
	} elsif($signal == 5) {
		my $mobToIgnore = plugin::TSSGetRaw("Zone_Controller_Ignore_Mob");
		INSERT_IGNORE_MOB_USING_REMOTE_PROTOCOL($mobToIgnore);
	} elsif($signal == 6) {
		my $mobToDepop = plugin::TSSGetRaw("Zone_Controller_Depop_Mob");
		INSERT_DEPOP_MOB_USING_REMOTE_PROTOCOL($mobToDepop);	
	} elsif($signal == 7) {
		my $newCustomMob = plugin::TSSGetRaw("Zone_Controller_New_Custom_Mob");
		my $newCustomMobType = plugin::TSSGetRaw("Zone_Controller_New_Custom_Mob_Type");
		INSERT_CUSTOM_MOB_USING_REMOTE_PROTOCOL($newCustomMob, $newCustomMobType);
	} elsif($signal == 8) {
		my $newCustomLoot = plugin::TSSGetRaw("Zone_Controller_New_Custom_Loot_Batch");
		INSERT_CUSTOM_LOOT_USING_REMOTE_PROTOCOL($newCustomLoot);
	} elsif($signal == 9) {
		STORE_MOB_JSON();
		STORE_LOOT_JSON();
		STORE_ITEM_JSON();
		quest::gmsay("New data will be live when zone data has been refreshed. To immediately apply all changes rebuff mobs after refreshing data.", 4, 1);
	} elsif($signal == 10) {
		my $mobNameToUpdate = plugin::TSSGetRaw("Zone_Controller_New_Respawn_Timer_Mob_Name");
		my $mobIDToUpdate = plugin::TSSGetRaw("Zone_Controller_New_Respawn_Timer_Mob_ID");
		my $mobToUpdateTimer = plugin::TSSGetRaw("Zone_Controller_New_Respawn_Timer_Time");
		use Scalar::Util qw(looks_like_number);

		if($mobNameToUpdate ne "" && $mobToUpdateTimer ne "") {
			if(looks_like_number($mobToUpdateTimer) && $mobToUpdateTimer =~ /^\d+$/) {
				my $updateIndicator = plugin::UpdateNPCSpawnGroupRespawnTimer($mobIDToUpdate, $mobToUpdateTimer, $zonesn);

				if($updateIndicator) {
					quest::gmsay("Mob [" . $mobNameToUpdate . "] with ID [" . $mobIDToUpdate . "] had its respawn timer set to [" . $mobToUpdateTimer . "] seconds in zone [" . $zonesn . "].", 4, 1);
				} else {
					quest::gmsay("Mob [" . $mobNameToUpdate . "] with ID [" . $mobIDToUpdate . "] failed to have its respawn timer set to [" . $mobToUpdateTimer . "] seconds in zone [" . $zonesn . "]! Check DB error for more details.", 5, 1);
				}
			} else {
				quest::gmsay("Update Error [" . $zoneid . "] - You must provide a respawn timer in the form of an integer!", 5, 1);
			}
		} else {
    		quest::gmsay("Update Error [" . $zoneid . "] - You must provide a respawn timer and have a mob targeted!", 5, 1);
    	}

		plugin::TSSDelRaw("Zone_Controller_New_Respawn_Timer_Mob_Name");
		plugin::TSSDelRaw("Zone_Controller_New_Respawn_Timer_Mob_ID");
		plugin::TSSDelRaw("Zone_Controller_New_Respawn_Timer_Time");
	} elsif($signal == 11) {
		my $mobNameToUpdate = plugin::TSSGetRaw("Zone_Controller_New_Respawn_Timer_Mob_Name");
		my $mobToUpdateTimer = plugin::TSSGetRaw("Zone_Controller_New_Respawn_Timer_Time");
		my $mobIDToUpdate;
		use Scalar::Util qw(looks_like_number);

		if($mobNameToUpdate ne "" && $mobToUpdateTimer ne "") {
			if(looks_like_number($mobToUpdateTimer) && $mobToUpdateTimer =~ /^\d+$/) {
				my @nlist = $entity_list->GetNPCList();

		    	foreach my $n (@nlist) {
		    		if($n->GetCleanName() eq $mobNameToUpdate) {
		    			$mobIDToUpdate = $n->GetNPCTypeID();
		    			my $updateIndicator = plugin::UpdateNPCSpawnGroupRespawnTimer($mobIDToUpdate, $mobToUpdateTimer, $zonesn);

		    			if($updateIndicator) {
							quest::gmsay("Mob [" . $mobNameToUpdate . "] with ID [" . $mobIDToUpdate . "] had its respawn timer set to [" . $mobToUpdateTimer . "] seconds in zone [" . $zonesn . "].", 4, 1);
						} else {
							quest::gmsay("Mob [" . $mobNameToUpdate . "] with ID [" . $mobIDToUpdate . "] failed to have its respawn timer set to [" . $mobToUpdateTimer . "] seconds in zone [" . $zonesn . "]! Check DB error for more details.", 5, 1);
						}
		    		}
		    	}
	    	} else {
	    		quest::gmsay("Update Error [" . $zoneid . "] - You must provide a respawn timer in the form of an integer!", 5, 1);
	    	}
    	} else {
    		quest::gmsay("Update Error [" . $zoneid . "] - You must provide a respawn timer and have a mob targeted!", 5, 1);
    	}

		plugin::TSSDelRaw("Zone_Controller_New_Respawn_Timer_Mob_Name");
		plugin::TSSDelRaw("Zone_Controller_New_Respawn_Timer_Mob_ID");
		plugin::TSSDelRaw("Zone_Controller_New_Respawn_Timer_Time");
	} elsif($signal == 12) {
		if($npc->GetBodyType() == 1 && $npc->GetRace() == 1) {
			$npc->SetBodyType(68, 1);
			$npc->SetRace(127);
			quest::gmsay("Toggled invisible.", 4, 1);
		} else {
			$npc->SetBodyType(1, 1);
			$npc->SetRace(1);
			quest::gmsay("Toggled visible.", 4, 1);
		}
	} elsif($signal == 13) {
		if(CHECK_FOR_RELOADQUEST_STOP_CONDITION()) {
			TRIGGER_FORCED_ZONEWIDE_NEW_SPAWN_ACTIONS(1);
		}
		PRINT_ALL_LOOT_DROPS_AS_PAGED_LIST_PUBLIC(0);
	} elsif($signal == 14) {
		my $newCustomTable = plugin::TSSGetRaw("Zone_Controller_New_Custom_Table_Batch");
		INSERT_CUSTOM_TABLE_USING_REMOTE_PROTOCOL($newCustomTable);
	} elsif($signal == 15) {
		my $newCustomBatchData = plugin::TSSGetRaw("Zone_Controller_New_Custom_Loot_Association_Batch");
		ASSOCIATE_EXISTING_ITEMS_WITH_EXISTING_TABLES_USING_REMOTE_PROTOCOL($newCustomBatchData);	
	} elsif($signal == 16) {
		REPOP_STATIC_MOBS();
	} elsif($signal == 17) {
		if(CHECK_FOR_RELOADQUEST_STOP_CONDITION()) {
			TRIGGER_FORCED_ZONEWIDE_NEW_SPAWN_ACTIONS(1);
		}
		#PRINT_ALL_LOOT_DROPS_AS_PAGED_LIST_PRIVATE(0);
	} elsif($signal == 19) {
		if(CHECK_FOR_RELOADQUEST_STOP_CONDITION()) {
			TRIGGER_FORCED_ZONEWIDE_NEW_SPAWN_ACTIONS(1);
		}
		PRINT_ALL_MOBS_WITH_LOOT_TABLE_PUBLIC();
	} elsif($signal == 910101) {
		my $forward_text = $npc->GetEntityVariable("UEQ_ZC_FORWARD_TEXT");
		my $forward_client_name = $npc->GetEntityVariable("UEQ_ZC_FORWARD_CLIENT");
		$forward_text = "" if !defined($forward_text);
		$forward_client_name = "" if !defined($forward_client_name);
		$forward_text =~ s/^\s+|\s+$//g;

		if($forward_text ne "") {
			my $forward_client = $entity_list->GetClientByName($forward_client_name);
			if($forward_client) {
				local $client = $forward_client;
				local $text = $forward_text;
				EVENT_SAY();
			} else {
				quest::gmsay("Zone Controller forward failed: client [" . $forward_client_name . "] not found for command [" . $forward_text . "].", 5, 1);
			}
		}
	} else {
		TRIGGER_NEW_SPAWN_ACTIONS($signal, 0);
	}
}

sub EVENT_TIMER {
	if (!_ueq_zc_has_bootstrap()) {
		_ueq_zc_bootstrap_runtime("timer");
		return;
	}

	if ($timer eq $UEQ_ZC_RECONCILE_TIMER_1) {
		_ueq_zc_reconcile_unbuffed_spawns("boot_1s");
		quest::stoptimer($UEQ_ZC_RECONCILE_TIMER_1);
	} elsif ($timer eq $UEQ_ZC_RECONCILE_TIMER_2) {
		_ueq_zc_reconcile_unbuffed_spawns("boot_5s");
		quest::stoptimer($UEQ_ZC_RECONCILE_TIMER_2);
	} elsif ($timer eq $UEQ_ZC_RECONCILE_TIMER_3) {
		_ueq_zc_diag_inc("bootstrap_30_runs");
		_ueq_zc_diag_inc("bootstrap_30_forced_runs");
		TRIGGER_FORCED_ZONEWIDE_NEW_SPAWN_ACTIONS(0, 0);
		quest::stoptimer($UEQ_ZC_RECONCILE_TIMER_3);
	} elsif ($timer eq $UEQ_ZC_RECONCILE_TIMER_STEADY) {
		_ueq_zc_diag_inc("steady_runs");
		_ueq_zc_reconcile_unbuffed_spawns("steady");
		PROCESS_SPIRE_COMMANDS();
		quest::settimer($UEQ_ZC_SPIRE_CMD_TIMER, 2);
		my @client_list = $entity_list->GetClientList();
		my $next_interval = (scalar(@client_list) > 0)
			? $UEQ_ZC_RECONCILE_STEADY_ACTIVE_SEC
			: $UEQ_ZC_RECONCILE_STEADY_IDLE_SEC;
		quest::settimer($UEQ_ZC_RECONCILE_TIMER_STEADY, $next_interval);
	} elsif ($timer eq $UEQ_ZC_SPIRE_CMD_TIMER) {
		PROCESS_SPIRE_COMMANDS();
		quest::settimer($UEQ_ZC_SPIRE_CMD_TIMER, 2);
	} elsif ($timer eq "trigger_initial_fast_zone_buff") {
		quest::stoptimer("trigger_initial_fast_zone_buff");
	}
}

sub _ueq_zc_spire_cmd_path {
	my $zone_id = $_[0];
	my $dir = "";
	eval {
		$dir = plugin::_instance_tools_ultimatedata_root();
		1;
	};
	$dir = "quests/global/ultimatedata" if !defined($dir) || $dir eq "";
	$dir =~ s!\\!/!g;
	$dir =~ s!/+$!!;
	return $dir . "/_spire_commands/" . $zone_id . ".json";
}

sub PROCESS_SPIRE_COMMANDS {
	return if !defined($zoneid);
	my $path = _ueq_zc_spire_cmd_path($zoneid);
	return if !-f $path;

	my $taken = $path . ".taken";
	return if !rename($path, $taken);

	open(my $fh, "<", $taken) or return;
	local $/;
	my $raw = <$fh>;
	close $fh;
	unlink $taken;

	require JSON::PP;
	my $data = eval { JSON::PP->new->allow_nonref->decode($raw) };
	return if !$data || ref($data) ne "HASH" || ref($data->{commands}) ne "ARRAY";

	my @ran = ();
	my @errors = ();
	foreach my $cmd (@{$data->{commands}}) {
		$cmd = "" if !defined($cmd);
		$cmd = lc($cmd);
		$cmd =~ s/^\s+|\s+$//g;
		next if $cmd eq "";

		my $ok = eval {
			if ($cmd eq "refreshzonedata" || $cmd eq "initdata") {
				INITIALIZE_DATA();
			} elsif ($cmd eq "repopallstaticbosses" || $cmd eq "repop") {
				REPOP_STATIC_MOBS();
			} elsif ($cmd eq "depopallstaticbosses" || $cmd eq "depop") {
				DEPOP_STATIC_MOBS();
			} elsif ($cmd eq "rebuffzone" || $cmd eq "reloadzone" || $cmd eq "resetallchanges") {
				TRIGGER_FORCED_ZONEWIDE_NEW_SPAWN_ACTIONS(1);
			} elsif ($cmd eq "applyallchanges") {
				TRIGGER_FORCED_ZONEWIDE_NEW_SPAWN_ACTIONS(0);
			} elsif ($cmd eq "saveallchanges") {
				STORE_MOB_JSON();
				STORE_LOOT_JSON();
				STORE_ITEM_JSON();
			} else {
				die "unknown command";
			}
			1;
		};
		if ($ok) {
			push @ran, $cmd;
		} else {
			my $err = $@;
			$err =~ s/\s+$//;
			push @errors, $cmd . ": " . $err;
		}
	}

	my $result_path = $path;
	$result_path =~ s/\.json$/.result.json/;
	my $result = {
		id => $data->{id},
		zoneId => $zoneid + 0,
		ran => \@ran,
		errors => \@errors,
		at => time()
	};
	if (open(my $out, ">", $result_path)) {
		print $out JSON::PP->new->canonical->encode($result);
		close $out;
	}
	if (scalar(@ran) > 0) {
		quest::gmsay("Spire applied [" . join(", ", @ran) . "] in zone [" . $zoneid . "].", 4, 1);
	}
}

sub EVENT_SAY {
	if (!_ueq_zc_has_bootstrap()) {
		_ueq_zc_bootstrap_runtime("say");
	}

	# GM command mode:
	# - Supports direct prefixes without hailing the NPC:
	#   !zc <token>
	#   #zc <token>
	# - Keeps backward compatibility for raw #token emits from GMConsole.
	if(defined $text) {
		$text =~ s/^\s*(?:!|#)\s*zc\s+//i;
		$text =~ s/^\s*#\s*//;
	}

	if($client->GetGM() == 1) {
		if ($text =~/Hail/i || $text =~/viewquickactions/i || $text =~/zchelp/i || $text =~/helpzc/i) {
			PRINT_HEADER();
			plugin::Whisper("Direct command mode: use !zc <command> or #zc <command> (example: !zc viewallmobs)");
		} elsif($text =~/viewzcdiag/i || $text =~/zcdiag/i) {
			PRINT_ZC_DIAG();
		} elsif($text =~/viewremotecommands/i) {
			PRINT_REMOTE_COMMANDS();
		} elsif($text =~/viewallmobs/i) {
			PRINT_MOB_LIST();
		} elsif($text =~/viewignoredmobs/i) {
			PRINT_IGNORED_MOB_LIST();
		} elsif($text =~/viewdepopmobs/i) {
			PRINT_DEPOP_MOB_LIST();
		} elsif($text =~/removemob_/i) {
			REMOVE_MOB($text);
		} elsif($text =~/renamemob#/i) {
			UPDATE_MOB_NAME($text, 0);
		} elsif($text =~/!whispermobname#/i) {
			UPDATE_MOB_NAME($text, 1);
		} elsif($text =~/clonemob#/i) {
			CLONE_MOB($text, 0);
		} elsif($text =~/!whisperclonename#/i) {
			CLONE_MOB($text, 1);
		} elsif($text =~/removeitembyname_/i) {
			REMOVE_ITEM_BY_NAME($text);
		} elsif($text =~/removefromignored_/i) {
			REMOVE_IGNORED_MOB($text);
		} elsif($text =~/removefromdepop_/i) {
			REMOVE_DEPOP_MOB($text);
		} elsif($text =~/addnewcustommob/i) {
			PRINT_NEW_CUSTOM_MOB_TYPE_SELECTION();	
		} elsif($text =~/batchaddncustommobs/i) {
			PRINT_ALL_DB_MOBS_AS_PAGED_LIST($text);	
		} elsif($text =~/dbad_/i) {
			INSERT_CUSTOM_MOB_USING_DB_BATCH_MODE($text);	
		} elsif($text =~/setnewcustommobtype#/i) {
			INSERT_CUSTOM_MOB($text, 0);
		} elsif($text =~/!addnewmob#/i) {
			INSERT_CUSTOM_MOB($text, 1);
		} elsif($text =~/addnewignoremob#/i) {
			INSERT_IGNORE_MOB($text, 0)
		} elsif($text =~/!addignoremob#/i) {
			INSERT_IGNORE_MOB($text, 1);
		} elsif($text =~/addnewdepopmob#/i) {
			INSERT_DEPOP_MOB($text, 0)
		} elsif($text =~/!adddepopmob#/i) {
			INSERT_DEPOP_MOB($text, 1);	
		} elsif($text =~/viewzoneinfo/i) {
			PRINT_ZONE_INFO();	
		} elsif($text =~/vl_/i) {
			PRINT_LOOT_TABLE($text);
		} elsif($text =~/vtd_/i) {
			PRINT_LOOT_TABLE_ITEMS_AS_PAGED_LIST($text);
		} elsif($text =~/quickadditems_/i) {
			PRINT_LOOT_TABLE_ITEMS_FOR_QUICK_TABLE_ASSOCIATION($text);	
		} elsif($text =~/viewitemdata_/i) {
			PRINT_LOOT_TABLE_ITEM_DETAILS($text);
		} elsif($text =~/vts_/i) {
			PRINT_TYPE_BUFF_HASH($text);
		} elsif($text =~/vcs_/i) {
			PRINT_CUSTOM_BUFF_HASH($text);
		} elsif($text =~/vfs_/i) {
			PRINT_BUFF_HASH($text);
	 	} elsif($text =~/viewallloottables/i) {
			PRINT_ALL_LOOT_TABLES();
		} elsif($text =~/viewallassociatedtables_/i) {
			PRINT_ALL_LOOT_TABLES_WITH_ITEM_NAME($text);
		} elsif($text =~/viewmobsbyloottable_/i) {
			PRINT_ALL_MOBS_WITH_LOOT_TABLE($text);
		} elsif($text =~/removeitemfromalltables_/i) {
			REMOVE_LOOT_TABLE_ITEM_FROM_ALL_LOOT_TABLES($text);
		} elsif($text =~/viewalllootdrops_/i) {
			PRINT_ALL_LOOT_DROPS($text);
		} elsif($text =~/repopallstaticbosses/i) {
			REPOP_STATIC_MOBS();
		} elsif($text =~/depopallstaticbosses/i) {
			DEPOP_STATIC_MOBS();
		} elsif($text =~/rebuffzone/i) {
			TRIGGER_FORCED_ZONEWIDE_NEW_SPAWN_ACTIONS(1);
		} elsif($text =~/refreshzonedata/i) {
			INITIALIZE_DATA();
		} elsif($text =~/ams#/i) {
			UPDATE_INTEGER_TYPE_BUFF($text);
		} elsif($text =~/togglemobstat#/i) {
			UPDATE_BOOLEAN_TYPE_BUFF($text);
		} elsif($text =~/saymobstat#/i) {
			UPDATE_ALPHA_TYPE_BUFF($text, 0);
		} elsif($text =~/!whispermobstat#/i) {
			UPDATE_ALPHA_TYPE_BUFF($text, 1);
		} elsif($text =~/acs#/i) {
			UPDATE_INTEGER_CUSTOM_BUFF($text);
		} elsif($text =~/rcs#/i) {
			UPDATE_INTEGER_CUSTOM_BUFF_DECREASE_BY_ONE_ONLY($text);
		} elsif($text =~/togglecustommobstat#/i) {
			UPDATE_BOOLEAN_CUSTOM_BUFF($text);
		} elsif($text =~/saycustommobstat#/i) {
			UPDATE_ALPHA_CUSTOM_BUFF($text, 0);
		} elsif($text =~/!whispercustommobstat#/i) {
			UPDATE_ALPHA_CUSTOM_BUFF($text, 1);
		} elsif($text =~/sayzoneinfo#/i) {
			UPDATE_ZONE_INFO($text, 0);
		} elsif($text =~/!whisperzoneinfo#/i) {
			UPDATE_ZONE_INFO($text, 1);
		} elsif($text =~/vco_/i) {
			PRINT_ALL_LOOT_TABLES_AVAILABLE_FOR_CUSTOM_ASSIGNMENT($text);
		} elsif($text =~/vto_/i) {
			PRINT_ALL_LOOT_TABLES_AVAILABLE_FOR_TYPE_ASSIGNMENT($text);
		} elsif($text =~/cl_/i) {
			INSERT_CUSTOM_LOOT_TABLE_REFERENCE($text);
		} elsif($text =~/atts_/i) {
			INSERT_TYPE_LOOT_TABLE_REFERENCE($text);
		} elsif($text =~/dclt_/i) {
			UPDATE_CUSTOM_LOOT_DROP_PERCENT($text, 0);
		} elsif($text =~/iclt_/i) {
			UPDATE_CUSTOM_LOOT_DROP_PERCENT($text, 1);
		} elsif($text =~/dtlt_/i) {
			UPDATE_TYPE_LOOT_DROP_PERCENT($text, 0);
		} elsif($text =~/itlt_/i) {
			UPDATE_TYPE_LOOT_DROP_PERCENT($text, 1);
		} elsif($text =~/stlt_/i) {
			UPDATE_TYPE_LOOT_DROP_PERCENT_IMPLICITLY($text);
		} elsif($text =~/sclt_/i) {
			UPDATE_CUSTOM_LOOT_DROP_PERCENT_IMPLICITLY($text);
		} elsif($text =~/saynewloottableinfo/i) {
			CREATE_NEW_LOOT_TABLE($text, 0);
		} elsif($text =~/!wnt#/i) {
			CREATE_NEW_LOOT_TABLE($text, 1);
		} elsif($text =~/displaytablesthatcanbeassociated_/i) {
			PRINT_ALL_LOOT_TABLES_WITH_NO_ASSOCIATION_TO_ITEM_NAME($text);
		} elsif($text =~/ali_/i) {
			INSERT_LOOT_TABLE_ITEM($text);	
		} elsif($text =~/assignallitemstoloottable_/i) {
			INSERT_LOOT_TABLE_ITEM_ALL($text);	
		} elsif($text =~/removeallitemsfromloottable_/i) {
			REMOVE_LOOT_TABLE_ITEM_ALL($text);
		} elsif($text =~/removeallitemsfromitemtable/i) {
			REMOVE_ITEM_ALL();	
		} elsif($text =~/addnewitemtozone/i) {
			INSERT_ITEM($text, 0);	
		} elsif($text =~/!additemid#/i) {
			INSERT_ITEM($text, 1);
		} elsif($text =~/sayitemdetails#/i) {
			UPDATE_ITEM_DETAILS($text, 0);
		} elsif($text =~/!updateitemdetails#/i) {
			UPDATE_ITEM_DETAILS($text, 1);			
		} elsif($text =~/removeitemdata_/i) {
			REMOVE_LOOT_TABLE_ITEM($text);
		} elsif($text =~/rlt_/i) {
			REMOVE_TYPE_LOOT_TABLE_REFERENCE($text);
		} elsif($text =~/rct_/i) {
			REMOVE_CUSTOM_LOOT_TABLE_REFERENCE($text);
		} elsif($text =~/removeloottable_/i) {
			REMOVE_LOOT_TABLE($text);
		} elsif($text =~/saveallchanges/i) {
			DO_SAVE_CONFIRMATION();
		} elsif($text =~/applyallchanges/i) {
			TRIGGER_FORCED_ZONEWIDE_NEW_SPAWN_ACTIONS(0);
		} elsif($text =~/resetallchanges/i) {
			TRIGGER_FORCED_ZONEWIDE_NEW_SPAWN_ACTIONS(1);
		}
	} else {
		plugin::Whisper("I can only speak to GM's at this time!");
	}
}

sub EVENT_POPUPRESPONSE {
	if($popupid == 100111) {
		STORE_MOB_JSON();
		STORE_LOOT_JSON();
		STORE_ITEM_JSON();
		quest::gmsay("New data will be live when zone data has been refreshed. To immediately apply all changes rebuff mobs after refreshing data.", 4, 1);
	}
}

sub INITIALIZE_DATA {
	#Check to see if zone data exists
	if(!plugin::CheckIfJSONFilesExist($zoneid)) {
		quest::gmsay("JSON data does not exist or is not configured correctly for zone: [" . $zoneid . "]. Creating them now...", 5, 1);
		plugin::GenerateJSONFilesFromTemplate($zoneid);
	} else {
		quest::gmsay("Successfully located JSON files for zone: [" . $zoneid . "].", 4, 1);
	}

	#Decode JSON data
	$zoneData = plugin::GetSpawnDataHash($zoneid);
	$lootData = plugin::GetLootDataHash($zoneid);
	$itemData = plugin::GetItemDataHash($zoneid);

	#Check for template artifacts
	if((keys %{$zoneData})[0] eq "TEMPZONEID") {
		$zoneData->{$zoneid} = delete $zoneData->{TEMPZONEID};
		quest::gmsay("Template JSON artifacts found in mob data JSON - they were updated. You should save all data files immediately and reload zone data.", 5, 1);
	}

	if((keys %{$lootData})[0] eq "TEMPZONEID") {
		$lootData->{$zoneid} = delete $lootData->{TEMPZONEID};
		quest::gmsay("Template JSON artifacts found in loot data JSON - they were updated. You should save all data files immediately and reload zone data.", 5, 1);
	}

	if((keys %{$itemData})[0] eq "TEMPZONEID") {
		$itemData->{$zoneid} = delete $itemData->{TEMPZONEID};
		quest::gmsay("Template JSON artifacts found in item data JSON - they were updated. You should save all data files immediately and reload zone data.", 5, 1);
	}

	#Get common mob groups for quick reference
	@depopArray = GET_DEPOP_ARRAY();
	@ignoreArray = GET_IGNORE_ARRAY();
	@staticNamedMobArray = GET_STATIC_NAMED_MOB_ARRAY();
	@namedMobArray = GET_NAMED_MOB_ARRAY();	
	@customMobArray = GET_CUSTOM_MOB_ARRAY();
	@dbMobArray = plugin::GetAllNPCNamesForZone($zoneid);

	quest::gmsay("Zone data has been initialized: [" . $zoneid . "]", 4, 1);
}

sub CHECK_FOR_RELOADQUEST_STOP_CONDITION {
	if($zoneData->{$zoneid}{basedata}{raid} == '') {
		quest::gmsay("Reloadquest condition detected, force reloading all zone data.", 5, 1);
		return 1;
	} else {
		return 0;
	}
}

sub TRIGGER_INITIAL_ZONE_LOAD_FAST_BUFF_START {
	$npc->SetEntityVariable("Is_Doing_Initial_Fast_Zone_Buff", 1);
}

sub TRIGGER_INITIAL_ZONE_LOAD_FAST_BUFF_END {
	$npc->SetEntityVariable("Is_Doing_Initial_Fast_Zone_Buff", 0);
}

sub TRIGGER_NEW_SPAWN_ACTIONS {
	my $signal = $_[0];
	my $forceApply = defined($_[1]) ? $_[1] : 0;
	my $mob = $entity_list->GetNPCByID($signal);
	if(!$mob) {
		_ueq_zc_diag_inc("missing_target");
		return;
	}
	if(!plugin::FilterSpawnTypes($mob, $zoneid)) {
		_ueq_zc_diag_inc("filtered_skip");
		return;
	}
	_ueq_zc_diag_inc("apply_attempts");

	my $currentState = $mob->GetEntityVariable($UEQ_ZC_STATE_KEY);
	$currentState = "" if !defined($currentState);
	if(!$forceApply && $currentState eq "buffed") {
		_ueq_zc_diag_inc("already_buffed_skip");
		return;
	}

	if(IS_DEPOP_MOB($mob)) {
		_ueq_zc_diag_inc("depop");
		_ueq_zc_mark_mob_state($mob, "depop");
		return;
	}

	if(IS_IGNORE_MOB($mob)) {
		_ueq_zc_diag_inc("ignored");
		_ueq_zc_mark_mob_state($mob, "ignored");
		return;
	}

	SET_MOB_BUFFS($mob);
	my ($verifyOK, $verifyReason, $expectedLevel, $actualLevel, $expectedMaxHP, $actualMaxHP) = _ueq_zc_verify_mob_buffs($mob);
	if(!$verifyOK) {
		_ueq_zc_diag_inc("verify_fail");
		_ueq_zc_mark_mob_state($mob, "pending");
		if($zoneid == 65) {
			plugin::Debug(
				"UEQ_ZC_VERIFY_FAIL zone=[" . $zoneid . "] instance=[" . $instanceid . "] npc_id=[" . $mob->GetID() .
				"] npc=[" . $mob->GetCleanName() . "] reason=[" . $verifyReason . "] expected_level=[" .
				_ueq_zc_debug_value($expectedLevel) . "] actual_level=[" . _ueq_zc_debug_value($actualLevel) .
				"] expected_max_hp=[" . _ueq_zc_debug_value($expectedMaxHP) . "] actual_max_hp=[" .
				_ueq_zc_debug_value($actualMaxHP) . "]"
			);
		}
		return;
	}

	SET_MOB_LOOT($mob);
	_ueq_zc_diag_inc("apply_ok");
	_ueq_zc_mark_mob_state($mob, "buffed");
}

sub TRIGGER_FORCED_ZONEWIDE_NEW_SPAWN_ACTIONS {
	my $initializeDataFlag = $_[0];
	my $announce = defined($_[1]) ? $_[1] : 1;
	my @mobList = $entity_list->GetNPCList();

	if($initializeDataFlag) { 
    	INITIALIZE_DATA();
    }

	    foreach my $mob (@mobList) {
	    	if($mob->GetID() != $npc->GetID()){
		    	if(plugin::FilterSpawnTypes($mob, $zoneid)) {
		    		TRIGGER_NEW_SPAWN_ACTIONS($mob->GetID(), 1);
		    	}
		    }
	    }

	if($announce) {
		quest::gmsay("All mobs have been rebuffed and had loot reassigned: [" . $zoneid . "]", 4, 1);
	}
}


#------------------------------------------------------------------------------#
#---Hash Access Block: Get hash data to dynamically update or reference mobs---#
#------------------------------------------------------------------------------#

sub SET_MOB_BUFFS {
	my $mob = $_[0];
	my $mobName = $mob->GetCleanName();
	my $mobType = GET_MOB_TYPE($mobName);
	my %buffHash = GET_BUFF_HASH($mobType, $mobName);
	#plugin::Debug($mobName);

	foreach my $key (keys %buffHash) {
		if($key ne "loot" && $buffHash{$key} ne "-1") {
			#plugin::Debug($mobName . ": " . $key . "->" . $buffHash{$key}); #print all mob buffs
			if($key eq "level") {
				$mob->SetLevel($buffHash{$key});
			} elsif($key eq "cash") {
				$mob->AddCash(0,0,0,int($buffHash{$key}));
			} elsif($key eq "size" && $buffHash{$key} ne "-1" && $buffHash{$key} ne "0") {
				$mob->ChangeSize($buffHash{$key});
			} else {
				$mob->ModifyNPCStat($key, $buffHash{$key});
			}
		}
	}

	$mob->Heal();
}

sub SET_MOB_LOOT {
	my $mob = $_[0];
	my $mobName = $mob->GetCleanName();
	my $mobType = GET_MOB_TYPE($mobName);
	my %lootDropHash = GET_MOB_LOOT_HASH($mobType, $mobName);
	my $randomRoll;
	my $percentTracker;

	$mob->ClearItemList();

	foreach $key (keys %lootDropHash) {
		if($lootDropHash{$key} > 100) {
			while ($lootDropHash{$key} > 0) {
				$randomRoll = plugin::GetRandomLootRoll(1, 100);
				
				if($randomRoll <= $lootDropHash{$key}) {
					$mob->AddItem(GET_RANDOM_LOOT_TABLE_ITEM_ITEM_ID($key), 1, 0);
				}

				$lootDropHash{$key} = $lootDropHash{$key} - 100;
			}
		} else {
			$randomRoll = plugin::GetRandomLootRoll(1, 100);

			if($randomRoll <= $lootDropHash{$key}) {
				$mob->AddItem(GET_RANDOM_LOOT_TABLE_ITEM_ITEM_ID($key), 1, 0);
			}
		}
	}
}

sub GET_LOOT_HASH {
	my %lootHash = %{$lootData->{$zoneid}};
	return %lootHash;
}

sub GET_MOB_LOOT_HASH {
	my $mobType = $_[0];
	my $mobName = $_[1];
	my $customizedFlag = IS_CUSTOMIZED_MOB($mobName);
	my %lootDropHash = GET_GLOBAL_LOOT_HASH($mobType);

	if($customizedFlag) {
		my %customLootDropHash = GET_CUSTOM_LOOT_HASH($mobName);
		foreach my $key (keys %customLootDropHash) {
			$lootDropHash{$key} = $customLootDropHash{$key};
		}
	}

	return %lootDropHash;	
}

sub GET_GLOBAL_LOOT_HASH {
	my $mobType = $_[0];
	my $typeLootDropCount = GET_TYPE_LOOT_DROP_COUNT($mobType);
	my %lootDropHash;

	if($typeLootDropCount > 0) {
		for (my $i = 0; $i < $typeLootDropCount; $i++) {
	   		$lootDropHash{$zoneData->{$zoneid}{basedata}{$mobType}{loot}[$i]{id}} = $zoneData->{$zoneid}{basedata}{$mobType}{loot}[$i]{chance};
		}
	}

	return %lootDropHash;
}

sub GET_CUSTOM_LOOT_HASH {
	my $mobName = $_[0];
	my $customLootDropCount = GET_CUSTOM_LOOT_DROP_COUNT($mobName);
	my %lootDropHash;

	if($customLootDropCount > 0) {
		for (my $i = 0; $i < $customLootDropCount; $i++) {
	   		$lootDropHash{$zoneData->{$zoneid}{custom}{$mobName}{loot}[$i]{id}} = $zoneData->{$zoneid}{custom}{$mobName}{loot}[$i]{chance};
		}
	}

	return %lootDropHash;
}

sub GET_TYPE_LOOT_DROP_COUNT {
	my $mobType = $_[0];
	return @{$zoneData->{$zoneid}{basedata}{$mobType}{loot}};
}

sub GET_CUSTOM_LOOT_DROP_COUNT {
	my $mobName = $_[0];
	return @{$zoneData->{$zoneid}{custom}{$mobName}{loot}};
}

sub GET_ITEM_ID_BY_ITEM_NAME {
	my $itemName = $_[0];
	return $itemData->{$zoneid}{$itemName}{itemid};
}

sub GET_ITEM_DESCRIPTION_BY_ITEM_NAME {
	my $itemName = $_[0];
	return $itemData->{$zoneid}{$itemName}{description};
}

sub GET_ITEM_SPELLID_BY_ITEM_NAME {
	my $itemName = $_[0];
	return $itemData->{$zoneid}{$itemName}{spellid};
}

sub GET_ITEM_ISGLOBAL_BY_ITEM_NAME {
	my $itemName = $_[0];
	return $itemData->{$zoneid}{$itemName}{isglobal};
}

sub GET_ITEM_GLOBALKEY_BY_ITEM_NAME {
	my $itemName = $_[0];
	return $itemData->{$zoneid}{$itemName}{globalkey};
}

sub GET_RANDOM_LOOT_TABLE_ITEM_ITEM_ID {
	my $lootTableID = $_[0];
	my $lootTableItemCount = @{$lootData->{$zoneid}{$lootTableID}};
	my $randomizedLootTableItemIndex = plugin::GetRandomLootRoll(0, $lootTableItemCount);
	my $lootTableItemName = $lootData->{$zoneid}{$lootTableID}[$randomizedLootTableItemIndex]{name};

	return GET_ITEM_ID_BY_ITEM_NAME($lootTableItemName);
}

sub GET_LOOT_TABLE_HASH {
	my %lootTableHash = %{$lootData->{$zoneid}};
	return %lootTableHash;
}

sub GET_ALL_LOOT_TABLE_IDS {
	my %lootTableHash = GET_LOOT_TABLE_HASH();
	my @locatedLootTableIDArray = ();

	foreach my $key (keys %lootTableHash) {	
		push @locatedLootTableIDArray, $key;
	}

	return @locatedLootTableIDArray;
}

sub GET_ALL_LOOT_TABLE_ITEM_NAMES {
	my $lootTableID = $_[0];
	my %lootTableHash = GET_LOOT_TABLE_HASH();
	my @allLootTableItemNames = ();

	foreach my $key (keys %lootTableHash) {		
		if($key eq $lootTableID) {
			for (my $i = 0; $i < @{$lootTableHash{$lootTableID}}; $i++) {
				push @allLootTableItemNames, $lootTableHash{$key}[$i]{name};
			}
			last;
		}
	}

	return @allLootTableItemNames;
}

sub GET_ITEM_HASH_BY_ITEM_NAME {
	my $itemName = $_[0];
	my %itemHash;

	if(exists($itemData->{$zoneid}{$itemName})) {
		$itemHash{name} = $itemName;
		$itemHash{itemid} = GET_ITEM_ID_BY_ITEM_NAME($itemName);
		$itemHash{spellid} = GET_ITEM_SPELLID_BY_ITEM_NAME($itemName);
		$itemHash{isglobal} = GET_ITEM_ISGLOBAL_BY_ITEM_NAME($itemName);
		$itemHash{globalkey} = GET_ITEM_GLOBALKEY_BY_ITEM_NAME($itemName);
		$itemHash{description} = GET_ITEM_DESCRIPTION_BY_ITEM_NAME($itemName);
	}

	return %itemHash;	
}

sub GET_ITEM_HASH {
	my %itemHash = %{$itemData->{$zoneid}};
	return %itemHash;
}

sub GET_BUFF_HASH {
	my $mobType = $_[0];
	my $mobName = $_[1];
	my $customizedFlag = IS_CUSTOMIZED_MOB($mobName);
	my %buffHash = GET_TYPE_BUFF_HASH($mobType);

	if($customizedFlag) {
		my %customBuffHash = GET_CUSTOM_BUFF_HASH($mobName);

		foreach my $key (keys %buffHash) {
			if(exists($customBuffHash{$key . "_mod"})) {
				if($customBuffHash{$key . "_mod"} ne "-1") {
					$buffHash{$key} = $buffHash{$key} + $customBuffHash{$key . "_mod"};
				}
			} elsif(exists($customBuffHash{$key . "_override"})) {
				if($customBuffHash{$key . "_override"} ne "-1") {
					$buffHash{$key} = $customBuffHash{$key . "_override"};
				}
			}
		}
	}

	return %buffHash
}

sub GET_TYPE_BUFF_HASH {
	my $mobType = $_[0];
	my %typeBuffHash = %{$zoneData->{$zoneid}{basedata}{$mobType}};
	return %typeBuffHash;
}

sub GET_CUSTOM_BUFF_HASH {
	my $mobName = $_[0];
	my %customBuffHash = %{$zoneData->{$zoneid}{custom}{$mobName}};
	return %customBuffHash;
}

sub GET_DEPOP_ARRAY {
	my @depop = ();
	my $depopCount = @{$zoneData->{$zoneid}{depop}{all}};

	if($depopCount > 0) {
		for (my $i = 0; $i < $depopCount; $i++) {
			push @depop, $zoneData->{$zoneid}{depop}{all}[$i]{name};
		}
	}

	return @depop;
}

sub GET_IGNORE_ARRAY {
	my @ignore = ();
	my $ignoreCount = @{$zoneData->{$zoneid}{ignore}{all}};

	if($ignoreCount > 0) {
		for (my $i = 0; $i < $ignoreCount; $i++) {
			push @ignore, $zoneData->{$zoneid}{ignore}{all}[$i]{name};
		}
	}

	return @ignore;
}

sub GET_TYPE_ARRAY {
	my @types = ("trash", "boss", "raid");
	return @types;
}

sub GET_STATIC_NAMED_MOB_ARRAY {
	my @static = ();
	my %staticNamedHash = %{$zoneData->{$zoneid}{custom}};

	foreach my $key (keys %staticNamedHash) {
		if($staticNamedHash{$key}{type} eq "boss" || $staticNamedHash{$key}{type} eq "raid") {
			if($staticNamedHash{$key}{static} eq "1") {
				push @static, $staticNamedHash{$key}{mobid};
			}
		}
	}

	return @static;
}

sub GET_NAMED_MOB_ARRAY {
	my @named = ();
	my %namedHash = %{$zoneData->{$zoneid}{custom}};

	foreach my $key (keys %namedHash) {
		if($namedHash{$key}{type} eq "boss" || $namedHash{$key}{type} eq "raid") {
			push @named, $key;
		}
	}

	return @named;
}

sub GET_CUSTOM_MOB_ARRAY {
	my @custom = ();
	my %customHash = %{$zoneData->{$zoneid}{custom}};

	foreach my $key (keys %customHash) {
		push @custom, $key;
	}

	@custom = sort @custom;
	return @custom;
}

sub GET_MOB_TYPE {
	my $mobName = $_[0];
	
	if(!IS_CUSTOMIZED_MOB($mobName)) {
		return "trash";
	} else {
		return $zoneData->{$zoneid}{custom}{$mobName}{type};
	}
}

sub GET_ZONE_INFO_HASH {
	my %zoneInfoHash = %{$zoneData->{$zoneid}{info}};
	return %zoneInfoHash;
}

sub IS_IGNORE_MOB {
	my $mob = $_[0];
	my $ignoreFlag = 0;

	if($mob) {
		my $mobName = $mob->GetCleanName();

		if (grep{$_ eq $mobName} @ignoreArray) {
			$ignoreFlag = 1;
		}
	}

	return $ignoreFlag;
}

sub IS_DEPOP_MOB {
	my $mob = $_[0];
	my $depopFlag = 0;

	if($mob) {
		my $mobName = $mob->GetCleanName();

		if (grep{$_ eq $mobName} @depopArray) {
			$depopFlag = 1;
			quest::depopall($mob->GetNPCTypeID());
		}
	}

	return $depopFlag;
}

sub IS_CUSTOMIZED_MOB {
	my $mobName = $_[0];
	my $namedFlag = 0;

	if (grep{$_ eq $mobName} @customMobArray) {
		$namedFlag = 1;
	}

	return $namedFlag;
} 

sub GET_ORPHANED_LOOT_TABLE_STATUS {
	my $lootTableID = $_[0];
	my @allTypesArray = ("trash", "boss", "raid");
	my $isOrphaned = 1;

	foreach my $mobName (@customMobArray) {
		my %customBuffHash = GET_CUSTOM_BUFF_HASH($mobName);
		for (my $i = 0; $i < @{$customBuffHash{loot}}; $i++) {
			if($customBuffHash{loot}[$i]{id} eq $lootTableID) {
				$isOrphaned = 0;
				last;
			}
		}
	}

	if($isOrphaned) {
		foreach my $mobType (@allTypesArray) {
			my %typeBuffHash = GET_TYPE_BUFF_HASH($mobType);
			for (my $i = 0; $i < @{$typeBuffHash{loot}}; $i++) {
				if($typeBuffHash{loot}[$i]{id} eq $lootTableID) {
					$isOrphaned = 0;
					last;
				}
			}
		}
	}

	if($isOrphaned) {
		return "(NOT ASSIGNED!)";
	} else {
		return "";
	}
}

sub GET_LOOT_TABLE_ITEM_COUNT_STATUS {
	my $lootTableName = $_[0];
	my %lootTableHash = GET_LOOT_TABLE_HASH();
	my $counter = 0;

	for (my $i = 0; $i < @{$lootTableHash{$lootTableName}}; $i++) {
		$counter = $counter + 1;
	}

	return "(Item Count: " . $counter . ")";
}

sub REPOP_STATIC_MOBS {
	plugin::RespawnBossMobs(@staticNamedMobArray, $entity_list);
	quest::gmsay("Static custom boss and raid mobs have been repopped: [" . $zoneid . "]", 4, 1);
}

sub DEPOP_STATIC_MOBS {
	plugin::DespawnBossMobs(@staticNamedMobArray, $entity_list);
	quest::gmsay("Static custom boss and raid mobs have been depopped: [" . $zoneid ."]", 4, 1);	
}


#------------------------------------------------------------------------#
#---Hash Write Block: Write to hash data dynamically and store in json---#
#------------------------------------------------------------------------#

sub UPDATE_INTEGER_TYPE_BUFF {
	my @typeUpdateArray = split /#/, $_[0]; #1=stat, 2=type, 3=value
	my $currentValue = $zoneData->{$zoneid}{basedata}{$typeUpdateArray[2]}{$typeUpdateArray[1]};
	my $updateAmount = $typeUpdateArray[3];
	my $newValue;

	if($updateAmount ne "0" && $updateAmount ne "-1") {
		$newValue = $updateAmount + $currentValue;
	} else {
		$newValue = $updateAmount;
	}
	
	$zoneData->{$zoneid}{basedata}{$typeUpdateArray[2]}{$typeUpdateArray[1]} = $newValue;
	quest::gmsay("Mob type [" . $typeUpdateArray[2] . "] has had key [" . $typeUpdateArray[1] . "] updated to: [" . $newValue . "]", 4, 1);
}

sub UPDATE_BOOLEAN_TYPE_BUFF {
	my @typeUpdateArray = split /#/, $_[0];
	my $currentValue = $zoneData->{$zoneid}{basedata}{$typeUpdateArray[2]}{$typeUpdateArray[1]};
	my $newValue = $typeUpdateArray[3];

	$zoneData->{$zoneid}{basedata}{$typeUpdateArray[2]}{$typeUpdateArray[1]} = $newValue;
	quest::gmsay("Mob type [" . $typeUpdateArray[2] . "] has had key [" . $typeUpdateArray[1] . "] updated to: [" . $newValue . "]", 4, 1);
}

sub UPDATE_ALPHA_TYPE_BUFF {
	my @typeUpdateArray = ();
	my @newStatArray = ();
	my $newValue;
	my $listeningState = $_[1];
	my $whisperModeKey = "_is_In_Whisper_Mode";
	my $whisperMode = plugin::TSSGet($client, $whisperModeKey);

	if(!$listeningState) {
		if(!$whisperMode) {
			@typeUpdateArray = split /#/, $_[0];
			PRINT_DETAIL_HEADER("Action", "Update Type Stat");
			plugin::Whisper("Say the updated value in the format: !whispermobstat# <new stat value> - You have 30 seconds. Be warned that anything you say to me after this message will be set as the new value!");
			plugin::TSSSet($client, $whisperModeKey, $typeUpdateArray[1] . "#" . $typeUpdateArray[2], 30);
		} else {
			plugin::Whisper("You have already requested to update. You must either wait 30 seconds between requests or say a value!");
		}
	} else {
		if($whisperMode) {
			@newStatArray = split /#/, $_[0];
			@typeUpdateArray = split /#/, $whisperMode;
			$newValue = $newStatArray[1];
			$newValue =~ s/\s//g;
			$zoneData->{$zoneid}{basedata}{$typeUpdateArray[1]}{$typeUpdateArray[0]} = $newValue;
			quest::gmsay("Mob type [" . $typeUpdateArray[1] . "] has had key [" . $typeUpdateArray[0] . "] updated to: [" . $newValue . "]", 4, 1);

			if($typeUpdateArray[0] eq "special_abilities") {
				$zoneData->{$zoneid}{basedata}{$typeUpdateArray[1]}{"special_attacks"} = -1;
				quest::gmsay("Warning: Setting [" . $typeUpdateArray[0] . "] forces special_attacks to be nullified. This has been done automatically.", 5, 1);
			} elsif($typeUpdateArray[0] eq "special_attacks") {
				$zoneData->{$zoneid}{basedata}{$typeUpdateArray[1]}{"special_abilities"} = -1;
				quest::gmsay("Warning: Setting [" . $typeUpdateArray[0] . "] forces special_abilities to be nullified. This has been done automatically.", 5, 1);
			}

			plugin::TSSDel($client, $whisperModeKey);
		} else {
			plugin::Whisper("You have taken too long to say a value, or you did not pick a stat type to update yet!");
		}
	}
}

sub UPDATE_INTEGER_CUSTOM_BUFF {
	my @typeUpdateArray = split /#/, $_[0]; #1=stat, 2=type, 3=value
	my $currentValue = $zoneData->{$zoneid}{custom}{$typeUpdateArray[2]}{$typeUpdateArray[1]};
	my $updateAmount = $typeUpdateArray[3];
	my $newValue;

	if($updateAmount ne "0" && $updateAmount ne "-1") {
		$newValue = $updateAmount + $currentValue;
	} else {
		$newValue = $updateAmount;
	}
	
	$zoneData->{$zoneid}{custom}{$typeUpdateArray[2]}{$typeUpdateArray[1]} = $newValue;
	quest::gmsay("Mob [" . $typeUpdateArray[2] . "] has had key [" . $typeUpdateArray[1] . "] updated to: [" . $newValue . "]", 4, 1);
}

sub UPDATE_INTEGER_CUSTOM_BUFF_DECREASE_BY_ONE_ONLY {
	my @typeUpdateArray = split /#/, $_[0]; #1=stat, 2=type, 3=value, 4=type
	my $currentValue = $zoneData->{$zoneid}{custom}{$typeUpdateArray[2]}{$typeUpdateArray[1]};
	my $statMod = $typeUpdateArray[1];
	$statMod =~ s/_mod//ig;
	$statMod =~ s/_override//ig;
	my $currentTypeValue = $zoneData->{$zoneid}{basedata}{$typeUpdateArray[4]}{$statMod};
	my $updateAmount = -1;
	my $newValue;
	
	if(($currentTypeValue + ($currentValue + $updateAmount)) > 1) {
		$newValue = $currentValue + $updateAmount;
		$zoneData->{$zoneid}{custom}{$typeUpdateArray[2]}{$typeUpdateArray[1]} = $newValue;
		quest::gmsay("Mob [" . $typeUpdateArray[2] . "] has had key [" . $typeUpdateArray[1] . "] updated to: [" . $newValue . "]", 4, 1);
	} else {
		quest::gmsay("ERROR: Mob [" . $typeUpdateArray[2] . "] key [" . $typeUpdateArray[1] . "] can not be updated to: [" . ($currentValue + $updateAmount) . "] as the minimum value after type and custom stat calculation must be greater than 1!", 5, 1);
	}
}

sub UPDATE_BOOLEAN_CUSTOM_BUFF {
	my @typeUpdateArray = split /#/, $_[0];
	my $currentValue = $zoneData->{$zoneid}{custom}{$typeUpdateArray[2]}{$typeUpdateArray[1]};
	my $newValue = $typeUpdateArray[3];

	$zoneData->{$zoneid}{custom}{$typeUpdateArray[2]}{$typeUpdateArray[1]} = $newValue;
	quest::gmsay("Mob type [" . $typeUpdateArray[2] . "] has had key [" . $typeUpdateArray[1] . "] updated to: [" . $newValue . "]", 4, 1);
}

sub UPDATE_ALPHA_CUSTOM_BUFF {
	my @typeUpdateArray = ();
	my @newStatArray = ();
	my $newValue;
	my $listeningState = $_[1];
	my $whisperModeKey = "_is_In_Whisper_Mode";
	my $whisperMode = plugin::TSSGet($client, $whisperModeKey);

	if(!$listeningState) {
		if(!$whisperMode) {
			@typeUpdateArray = split /#/, $_[0];
			PRINT_DETAIL_HEADER("Action", "Update Custom Stat");
			plugin::Whisper("Say the updated value in the format: !whispercustommobstat# <new stat value> - You have 30 seconds. Be warned that anything you say to me after this message will be set as the new value!");
			plugin::TSSSet($client, $whisperModeKey, $typeUpdateArray[1] . "#" . $typeUpdateArray[2], 30);
		} else {
			plugin::Whisper("You have already requested to update. You must either wait 30 seconds between requests or say a value!");
		}
	} else {
		if($whisperMode) {
			@newStatArray = split /#/, $_[0];
			@typeUpdateArray = split /#/, $whisperMode;
			$newValue = $newStatArray[1];
			$newValue =~ s/\s//g;
			$zoneData->{$zoneid}{custom}{$typeUpdateArray[1]}{$typeUpdateArray[0]} = $newValue;
			quest::gmsay("Mob [" . $typeUpdateArray[1] . "] has had key [" . $typeUpdateArray[0] . "] updated to: [" . $newValue . "]", 4, 1);

			if($typeUpdateArray[0] eq "special_abilities_override") {
				$zoneData->{$zoneid}{custom}{$typeUpdateArray[1]}{"special_attacks_override"} = -1;
				quest::gmsay("Warning: Setting [" . $typeUpdateArray[0] . "] forces special_attacks_override to be nullified. This has been done automatically.", 5, 1);
			} elsif($typeUpdateArray[0] eq "special_attacks_override") {
				$zoneData->{$zoneid}{custom}{$typeUpdateArray[1]}{"special_abilities_override"} = -1;
				quest::gmsay("Warning: Setting [" . $typeUpdateArray[0] . "] forces special_abilities_override to be nullified. This has been done automatically.", 5, 1);
			}

			plugin::TSSDel($client, $whisperModeKey);
		} else {
			plugin::Whisper("You have taken too long to say a value, or you did not pick a stat type to update yet!");
		}
	}
}

sub REMOVE_LOOT_TABLE_ITEM {
	my @removeItemArray = split /_/, $_[0]; #1=key, 2=table, 3=index
	my $itemIndex = FIRSTIDX_IN_HASH_ARRAY_BY_KEY($lootData->{$zoneid}{$removeItemArray[2]}, "name", $removeItemArray[1]);

	if($itemIndex < 0) {
		quest::gmsay("WARNING: Item [" . $removeItemArray[1] . "] was not found in loot table [" . $removeItemArray[2] . "]", 5, 1);
		return;
	}

	splice(@{$lootData->{$zoneid}{$removeItemArray[2]}}, $itemIndex, 1);
	quest::gmsay("Item [" . $removeItemArray[1] . "] has been removed from loot table [" . $removeItemArray[2] . "]", 4, 1);
}

sub INSERT_LOOT_TABLE_ITEM {
	my @insertItemArray = split /_/, $_[0]; #1=table, 2=itemname
	my %lootTableHash = GET_LOOT_TABLE_HASH();
	my @loottableHashArray = @{$lootTableHash{$insertItemArray[1]}};

	if (!grep{$_->{name} eq $insertItemArray[2]} @loottableHashArray) {
		$lootData->{$zoneid}{$insertItemArray[1]}[@loottableHashArray]{name} = $insertItemArray[2];
		quest::gmsay("Item [" . $insertItemArray[2] . "] has been added to loot table [" . $insertItemArray[1] . "]", 4, 1);
	} else {
		quest::gmsay("WARNING: Unable to add item [" . $insertItemArray[2] . "] to loot table [" . $insertItemArray[1] . "] - It already is assigned this table!", 5, 1);
	}
}

sub INSERT_LOOT_TABLE_ITEM_ALL{
	my @lootTableID = split /_/, $_[0];
	my %itemHash = GET_ITEM_HASH();

	foreach my $itemName (keys %itemHash) {
		my %lootTableHash = GET_LOOT_TABLE_HASH();
		my @loottableHashArray = @{$lootTableHash{$lootTableID[1]}};

		if($itemName ne "") {
			if (!grep{$_->{name} eq $itemName} @loottableHashArray) {
				$lootData->{$zoneid}{$lootTableID[1]}[@loottableHashArray]{name} = $itemName;
				quest::gmsay("Item [" . $itemName . "] has been added to loot table [" . $lootTableID[1] . "]", 4, 1);
			} else {
				quest::gmsay("WARNING: Unable to add item [" . $itemName . "] to loot table [" . $lootTableID[1] . "] - It already is assigned this table!", 5, 1);
			}
		}
	}

	PRINT_LOOT_TABLE_ITEMS_AS_PAGED_LIST("_" . $lootTableID[1] . "_0");
}

sub REMOVE_LOOT_TABLE_ITEM_ALL {
	my @lootTableID = split /_/, $_[0];
	my %lootTableHash = GET_LOOT_TABLE_HASH();
	my @loottableHashArray = @{$lootTableHash{$lootTableID[1]}};

	for (my $i = 0; $i < @loottableHashArray; $i++) {
		splice(@{$lootData->{$zoneid}{$lootTableID[1]}}, i, 1);
	}

	PRINT_LOOT_TABLE_ITEMS_AS_PAGED_LIST("_" . $lootTableID[1] . "_0");
	quest::gmsay("All items been removed from loot table [" . $lootTableID[1] . "]", 4, 1);
}

sub INSERT_ITEM {
	my @newItemArray = ();
	my $listeningState = $_[1];
	my $whisperModeKey = "_is_In_Whisper_Mode";
	my $whisperMode = plugin::TSSGet($client, $whisperModeKey);

	if(!$listeningState) {
		if(!$whisperMode) {
			PRINT_DETAIL_HEADER("Action", "Add New Item");
			plugin::Whisper("Say the new item id in the format: !additemid# <new item id> - You have 30 seconds. Be warned that anything you say to me after this message will be set as the new value!");
			plugin::TSSSet($client, $whisperModeKey, 1, 30);
		} else {
			plugin::Whisper("You have already requested to add a new item. You must either wait 30 seconds between requests or say a value!");
		}
	} else {
		if($whisperMode) {
			my %itemHash = GET_ITEM_HASH();
			@newItemArray = split /#/, $_[0];
			$newValue = $newItemArray[1];
			$newValue =~ s/\s//g;
			my $newItemName = plugin::GetItemNameByItemID($newValue);

			if($newItemName ne "LOOKUPERROR") {
				if (!exists($itemHash{$newItemName})) {
					$itemData->{$zoneid}{$newItemName}{itemid} = $newValue;
					$itemData->{$zoneid}{$newItemName}{description} = "-1";
					$itemData->{$zoneid}{$newItemName}{spellid} = "-1";
					$itemData->{$zoneid}{$newItemName}{isglobal} = "-1";
					$itemData->{$zoneid}{$newItemName}{globalkey} = "-1";
					quest::gmsay("Item [" . $newValue . "] was added successfully as [" . $newItemName . "]!", 4, 1);
					PRINT_ALL_LOOT_DROPS("_0");
					plugin::TSSDel($client, $whisperModeKey);
				} else {
					quest::gmsay("Item [" . $newValue . "] was not added - It already exists in the loot list!", 5, 1);
				}
			} else {
				plugin::TSSDel($client, $whisperModeKey);
				quest::gmsay("Item [" . $newValue . "] was not added - It doesn't exist in the database!", 5, 1);
			}
		} else {
			plugin::Whisper("You have taken too long to say a value, or you did not say an item id to add yet!");
		}
	}
}

sub INSERT_CUSTOM_MOB {
	my @newMobArray = ();
	my $listeningState = $_[1];
	my $whisperModeKey = "_is_In_Whisper_Mode";
	my $whisperMode = plugin::TSSGet($client, $whisperModeKey);

	if(!$listeningState) {
		if(!$whisperMode) {
			PRINT_DETAIL_HEADER("Action", "Add Custom Mob");
			plugin::Whisper("Say the new custom mob in the format: !addnewmob# <new mob name> -- You have 60 seconds. Be warned that anything you say to me after this message will be set as the new value!");
			@newMobArray = split /#/, $_[0];
			plugin::TSSSet($client, $whisperModeKey, $newMobArray[1], 60);
		} else {
			plugin::Whisper("You have already requested to add a new mob. You must either wait 60 seconds between requests or say a value!");
		}
	} else {
		if($whisperMode) {
			@customMobArray = GET_CUSTOM_MOB_ARRAY();
			@newMobArray = split /#/, $_[0];
			$newValue = $newMobArray[1];
			$newValue =~ s/^\s+|\s+$//g;
			$newValue =~ s/_/ /g;

			if (!grep{$_ eq $newValue} @customMobArray) {
				$zoneData->{$zoneid}{custom}{$newValue}{type} = $whisperMode;
				$zoneData->{$zoneid}{custom}{$newValue}{static} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{mobid} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{level_mod} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{max_hp_mod} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{min_hit_mod} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{max_hit_mod} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{aggro_mod} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{assist_mod} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{attack_speed_mod} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{special_attacks_override} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{special_abilities_override} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{see_invis_override} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{slow_mitigation_override} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{size_mod} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{cash_override} = "-1";
				$zoneData->{$zoneid}{custom}{$newValue}{loot} = [];
				quest::gmsay("Mob [" . $newValue . "] of the type [" . $whisperMode . "] was added successfully!", 4, 1);

				@staticNamedMobArray = GET_STATIC_NAMED_MOB_ARRAY();
				@namedMobArray = GET_NAMED_MOB_ARRAY();	
				@customMobArray = GET_CUSTOM_MOB_ARRAY();

				PRINT_MOB_LIST();
				plugin::TSSDel($client, $whisperModeKey);
			} else {
				quest::gmsay("Mob [" . $newValue . "] was not added - It already exists!", 5, 1);
			}
		} else {
			plugin::Whisper("You have taken too long to say a value, or you did not say a mob name to add yet!");
		}
	}
}

sub INSERT_CUSTOM_MOB_USING_REMOTE_PROTOCOL {
	my $newMob = $_[0];
	my $newMobType = $_[1];
	@customMobArray = GET_CUSTOM_MOB_ARRAY();
	$newMob =~ s/^\s+|\s+$//g;
	$newMobType=~ s/^\s+|\s+$//g;

	if (!grep{$_ eq $newMob} @customMobArray) {
		$zoneData->{$zoneid}{custom}{$newMob}{type} = $newMobType;
		$zoneData->{$zoneid}{custom}{$newMob}{static} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{mobid} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{level_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{max_hp_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{min_hit_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{max_hit_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{aggro_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{assist_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{attack_speed_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{special_attacks_override} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{special_abilities_override} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{see_invis_override} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{slow_mitigation_override} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{size_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{cash_override} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{loot} = [];
		quest::gmsay("Mob [" . $newMob . "] of the type [" . $newMobType . "] was added successfully!", 4, 1);

		@staticNamedMobArray = GET_STATIC_NAMED_MOB_ARRAY();
		@namedMobArray = GET_NAMED_MOB_ARRAY();	
		@customMobArray = GET_CUSTOM_MOB_ARRAY();
	} else {
		quest::gmsay("Mob [" . $newMob . "] of the type [" . $newMobType . "] was not added successfully - It already exists! [" . $zoneid . "]", 5, 1);
	}

	plugin::TSSDelRaw("Zone_Controller_New_Custom_Mob");
	plugin::TSSDelRaw("Zone_Controller_New_Custom_Mob_Type");
}

sub INSERT_CUSTOM_MOB_USING_DB_BATCH_MODE {
	my @listParams = split /_/, $_[0];
	my $newMob = $listParams[1];
	my $newMobType = $listParams[2];
	@customMobArray = GET_CUSTOM_MOB_ARRAY();
	$newMob =~ s/^\s+|\s+$//g;
	$newMobType=~ s/^\s+|\s+$//g;

	if (!grep{$_ eq $newMob} @customMobArray) {
		$zoneData->{$zoneid}{custom}{$newMob}{type} = $newMobType;
		$zoneData->{$zoneid}{custom}{$newMob}{static} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{mobid} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{level_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{max_hp_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{min_hit_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{max_hit_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{aggro_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{assist_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{attack_speed_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{special_attacks_override} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{special_abilities_override} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{see_invis_override} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{slow_mitigation_override} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{size_mod} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{cash_override} = "-1";
		$zoneData->{$zoneid}{custom}{$newMob}{loot} = [];
		quest::gmsay("Mob [" . $newMob . "] of the type [" . $newMobType . "] was added successfully!", 4, 1);

		@staticNamedMobArray = GET_STATIC_NAMED_MOB_ARRAY();
		@namedMobArray = GET_NAMED_MOB_ARRAY();	
		@customMobArray = GET_CUSTOM_MOB_ARRAY();
	} else {
		quest::gmsay("Mob [" . $newMob . "] of the type [" . $newMobType . "] was not added successfully - It already exists! [" . $zoneid . "]", 5, 1);
	}
}

sub INSERT_CUSTOM_LOOT_USING_REMOTE_PROTOCOL {
	my $newLoot = $_[0];
	my %itemHash = GET_ITEM_HASH();
	my $newItemName;
	my @newLootArray;
	$newLoot =~ s/^\s+|\s+$//g;
	my $isBatchLootEntry = index($newLoot, ",");

	if($newLoot ne "") {
		if($isBatchLootEntry) {
			@newLootArray = split /,/, $newLoot;

			foreach my $newValue (@newLootArray) {
				$newValue =~ s/^\s+|\s+$//g;
				$newValue =~ s/ //g;
				$newItemName = plugin::GetItemNameByItemID($newValue);

				if($newItemName ne "LOOKUPERROR") {
					if(!exists($itemHash{$newItemName})) {
						$itemData->{$zoneid}{$newItemName}{itemid} = $newValue;
						$itemData->{$zoneid}{$newItemName}{description} = "-1";
						$itemData->{$zoneid}{$newItemName}{spellid} = "-1";
						$itemData->{$zoneid}{$newItemName}{isglobal} = "-1";
						$itemData->{$zoneid}{$newItemName}{globalkey} = "-1";
						quest::gmsay("Item [" . $newValue . "] was added successfully as [" . $newItemName . "]!", 4, 1);
					} else {
						quest::gmsay("Item [" . $newValue . "] as [" . $newItemName . "] was not added successfully - It already exists! [" . $zoneid . "]", 5, 1);
					}
				} else {
					quest::gmsay("Item [" . $newValue . "] was not added successfully - This ID does not exist in the database! [" . $zoneid . "]", 5, 1);
				}
			}
		} else {
			$newItemName = plugin::GetItemNameByItemID($newValue);

			if($newItemName ne "LOOKUPERROR") {
				if(!exists($itemHash{$newItemName})) {
					$itemData->{$zoneid}{$newItemName}{itemid} = $newLoot;
					$itemData->{$zoneid}{$newItemName}{description} = "-1";
					$itemData->{$zoneid}{$newItemName}{spellid} = "-1";
					$itemData->{$zoneid}{$newItemName}{isglobal} = "-1";
					$itemData->{$zoneid}{$newItemName}{globalkey} = "-1";
					quest::gmsay("Item [" . $newLoot . "] was added successfully as [" . $newItemName . "]!", 4, 1);
				} else {
					quest::gmsay("Item [" . $newLoot . "] as [" . $newItemName . "] was not added successfully - It already exists! [" . $zoneid . "]", 5, 1);
				}
			} else {
				quest::gmsay("Item [" . $newLoot . "] was not added successfully - This ID does not exist in the database! [" . $zoneid . "]", 5, 1);
			}
		}
	} else {
		quest::gmsay("Item [" . $newLoot . "] was not added successfully - You did not provide an ID! [" . $zoneid . "]", 5, 1);
	}

	plugin::TSSDelRaw("Zone_Controller_New_Custom_Loot_Batch");
}

sub INSERT_CUSTOM_TABLE_USING_REMOTE_PROTOCOL {
	my $newTable = $_[0];
	my %tableHash = GET_LOOT_HASH();
	my $newTableName;
	my @newTableArray;
	my $newValue;
	my $newValueAsLowerCase;
	my $newTableAsLowerCase;
	my $isBatchLootEntry = index($newTable, ",");

	if($newTable ne "") {
		if($isBatchLootEntry) {
			@newTableArray = split /,/, $newTable;

			foreach my $newValue (@newTableArray) {
				$newValue =~ s/^\s+|\s+$//g;
				$newValue =~ s/_//g;
				$newValue =~ s/ //g;
				$newValueAsLowerCase = $newValue;

				if(!exists($tableHash{$newValueAsLowerCase})) {
					$lootData->{$zoneid}{$newValueAsLowerCase} = [];
					quest::gmsay("Loot table [" . $newValueAsLowerCase . "] was added successfully!", 4, 1);
				} else {
					quest::gmsay("Loot table [" . $newValueAsLowerCase . "] was not added successfully - It already exists! [" . $zoneid . "]", 5, 1);
				}
			}
		} else {
			$newTable =~ s/^\s+|\s+$//g;
			$newTable =~ s/_//g;
			$newTable =~ s/ //g;
			$newTableAsLowerCase = $newTable;

			if (!exists($tableHash{$newTableAsLowerCase})) {
				$lootData->{$zoneid}{$newTableAsLowerCase} = [];
				quest::gmsay("Loot table [" . $newTableAsLowerCase . "] was added successfully!", 4, 1);
			} else {
				quest::gmsay("Loot table [" . $newTableAsLowerCase . "] was not added successfully - It already exists! [" . $zoneid . "]", 5, 1);
			}
		}
	} else {
		quest::gmsay("Loot table was not added successfully - You did not provide a name! [" . $zoneid . "]", 5, 1);
	}

	plugin::TSSDelRaw("Zone_Controller_New_Custom_Loot_Batch");
}

sub ASSOCIATE_EXISTING_ITEMS_WITH_EXISTING_TABLES_USING_REMOTE_PROTOCOL {
	my $newEntry = $_[0];
	my %tableHash = GET_LOOT_HASH();
	my %lootTableHash = GET_LOOT_TABLE_HASH();
	my %itemHash = GET_ITEM_HASH();
	my $isBatchLootEntry = index($newEntry, ",");
	my $currentTable;
	my $itemName;
	my @loottableHashArray;
	use Scalar::Util qw(looks_like_number);
	use Data::Dumper;

	if($isBatchLootEntry) {
		@newEntryArray = split /,/, $newEntry;

		foreach my $newValue (@newEntryArray) {
			$newValue =~ s/^\s+|\s+$//g;
			$newValue =~ s/_//g;
			$newValue =~ s/ //g;
			
			if(!looks_like_number($newValue)) {
				if(exists($tableHash{$newValue})) {
					$currentTable = $newValue;
					quest::gmsay("Switching to loot table [" . $currentTable . "].", 4, 1);
				} else {
					quest::gmsay("ERROR: Bad data detected - Table does not exist: [" . $newValue . "]. Refreshing zone data and rolling back all batch changes.", 5, 1);
					quest::gmsay(Dumper(\%tableHash), 6, 1);
					INITIALIZE_DATA();
					last;
				}
			} else {
				if($currentTable ne '') {
					$itemName = plugin::GetItemNameByItemID($newValue);

					if($itemName ne "LOOKUPERROR") {
						if(exists($itemHash{$itemName})) {
							@loottableHashArray = @{$lootTableHash{$currentTable}};

							if(!grep{$_->{name} eq $itemName} @loottableHashArray) {
								$lootData->{$zoneid}{$currentTable}[@loottableHashArray]{name} = $itemName;
								quest::gmsay("Item [" . $itemName . "] has been added to loot table [" . $currentTable . "]", 4, 1);
							} else {
								quest::gmsay("WARNING: Unable to add item [" . $itemName . "] to loot table [" . $currentTable . "] - It is already assigned this table!", 5, 1);
							}	
						} else {
							quest::gmsay("ERROR: Bad data detected - Item does not exist in the item hash: " . $itemName . ". Refreshing zone data and rolling back all batch changes.", 5, 1);
							INITIALIZE_DATA();
							last;
						}
					} else {
						quest::gmsay("ERROR: Bad data detected - Item id does not exist in the database: [" . $newValue . "]. Refreshing zone data and rolling back all batch changes.", 5, 1);
						INITIALIZE_DATA();
						last;
					}
				}
			}
		}
	} else {
		quest::gmsay("ERROR: Failed to load items into tables - You did not pass in a comma-delimited list!", 5, 1);
	}

	plugin::TSSDelRaw("Zone_Controller_New_Custom_Loot_Association_Batch");
}

sub INSERT_IGNORE_MOB {
	my @newMobArray = ();
	my $listeningState = $_[1];
	my $whisperModeKey = "_is_In_Whisper_Mode";
	my $whisperMode = plugin::TSSGet($client, $whisperModeKey);

	if(!$listeningState) {
		if(!$whisperMode) {
			PRINT_DETAIL_HEADER("Action", "Add Ignored Mob");
			plugin::Whisper("Say the new ignored mob in the format: !addignoremob# <new mob name> - Use _ for spaces in the name and do not use any other special characters! You have 60 seconds. Be warned that anything you say to me after this message will be set as the new value!");
			@newMobArray = split /#/, $_[0];
			plugin::TSSSet($client, $whisperModeKey, $newMobArray[1], 60);
		} else {
			plugin::Whisper("You have already requested to add a new mob. You must either wait 60 seconds between requests or say a value!");
		}
	} else {
		if($whisperMode) {
			@ignoreArray = GET_IGNORE_ARRAY();
			@newMobArray = split /#/, $_[0];
			$newValue = $newMobArray[1];
			$newValue =~ s/^\s+|\s+$//g;
			$newValue =~ s/_/ /g;

			if (!grep{$_ eq $newValue} @ignoreArray) {
				$zoneData->{$zoneid}{ignore}{all}[@ignoreArray]{name} = $newValue;
				quest::gmsay("Mob [" . $newValue . "] was added to the ignore list successfully!", 4, 1);
				@ignoreArray = GET_IGNORE_ARRAY();
				plugin::Whisper("[" . quest::saylink("viewignoredmobs", 1, "View Ignored Mobs") . "]");
				plugin::TSSDel($client, $whisperModeKey);
			} else {
				quest::gmsay("Mob [" . $newValue . "] was not added - It is already on the ignore list!", 5, 1);
			}
		} else {
			plugin::Whisper("You have taken too long to say a value, or you did not say a mob name to add yet!");
		}
	}
}

sub INSERT_IGNORE_MOB_USING_REMOTE_PROTOCOL {
	my $newMob = $_[0];
	@ignoreArray = GET_IGNORE_ARRAY();
	$newMob =~ s/^\s+|\s+$//g;
	$newMob =~ s/_/ /g;

	if (!grep{$_ eq $newMob} @ignoreArray) {
		$zoneData->{$zoneid}{ignore}{all}[@ignoreArray]{name} = $newMob;
		quest::gmsay("Mob [" . $newMob . "] was added to the ignore list successfully!", 4, 1);
		@ignoreArray = GET_IGNORE_ARRAY();
	} else {
		quest::gmsay("Mob [" . $newMob . "] was not added to the ignore list - It already exists!", 5, 1);
	}

	plugin::TSSDelRaw("Zone_Controller_Ignore_Mob");
}

sub INSERT_DEPOP_MOB {
	my @newMobArray = ();
	my $listeningState = $_[1];
	my $whisperModeKey = "_is_In_Whisper_Mode";
	my $whisperMode = plugin::TSSGet($client, $whisperModeKey);

	if(!$listeningState) {
		if(!$whisperMode) {
			PRINT_DETAIL_HEADER("Action", "Add Depop Mob");
			plugin::Whisper("Say the new depop mob in the format: !adddepopemob# <new mob name> - Use _ for spaces in the name! You have 60 seconds. Be warned that anything you say to me after this message will be set as the new value!");
			@newMobArray = split /#/, $_[0];
			plugin::TSSSet($client, $whisperModeKey, $newMobArray[1], 60);
		} else {
			plugin::Whisper("You have already requested to add a new mob. You must either wait 60 seconds between requests or say a value!");
		}
	} else {
		if($whisperMode) {
			@depopArray = GET_DEPOP_ARRAY();
			@newMobArray = split /#/, $_[0];
			$newValue = $newMobArray[1];
			$newValue =~ s/^\s+|\s+$//g;
			$newValue =~ s/_/ /g;

			if (!grep{$_ eq $newValue} @depopArray) {
				$zoneData->{$zoneid}{depop}{all}[@depopArray]{name} = $newValue;
				quest::gmsay("Mob [" . $newValue . "] was added to the depop list successfully!", 4, 1);
				@depopArray = GET_DEPOP_ARRAY();
				plugin::Whisper("[" . quest::saylink("viewdepopmobs", 1, "View Depop Mobs") . "]");
				plugin::TSSDel($client, $whisperModeKey);
			} else {
				quest::gmsay("Mob [" . $newValue . "] was not added - It is already on the depop list!", 5, 1);
			}
		} else {
			plugin::Whisper("You have taken too long to say a value, or you did not say a mob name to add yet!");
		}
	}
}

sub INSERT_DEPOP_MOB_USING_REMOTE_PROTOCOL {
	my $newMob = $_[0];
	@depopArray = GET_DEPOP_ARRAY();
	$newMob =~ s/^\s+|\s+$//g;
	$newMob =~ s/_/ /g;

	if (!grep{$_ eq $newMob} @depopArray) {
		$zoneData->{$zoneid}{depop}{all}[@depopArray]{name} = $newMob;
		quest::gmsay("Mob [" . $newMob . "] was added to the depop list successfully!", 4, 1);
		@depopArray = GET_DEPOP_ARRAY();
	} else {
		quest::gmsay("Mob [" . $newMob . "] was not added to the depop list - It already exists!", 5, 1);
	}

	plugin::TSSDelRaw("Zone_Controller_Depop_Mob");
}

sub REMOVE_LOOT_TABLE_ITEM_FROM_ALL_LOOT_TABLES {
	my @itemName = split /_/, $_[0];
	my %lootTableHash = GET_LOOT_TABLE_HASH();

	foreach my $key (keys %lootTableHash) {
		for (my $i = 0; $i < @{$lootTableHash{$key}}; $i++) {
			if($lootTableHash{$key}[$i]{name} eq $itemName[1]) {
				splice(@{$lootData->{$zoneid}{$key}}, $i, 1);
			}
		}
	}

	quest::gmsay("Item [" . $itemName[1] . "] has been removed from all loot tables.", 4, 1);
}

sub REMOVE_TYPE_LOOT_TABLE_REFERENCE {
	my @removeTableArray = split /_/, $_[0]; #1=table, 2=Type
	my @allAssociatedLootTablesArray = @{$zoneData->{$zoneid}{basedata}{$removeTableArray[2]}{loot}};
	my $index = 0;

	foreach my $lootHash (@allAssociatedLootTablesArray) {
		if($lootHash->{id} eq $removeTableArray[1]) {
			last;
		} else {
			$index = $index + 1;
		}
	}

	splice(@{$zoneData->{$zoneid}{basedata}{$removeTableArray[2]}{loot}}, $index, 1);

	quest::gmsay("Loot table reference [" . $removeTableArray[1] . "] has been removed from type [" . $removeTableArray[2] . "]", 4, 1);
}

sub REMOVE_CUSTOM_LOOT_TABLE_REFERENCE {
	my @removeTableArray = split /_/, $_[0]; #1=table, 2=Name
	my @allAssociatedLootTablesArray = @{$zoneData->{$zoneid}{custom}{$removeTableArray[2]}{loot}};
	my $index = 0;

	foreach my $lootHash (@allAssociatedLootTablesArray) {
		if($lootHash->{id} eq $removeTableArray[1]) {
			last;
		} else {
			$index = $index + 1;
		}
	}

	splice(@{$zoneData->{$zoneid}{custom}{$removeTableArray[2]}{loot}}, $index, 1);
	quest::gmsay("Loot table reference [" . $removeTableArray[1] . "] has been removed from mob [" . $removeTableArray[2] . "]", 4, 1);
}

sub INSERT_CUSTOM_LOOT_TABLE_REFERENCE {
	my @insertTableArray = split /_/, $_[0];
	my %customBuffHash = GET_CUSTOM_BUFF_HASH($insertTableArray[2]);
	my @customBuffHashArray = @{$customBuffHash{loot}};

	if (!grep{$_->{id} eq $insertTableArray[1]} @customBuffHashArray) {
		$zoneData->{$zoneid}{custom}{$insertTableArray[2]}{loot}[@customBuffHashArray]{id} = $insertTableArray[1];
		$zoneData->{$zoneid}{custom}{$insertTableArray[2]}{loot}[@customBuffHashArray]{chance} = "100";
		quest::gmsay("Loot table reference [" . $insertTableArray[1] . "] has been added to mob [" . $insertTableArray[2] . "]", 4, 1);
	} else {
		quest::gmsay("WARNING: Unable to add loot table reference [" . $insertTableArray[1] . "] to mob [" . $insertTableArray[2] . "] - It already is assigned this table!", 5, 1);
	}
}

sub CREATE_NEW_LOOT_TABLE {
	my @newTableArray = ();
	my $newValue;
	my $newValueAsLowerCase;
	my $listeningState = $_[1];
	my $whisperModeKey = "_is_In_Whisper_Mode";
	my $whisperMode = plugin::TSSGet($client, $whisperModeKey);

	if(!$listeningState) {
		if(!$whisperMode) {
			PRINT_DETAIL_HEADER("Action", "Add New Loot Table");
			plugin::Whisper("Say the new loot table id in the format: !wnt# <new loot table id> - You have 30 seconds. Be warned that anything you say to me after this message will be set as the new value!");
			plugin::TSSSet($client, $whisperModeKey, 1, 30);
		} else {
			plugin::Whisper("You have already requested to add a new loot table. You must either wait 30 seconds between requests or say a value!");
		}
	} else {
		if($whisperMode) {
			my %lootHash = GET_LOOT_HASH();
			@newTableArray = split /#/, $_[0];
			$newValue = $newTableArray[1];
			$newValue =~ s/^\s+|\s+$//g;
			$newValue =~ s/_//g;
			$newValue =~ s/ //g;
			$newValueAsLowerCase = lc $newValue;

			if (!exists($lootHash{$newValueAsLowerCase})) {
				$lootData->{$zoneid}{$newValueAsLowerCase} = [];
				quest::gmsay("Loot table [" . $newValueAsLowerCase . "] was added successfully!", 4, 1);
				plugin::TSSDel($client, $whisperModeKey);
				REMOVE_LOOT_TABLE_ITEM_ALL("_" . $newValueAsLowerCase);
				PRINT_ALL_LOOT_TABLES();
			} else {
				quest::gmsay("Loot table [" . $newValueAsLowerCase . "] was not added - It already exists!", 5, 1);
			}
		} else {
			plugin::Whisper("You have taken too long to say a value, or you did not say an item id to add yet!");
		}
	}
}

sub INSERT_TYPE_LOOT_TABLE_REFERENCE {
	my @insertTableArray = split /_/, $_[0];
	my %typeBuffHash = GET_TYPE_BUFF_HASH($insertTableArray[2]);
	my @typeBuffHashArray = @{$typeBuffHash{loot}};

	if (!grep{$_->{id} eq $insertTableArray[1]} @typeBuffHashArray) {
		$zoneData->{$zoneid}{basedata}{$insertTableArray[2]}{loot}[@typeBuffHashArray]{id} = $insertTableArray[1];
		$zoneData->{$zoneid}{basedata}{$insertTableArray[2]}{loot}[@typeBuffHashArray]{chance} = "100";
		quest::gmsay("Loot table reference [" . $insertTableArray[1] . "] has been added to mob type [" . $insertTableArray[2] . "]", 4, 1);

			my $mobType;
			my %customBuffHash;
			my @customBuffHashArray;
			my $currentDropIndex;

			foreach my $mobName (@customMobArray) {
				$mobType = GET_MOB_TYPE($mobName);
				%customBuffHash = GET_CUSTOM_BUFF_HASH($mobName);
				@customBuffHashArray = @{$customBuffHash{loot}};

				if (grep{$_->{id} eq $insertTableArray[1]} @customBuffHashArray) {
					$currentDropIndex = FIRSTIDX_IN_HASH_ARRAY_BY_KEY(\@customBuffHashArray, "id", $insertTableArray[1]);
					splice(@{$zoneData->{$zoneid}{custom}{$mobName}{loot}}, $currentDropIndex, 1);
					quest::gmsay("WARNING: Custom loot table reference [" . $insertTableArray[1] . "] for mob [" . $mobName . "] was removed - It was added to this mobs type table and duplicates within these two tables is not permitted!", 5, 1);
				}
			}
	} else {
		quest::gmsay("WARNING: Unable to add loot table reference [" . $insertTableArray[1] . "] to mob type [" . $insertTableArray[2] . "] - It already is assigned this table!", 5, 1);
	}
}

sub UPDATE_CUSTOM_LOOT_DROP_PERCENT {
	my @updatePercentArray = split /_/, $_[0];
	my $changeType = $_[1];
	my %customBuffHash = GET_CUSTOM_BUFF_HASH($updatePercentArray[3]);
	my @customBuffHashArray = @{$customBuffHash{loot}};
	my $currentDropPercent; 
	my $currentDropIndex;
	
	if (grep{$_->{id} eq $updatePercentArray[2]} @customBuffHashArray) {
		$currentDropIndex = FIRSTIDX_IN_HASH_ARRAY_BY_KEY(\@customBuffHashArray, "id", $updatePercentArray[2]);
		$currentDropPercent = $zoneData->{$zoneid}{custom}{$updatePercentArray[3]}{loot}[$currentDropIndex]{chance};
			
		if($changeType) {
			if(($currentDropPercent + $updatePercentArray[1]) <= 100) {
				$zoneData->{$zoneid}{custom}{$updatePercentArray[3]}{loot}[$currentDropIndex]{chance} = ($currentDropPercent + $updatePercentArray[1]);
				quest::gmsay("Loot table reference [" . $updatePercentArray[2] . "] for mob [" . $updatePercentArray[3] . "] has been increased by [" . $updatePercentArray[1] . "]. The new value is: [" . ($currentDropPercent + $updatePercentArray[1]) . "]", 4, 1);
			} else {
				quest::gmsay("WARNING: Loot table reference [" . $updatePercentArray[2] . "] for mob [" . $updatePercentArray[3] . "] can not be increased above 100 percent.", 5, 1);
			}
		} else {
			if(($currentDropPercent - $updatePercentArray[1]) >= 0) {
				$zoneData->{$zoneid}{custom}{$updatePercentArray[3]}{loot}[$currentDropIndex]{chance} = ($currentDropPercent - $updatePercentArray[1]);
				quest::gmsay("Loot table reference [" . $updatePercentArray[2] . "] for mob [" . $updatePercentArray[3] . "] has been decreased by [" . $updatePercentArray[1] . "]. The new value is: [" . ($currentDropPercent - $updatePercentArray[1]) . "]", 4, 1);
			} else {
				quest::gmsay("WARNING: Loot table reference [" . $updatePercentArray[2] . "] for mob [" . $updatePercentArray[3] . "] can not be reduced below 0 percent.", 5, 1);
			}
		}		
	}
}

sub UPDATE_TYPE_LOOT_DROP_PERCENT {
	my @updatePercentArray = split /_/, $_[0];
	my $changeType = $_[1];
	my %typeBuffHash = GET_TYPE_BUFF_HASH($updatePercentArray[3]);
	my @typeBuffHashArray = @{$typeBuffHash{loot}};
	my $currentDropPercent; 
	my $currentDropIndex;
	
	if (grep{$_->{id} eq $updatePercentArray[2]} @typeBuffHashArray) {
		$currentDropIndex = FIRSTIDX_IN_HASH_ARRAY_BY_KEY(\@typeBuffHashArray, "id", $updatePercentArray[2]);
		$currentDropPercent = $zoneData->{$zoneid}{basedata}{$updatePercentArray[3]}{loot}[$currentDropIndex]{chance};
			
		if($changeType) {
			if(($currentDropPercent + $updatePercentArray[1]) <= 100) {
				$zoneData->{$zoneid}{basedata}{$updatePercentArray[3]}{loot}[$currentDropIndex]{chance} = ($currentDropPercent + $updatePercentArray[1]);
				quest::gmsay("Loot table reference [" . $updatePercentArray[2] . "] for mob type [" . $updatePercentArray[3] . "] has been increased by [" . $updatePercentArray[1] . "]. The new value is: [" . ($currentDropPercent + $updatePercentArray[1]) . "]", 4, 1);
			} else {
				quest::gmsay("WARNING: Loot table reference [" . $updatePercentArray[2] . "] for mob [" . $updatePercentArray[3] . "] can not be increased above 100 percent.", 5, 1);				
			}
		} else {
			if(($currentDropPercent - $updatePercentArray[1]) >= 0) {
				$zoneData->{$zoneid}{basedata}{$updatePercentArray[3]}{loot}[$currentDropIndex]{chance} = ($currentDropPercent - $updatePercentArray[1]);
				quest::gmsay("Loot table reference [" . $updatePercentArray[2] . "] for mob type [" . $updatePercentArray[3] . "] has been decreased by [" . $updatePercentArray[1] . "]. The new value is: [" . ($currentDropPercent - $updatePercentArray[1]) . "]", 4, 1);
			} else {
				quest::gmsay("WARNING: Loot table reference [" . $updatePercentArray[2] . "] for mob type [" . $updatePercentArray[3] . "] can not be reduced below 0 percent.", 5, 1);
			}
		}		
	}
}

sub UPDATE_CUSTOM_LOOT_DROP_PERCENT_IMPLICITLY {
	my @updatePercentArray = split /_/, $_[0];
	my %customBuffHash = GET_CUSTOM_BUFF_HASH($updatePercentArray[3]);
	my @customBuffHashArray = @{$customBuffHash{loot}};
	my $currentDropIndex;
	
	if (grep{$_->{id} eq $updatePercentArray[2]} @customBuffHashArray) {
		$currentDropIndex = FIRSTIDX_IN_HASH_ARRAY_BY_KEY(\@customBuffHashArray, "id", $updatePercentArray[2]);
		$zoneData->{$zoneid}{custom}{$updatePercentArray[3]}{loot}[$currentDropIndex]{chance} = $updatePercentArray[1];
		quest::gmsay("Loot table reference [" . $updatePercentArray[2] . "] for mob [" . $updatePercentArray[3] . "] has been set to [" . $updatePercentArray[1] . "]", 4, 1);
	}
}

sub UPDATE_TYPE_LOOT_DROP_PERCENT_IMPLICITLY {
	my @updatePercentArray = split /_/, $_[0];
	my %typeBuffHash = GET_TYPE_BUFF_HASH($updatePercentArray[3]);
	my @typeBuffHashArray = @{$typeBuffHash{loot}};
	my $currentDropIndex;
	
	if (grep{$_->{id} eq $updatePercentArray[2]} @typeBuffHashArray) {
		$currentDropIndex = FIRSTIDX_IN_HASH_ARRAY_BY_KEY(\@typeBuffHashArray, "id", $updatePercentArray[2]);
		$zoneData->{$zoneid}{basedata}{$updatePercentArray[3]}{loot}[$currentDropIndex]{chance} = $updatePercentArray[1];
		quest::gmsay("Loot table reference [" . $updatePercentArray[2] . "] for mob type [" . $updatePercentArray[3] . "] has been set to [" . $updatePercentArray[1] . "]", 4, 1);
	}
}

sub REMOVE_LOOT_TABLE {
	my @removeTableArray = split /_/, $_[0]; #1=table
	my @typeArray = ("trash", "boss", "raid");
	my @allCustomMobs = GET_CUSTOM_MOB_ARRAY();
	
	foreach my $type (@typeArray) {
		my $typeCounter = 0;
		my @allAssociatedTypeLootTablesArray = @{$zoneData->{$zoneid}{basedata}{$type}{loot}};
		
		foreach my $lootHash (@allAssociatedTypeLootTablesArray) {
			if($lootHash->{id} eq $removeTableArray[1]) {
				splice(@{$zoneData->{$zoneid}{basedata}{$type}{loot}}, $typeCounter, 1);
			} else {
				$typeCounter = $typeCounter + 1;
			}
		}
	}

	foreach my $custom (@allCustomMobs) {
		my $customCounter = 0;
		my @allAssociatedCustomLootTablesArray = @{$zoneData->{$zoneid}{custom}{$custom}{loot}};
		
		foreach my $lootHash (@allAssociatedCustomLootTablesArray) {
			if($lootHash->{id} eq $removeTableArray[1]) {
				splice(@{$zoneData->{$zoneid}{custom}{$custom}{loot}}, $customCounter, 1);
			} else {
				$customCounter = $customCounter + 1;
			}
		}
	}

	delete ($lootData->{$zoneid}{$removeTableArray[1]});
	PRINT_ALL_LOOT_TABLES();
	quest::gmsay("Table [" . $removeTableArray[1] . "] has been deleted and all npc loot drops assigned to it have been removed.", 4, 1);
}

sub REMOVE_IGNORED_MOB {
	my @removeMobArray = split /_/, $_[0]; #1=mob
	my $ignoreCounter = 0;
	my @allAssociatedIgnoredMobsHashAsArray = @{$zoneData->{$zoneid}{ignore}{all}};

	foreach my $ignoredMob (@allAssociatedIgnoredMobsHashAsArray) {
		if($ignoredMob->{name} eq $removeMobArray[1]) {
			splice(@{$zoneData->{$zoneid}{ignore}{all}}, $ignoreCounter, 1);
		} else {
			$ignoreCounter = $ignoreCounter + 1;
		}
	}
	
	@ignoreArray = grep {$_ ne $removeMobArray[1]} @ignoreArray;
	quest::gmsay("Mob [" . $removeMobArray[1] . "] has been removed from the ignore list.", 4, 1);
}

sub REMOVE_DEPOP_MOB {
	my @depopMobArray = split /_/, $_[0]; #1=mob
	my $depopCounter = 0;
	my @allAssociatedDepopMobsHashAsArray = @{$zoneData->{$zoneid}{depop}{all}};

	foreach my $depopMob (@allAssociatedDepopMobsHashAsArray) {
		if($depopMob->{name} eq $depopMobArray[1]) {
			splice(@{$zoneData->{$zoneid}{depop}{all}}, $depopCounter, 1);
		} else {
			$depopCounter = $depopCounter + 1;
		}
	}
	
	@depopArray = grep {$_ ne $depopMobArray[1]} @depopArray;
	quest::gmsay("Mob [" . $depopMobArray[1] . "] has been removed from the depop list.", 4, 1);
}

sub REMOVE_MOB {
	my @removeMobArray = split /_/, $_[0]; #1=mob
	delete($zoneData->{$zoneid}{custom}{$removeMobArray[1]});
	
	@staticNamedMobArray = grep {$_ ne $removeMobArray[1]} @staticNamedMobArray;
	@namedMobArray = grep {$_ ne $removeMobArray[1]} @namedMobArray;
	@customMobArray = grep {$_ ne $removeMobArray[1]} @customMobArray;

	quest::gmsay("Custom mob [" . $removeMobArray[1] . "] has been removed.", 4, 1);
}

sub REMOVE_ITEM_BY_NAME {
	my @itemArray = split /_/, $_[0]; #1=item
	delete($itemData->{$zoneid}{$itemArray[1]});
	REMOVE_LOOT_TABLE_ITEM_FROM_ALL_LOOT_TABLES("_" . $itemArray[1]);
	quest::gmsay("Item [" . $itemArray[1] . "] has been removed from the item list.", 4, 1);
}

sub REMOVE_ITEM_ALL {
	my %itemHash = GET_ITEM_HASH();

	foreach my $itemName (keys %itemHash) {
		REMOVE_ITEM_BY_NAME("_" . $itemName);
	}
	PRINT_ALL_LOOT_DROPS("_0");
}

sub UPDATE_ZONE_INFO {
	my @zoneInfoUpdateArray = ();
	my @newValueArray = ();
	my $newZoneInfoValue;
	my $listeningState = $_[1];
	my $whisperModeKey = "_is_In_Whisper_Mode";
	my $whisperMode = plugin::TSSGet($client, $whisperModeKey);

	if(!$listeningState) {
		if(!$whisperMode) {
			@zoneInfoUpdateArray = split /#/, $_[0];
			PRINT_DETAIL_HEADER("Action", "Update Zone Info");
			plugin::Whisper("Say the updated value for [" . $zoneInfoUpdateArray[1] . "] in the format: !whisperzoneinfo# <new info> - You have 30 seconds. Be warned that anything you say to me after this message will be set as the new value!");
			plugin::TSSSet($client, $whisperModeKey, $zoneInfoUpdateArray[1], 30);
		} else {
			plugin::Whisper("You have already requested to update. You must either wait 30 seconds between requests or say a value!");
		}
	} else {
		if($whisperMode) {
			@newValueArray = split /#/, $_[0];
			$newZoneInfoValue = $newValueArray[1];
			$newZoneInfoValue =~ s/^\s+|\s+$//g;
			$zoneData->{$zoneid}{info}{$whisperMode} = $newZoneInfoValue;
			quest::gmsay("Zone info key [" . $whisperMode . "] updated to: [" . $newZoneInfoValue . "]", 4, 1);
			plugin::TSSDel($client, $whisperModeKey);
			plugin::Whisper("[" . quest::saylink("viewzoneinfo", 1, "Reload Zone Info") . "] [" . quest::saylink("viewquickactions", 1, "View Quick Actions") . "]");
		} else {
			plugin::Whisper("You have taken too long to say a value, or you did not pick a zone info value to update yet!");
		}
	}
}

sub UPDATE_MOB_NAME {
	my @mobInfoUpdateArray = ();
	my @newValueArray = ();
	my $newMobInfoValue;
	my $listeningState = $_[1];
	my $whisperModeKey = "_is_In_Whisper_Mode";
	my $whisperMode = plugin::TSSGet($client, $whisperModeKey);

	if(!$listeningState) {
		if(!$whisperMode) {
			@mobInfoUpdateArray = split /#/, $_[0];
			PRINT_DETAIL_HEADER("Action", "Update Mob Name");
			plugin::Whisper("Say the updated name for [" . $mobInfoUpdateArray[1] . "] in the format: !whispermobname# <new info> - You have 60 seconds. Be warned that anything you say to me after this message will be set as the new value!");
			plugin::TSSSet($client, $whisperModeKey, $mobInfoUpdateArray[1], 60);
		} else {
			plugin::Whisper("You have already requested to update. You must either wait 60 seconds between requests or say a value!");
		}
	} else {
		if($whisperMode) {
			@newValueArray = split /#/, $_[0];
			$newMobInfoValue = $newValueArray[1];
			$newMobInfoValue =~ s/^\s+|\s+$//g;
			$zoneData->{$zoneid}{custom}{$newMobInfoValue} = delete $zoneData->{$zoneid}{custom}{$whisperMode};
			quest::gmsay("Mob name [" . $whisperMode . "] has been updated to: [" . $newMobInfoValue . "]. All custom mob name arrays have also been reinitialized.", 4, 1);
			
			@staticNamedMobArray = GET_STATIC_NAMED_MOB_ARRAY();
			@namedMobArray = GET_NAMED_MOB_ARRAY();	
			@customMobArray = GET_CUSTOM_MOB_ARRAY();

			plugin::TSSDel($client, $whisperModeKey);
			PRINT_MOB_LIST();
		} else {
			plugin::Whisper("You have taken too long to say a value, or you did not pick a zone info value to update yet!");
		}
	}	
}

sub CLONE_MOB {
	my @mobInfoUpdateArray = ();
	my @newValueArray = ();
	my $newMobInfoValue;
	my $listeningState = $_[1];
	my $whisperModeKey = "_is_In_Whisper_Mode";
	my $whisperMode = plugin::TSSGet($client, $whisperModeKey);

	if(!$listeningState) {
		if(!$whisperMode) {
			@mobInfoUpdateArray = split /#/, $_[0];
			PRINT_DETAIL_HEADER("Action", "Clone Mob");
			plugin::Whisper("Say the name of the new mob to clone from [" . $mobInfoUpdateArray[1] . "] in the format: !whisperclonename# <new info> - You have 60 seconds. Be warned that anything you say to me after this message will be set as the new value!");
			plugin::TSSSet($client, $whisperModeKey, $mobInfoUpdateArray[1], 60);
		} else {
			plugin::Whisper("You have already requested to update. You must either wait 60 seconds between requests or say a value!");
		}
	} else {
		if($whisperMode) {
			@newValueArray = split /#/, $_[0];
			$newMobInfoValue = $newValueArray[1];
			$newMobInfoValue =~ s/^\s+|\s+$//g;
			use Storable 'dclone';
			$zoneData->{$zoneid}{custom}{$newMobInfoValue} = dclone $zoneData->{$zoneid}{custom}{$whisperMode};
			quest::gmsay("Mob name [" . $whisperMode . "] has been cloned to: [" . $newMobInfoValue . "]. All custom mob name arrays have also been reinitialized.", 4, 1);
			
			@staticNamedMobArray = GET_STATIC_NAMED_MOB_ARRAY();
			@namedMobArray = GET_NAMED_MOB_ARRAY();	
			@customMobArray = GET_CUSTOM_MOB_ARRAY();

			plugin::TSSDel($client, $whisperModeKey);
			PRINT_MOB_LIST();
		} else {
			plugin::Whisper("You have taken too long to say a value, or you did not pick a zone info value to update yet!");
		}
	}	
}

sub UPDATE_ITEM_DETAILS {
	my @itemInfoUpdateArray = ();
	my @newValueArray = ();
	my $newZoneInfoValue;
	my $listeningState = $_[1];
	my $whisperModeKey = "_is_In_Whisper_Mode";
	my $whisperMode = plugin::TSSGet($client, $whisperModeKey);

	if(!$listeningState) {
		if(!$whisperMode) {
			@itemInfoUpdateArray = split /#/, $_[0]; #1=item name 2=key
			PRINT_DETAIL_HEADER("Action", "Update Item Details");
			plugin::Whisper("Say the updated value for the [" . $itemInfoUpdateArray[2] . "] field associated with item [" . $itemInfoUpdateArray[1] . "] in the format: !updateitemdetails# <new details> - You have 60 seconds. Be warned that anything you say to me after this message will be set as the new value!");
			plugin::TSSSet($client, $whisperModeKey, $itemInfoUpdateArray[1] . "#" . $itemInfoUpdateArray[2], 60);
		} else {
			plugin::Whisper("You have already requested to update. You must either wait 60 seconds between requests or say a value!");
		}
	} else {
		if($whisperMode) {
			@newItemInfoArray = split /#/, $_[0];
			@storedItemInfoArray = split /#/, $whisperMode;
			$newItemInfoValue = $newItemInfoArray[1];
			$newItemInfoValue =~ s/^\s+|\s+$//g;
			$itemData->{$zoneid}{$storedItemInfoArray[0]}{$storedItemInfoArray[1]} = $newItemInfoValue;
			quest::gmsay("Item info key [" . $storedItemInfoArray[1] . "] for item [" . $storedItemInfoArray[0] . "] was updated to: [" . $newItemInfoValue . "]", 4, 1);
			plugin::TSSDel($client, $whisperModeKey);
			plugin::Whisper("[" . quest::saylink("viewitemdata_" . $storedItemInfoArray[0], 1, "Reload Item Details") . "] [" . quest::saylink("viewquickactions", 1, "View Quick Actions") . "]");
		} else {
			plugin::Whisper("You have taken too long to say a value, or you did not pick an item info value to update yet!");
		}
	}
}

sub DO_SAVE_CONFIRMATION {
	quest::popup("Save Changes", "<br>Are you sure that you want to <c \"#32CD32\">save</c> all changes permenantly?", 100111, 1, 120);
}

sub STORE_MOB_JSON {
	plugin::UpdateSpawnDataHash($zoneData, $zoneid);
	quest::gmsay("Mob JSON has been updated!", 4, 1);
}

sub STORE_LOOT_JSON {
	plugin::UpdateLootDataHash($lootData, $zoneid);
	quest::gmsay("Loot JSON has been updated!", 4, 1);
}

sub STORE_ITEM_JSON {
	plugin::UpdateItemDataHash($itemData, $zoneid);
	quest::gmsay("Item JSON has been updated!", 4, 1);
}


#--------------------------------------------------------------------------#
#---Admin Block: Display interface to enable to dynamic updating of mobs---#
#--------------------------------------------------------------------------#

sub PRINT_MOB_LIST {
	my $mobCounter = 1;
	PRINT_DETAIL_HEADER("Info", "All Mobs");
	plugin::Whisper("The following list contains all mobs along with their stats and loot tables. [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");
	plugin::Whisper("");
	plugin::Whisper("Custom Mobs:");
	
	foreach my $mobName (@customMobArray) {
		plugin::Whisper($mobCounter . ". " . $mobName . " [" . quest::saylink("vl_" . $mobName, 1, "View Loot Tables") . "] [" . quest::saylink("vfs_" . $mobName, 1, "View Stats") . "] [" . quest::saylink("clonemob#" . $mobName, 1, "Clone") . "] [" . quest::saylink("renamemob#" . $mobName, 1, "Rename") . "] [" . quest::saylink("removemob_" . $mobName, 1, "Remove") . "]");
		$mobCounter = $mobCounter + 1;
	}
	
	plugin::Whisper("");
	plugin::Whisper("Mob Types:");
	plugin::Whisper($mobCounter . ". " . "All Trash" . " [" . quest::saylink("vl_" . "TrashALL", 1, "View Loot Tables") . "] [" . quest::saylink("vts_" . "TrashALL", 1, "View Stats") . "]");
	plugin::Whisper($mobCounter + 1 . ". " . "All Bosses" . " [" . quest::saylink("vl_" . "BossALL", 1, "View Loot Tables") . "] [" . quest::saylink("vts_" . "BossALL", 1, "View Stats") . "]");
	plugin::Whisper($mobCounter + 2 . ". " . "All Raid Bosses" . " [" . quest::saylink("vl_" . "RaidALL", 1, "View Loot Tables") . "] [" . quest::saylink("vts_" . "RaidALL", 1, "View Stats") . "]");

	plugin::Whisper("");
	plugin::Whisper("[" . quest::saylink("viewallmobs", 1, "Refresh This View") . "] [" . quest::saylink("addnewcustommob", 1, "Add New Custom Mob") . "] [" . quest::saylink("batchaddncustommobs", 1, "Batch Add New Custom Mobs") . "]");
}

sub PRINT_REMOTE_COMMANDS{
	PRINT_DETAIL_HEADER("Info", "Remote Commands");
	plugin::Whisper("The following list contains all text commands you can use while not directly speaking to the zone controller. [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");
	plugin::Whisper("");
	plugin::Whisper("1. !initdata <zoneid>");
	plugin::Whisper("Info: Forces the zone controller to reload data from JSON. This command can be used from any zone as long as the target zone id's zone controller is popped.");
	plugin::Whisper("");
	plugin::Whisper("2. !repop <zoneid>");
	plugin::Whisper("Info: Forces the zone controller to repop all static named mobs. This command can be used from any zone as long as the target zone id's zone controller is popped.");
	plugin::Whisper("");
	plugin::Whisper("3. !depop <zoneid>");
	plugin::Whisper("Info: Forces the zone controller to depop all static named mobs. This command can be used from any zone as long as the target zone id's zone controller is popped.");
	plugin::Whisper("");
	plugin::Whisper("4. !reloadzone <zoneid>");
	plugin::Whisper("Info: Forces the zone controller to reload live decoded data. This command can be used from any zone as long as the target zone id's zone controller is popped.");
	plugin::Whisper("");
	plugin::Whisper("5. !remoteaddignore <mob name>");
	plugin::Whisper("Info: Add your current target to the ignore list for the current zone. Best when used in a macro such as: /say !remoteaddignore percentT (use percent symbol not word)");
	plugin::Whisper("");
	plugin::Whisper("6. !remoteadddepop <mob name>");
	plugin::Whisper("Info: Add your current target to the depop list for the current zone. Best when used in a macro such as: /say !remoteadddepop percentT (use percent symbol not word)");
	plugin::Whisper("");
	plugin::Whisper("7. !remoteaddcustomtypetrash <mob name>");
	plugin::Whisper("Info: Add your current target to the custom mob list, type trash, for the current zone. Best when used in a macro such as: /say !remoteaddcustomtypetrash percentT (use percent symbol not word)");
	plugin::Whisper("");
	plugin::Whisper("8. !remoteaddcustomtypeboss <mob name>");
	plugin::Whisper("Info: Add your current target to the custom mob list, type boss, for the current zone. Best when used in a macro such as: /say !remoteaddcustomtypeboss percentT (use percent symbol not word)");
	plugin::Whisper("");
	plugin::Whisper("9. !remoteaddcustomtyperaid <mob name>");
	plugin::Whisper("Info: Add your current target to the custom mob list, type raid, for the current zone. Best when used in a macro such as: /say !remoteaddcustomtyperaid percentT (use percent symbol not word)");
	plugin::Whisper("");
	plugin::Whisper("10. !remoteadditem <itemid OR itemid comma delimited string>");
	plugin::Whisper("Info: Add item id to the loot table. A comma delimited string can also be passed in to add multiple items at once.");
	plugin::Whisper("");
	plugin::Whisper("11. !remoteaddtable <table name OR table name comma delimited string>");
	plugin::Whisper("Info: Add a loot table. A comma delimited string can also be passed in to add multiple loot tables at once.");
	plugin::Whisper("");
	plugin::Whisper("12. !remotebatchassociation <table and item comma delimited string>");
	plugin::Whisper("Info: Batch add existing items to existing tables. A comma delimited string should be passed in the format: tablename, itemid, itemid, tablename2, itemid, itemid, etc.");
	plugin::Whisper("");
	plugin::Whisper("13. !remotesave");
	plugin::Whisper("Info: Save all changes to JSON permenantly. In order to reflect changes you should !reloadzone <zoneid> after using this command.");
	plugin::Whisper("");
	plugin::Whisper("14. !remoteupdatetimer <respawn timer in seconds>");
	plugin::Whisper("Info: Update the respawn timer of the spawngroup associated with your selected mob.");
	plugin::Whisper("");
	plugin::Whisper("15. !remoteupdatealltimer <respawn timer in seconds>");
	plugin::Whisper("Info: Update the respawn timer for all spawngroups associated with the name of your selected mob.");
	plugin::Whisper("");
	plugin::Whisper("16. !togglevis");
	plugin::Whisper("Info: Hides or unhides the zone controller.");
	plugin::Whisper("");
	plugin::Whisper("17. !showloot");
	plugin::Whisper("Info: Print all item varlinks in say channel.");
	plugin::Whisper("");
	plugin::Whisper("18. zcdiag");
	plugin::Whisper("Info: While hailing the zone controller, show runtime counters for spawn signals, reconciles, and buff/loot apply outcomes.");
	plugin::Whisper("");	
}

sub PRINT_IGNORED_MOB_LIST {
	my $mobCounter = 1;
	PRINT_DETAIL_HEADER("Info", "Ignored Mobs");
	plugin::Whisper("The following list contains all mobs that will be disregarded by the zone controller when buffing new mob spawns. [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");
	plugin::Whisper("");

	foreach my $mobName (@ignoreArray) {
		plugin::Whisper($mobCounter . ". " . $mobName . " [" . quest::saylink("removefromignored_" . $mobName, 1, "Remove") . "]");
		$mobCounter = $mobCounter + 1;
	}
	
	plugin::Whisper("");
	plugin::Whisper("[" . quest::saylink("viewignoredmobs", 1, "Refresh This View") . "] [" . quest::saylink("addnewignoremob#1", 1, "Add New Ignored Mob") . "]");
}

sub PRINT_DEPOP_MOB_LIST {
	my $mobCounter = 1;
	PRINT_DETAIL_HEADER("Info", "Depop Mobs");
	plugin::Whisper("The following list contains all mobs that will be depoped by the zone controller when buffing new mob spawns. [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");
	plugin::Whisper("");

	foreach my $mobName (@depopArray) {
		plugin::Whisper($mobCounter . ". " . $mobName . " [" . quest::saylink("removefromdepop_" . $mobName, 1, "Remove") . "]");
		$mobCounter = $mobCounter + 1;
	}
	
	plugin::Whisper("");
	plugin::Whisper("[" . quest::saylink("viewdepopmobs", 1, "Refresh This View") . "] [" . quest::saylink("addnewdepopmob#1", 1, "Add New Depop Mob") . "]");
}

sub PRINT_ALL_MOBS_WITH_LOOT_TABLE {
	my @lootTableID = split /_/, $_[0];
	my @allTypesArray = ("trash", "boss", "raid");
	my $mobsWithLootTableCounter = 1;

	PRINT_DETAIL_HEADER("Info", "Assigned Mobs");
	plugin::Whisper("The following mobs are assigned to loot table " . $lootTableID[1] . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");
	plugin::Whisper("");

	foreach my $mobName (@customMobArray) {
		my %customBuffHash = GET_CUSTOM_BUFF_HASH($mobName);
		for (my $i = 0; $i < @{$customBuffHash{loot}}; $i++) {
			if($customBuffHash{loot}[$i]{id} eq $lootTableID[1]) {
				plugin::Whisper($mobsWithLootTableCounter . ". " . $mobName . " [" . quest::saylink("vl_" . $mobName, 1, "View Loot Tables") . "]");
				$mobsWithLootTableCounter = $mobsWithLootTableCounter + 1;
			}
		}
	}

	foreach my $mobType (@allTypesArray) {
		my %typeBuffHash = GET_TYPE_BUFF_HASH($mobType);
		for (my $i = 0; $i < @{$typeBuffHash{loot}}; $i++) {
			if($typeBuffHash{loot}[$i]{id} eq $lootTableID[1]) {

				if($mobType eq "trash") {
					plugin::Whisper($mobsWithLootTableCounter . ". All Trash" . " [" . quest::saylink("vl_" . "TrashALL", 1, "View Loot Tables") . "]");
				} elsif($mobType eq "boss") {
					plugin::Whisper($mobsWithLootTableCounter . ". All Bosses" . " [" . quest::saylink("vl_" . "BossALL", 1, "View Loot Tables") . "]");
				} elsif($mobType eq "raid") {
					plugin::Whisper($mobsWithLootTableCounter . ". All Raid Bosses" . " [" . quest::saylink("vl_" . "RaidALL", 1, "View Loot Tables") . "]");
				}
				$mobsWithLootTableCounter = $mobsWithLootTableCounter + 1;
			}
		}
	}
}

sub PRINT_ALL_MOBS_WITH_LOOT_TABLE_PUBLIC {
	my @allTypesArray = ("trash", "boss", "raid");
	my $mobsWithLootTableCounter = 1;
	my $clientEntity = $entity_list->GetClientByName($npc->GetEntityVariable("message_target"));
	my $lootTableID = $npc->GetEntityVariable("table_target");

	PRINT_DETAIL_HEADER_PUBLIC("Info", "Assigned Mobs", $clientEntity);
	$clientEntity->Message(315, "The following mobs are assigned to loot table " . $lootTableID . ":");
	$clientEntity->Message(315, "");

	foreach my $mobName (@customMobArray) {
		my %customBuffHash = GET_CUSTOM_BUFF_HASH($mobName);
		for (my $i = 0; $i < @{$customBuffHash{loot}}; $i++) {
			if($customBuffHash{loot}[$i]{id} eq $lootTableID) {
				$clientEntity->Message(315, $mobsWithLootTableCounter . ". " . $mobName);
				$mobsWithLootTableCounter = $mobsWithLootTableCounter + 1;
			}
		}
	}

	foreach my $mobType (@allTypesArray) {
		my %typeBuffHash = GET_TYPE_BUFF_HASH($mobType);
		for (my $i = 0; $i < @{$typeBuffHash{loot}}; $i++) {
			if($typeBuffHash{loot}[$i]{id} eq $lootTableID) {

				if($mobType eq "trash") {
					$clientEntity->Message(315, $mobsWithLootTableCounter . ". All Trash");
				} elsif($mobType eq "boss") {
					$clientEntity->Message(315, $mobsWithLootTableCounter . ". All Bosses");
				} elsif($mobType eq "raid") {
					$clientEntity->Message(315, $mobsWithLootTableCounter . ". All Raid Bosses");
				}
				$mobsWithLootTableCounter = $mobsWithLootTableCounter + 1;
			}
		}
	}
}

sub PRINT_LOOT_TABLE {
	my @mobName = split /_/, $_[0];
	my $lootTableCounter = 1;
	my $mobType;
	my $mobNameReference = $mobName[1];

	if($mobName[1] eq "TrashALL") {
		$mobType = "trash";
		$mobName[1] = "trash";
	} elsif($mobName[1] eq "BossALL") {
		$mobType = "boss";
		$mobName[1] = "boss";
	} elsif($mobName[1] eq "RaidALL") {
		$mobType = "raid";
		$mobName[1] = "raid";
	} else {
		$mobType = GET_MOB_TYPE($mobName[1]);
	}

	my %globalLootTableHash = GET_GLOBAL_LOOT_HASH($mobType);
	my $customizedFlag = IS_CUSTOMIZED_MOB($mobName[1]);

	PRINT_DETAIL_HEADER("Info", "Associated Loot Tables");
	plugin::Whisper("The following loot table ids are assigned to " . $mobName[1] . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");

	plugin::Whisper("");
	plugin::Whisper("Global Loot Table(s) For Type: " . $mobType);
	foreach my $key (keys %globalLootTableHash) {
		plugin::Whisper($lootTableCounter . ". [" . quest::saylink("vtd_" . $key . "_0", 1, $key) . "] [" . quest::saylink("rlt_" . $key . "_" . $mobType, 1, "Remove Loot Table Assignment") . "]". " Rate: " . $globalLootTableHash{$key} . " percent [" . quest::saylink("dtlt_1_" . $key . "_" . $mobType, 1, "-") . "] [" . quest::saylink("itlt_1_" . $key . "_" . $mobType, 1, "+") . "]  ([" . quest::saylink("stlt_0_" . $key . "_" . $mobType, 1, "0") . "] [" . quest::saylink("stlt_25_" . $key . "_" . $mobType, 1, "25") . "] [" . quest::saylink("stlt_50_" . $key . "_" . $mobType, 1, "50") . "] [" . quest::saylink("stlt_100_" . $key . "_" . $mobType, 1, "100") . "] [" . quest::saylink("stlt_200_" . $key . "_" . $mobType, 1, "200") . "] [" . quest::saylink("stlt_300_" . $key . "_" . $mobType, 1, "300") . "] [" . quest::saylink("stlt_400_" . $key . "_" . $mobType, 1, "400") . "] [" . quest::saylink("stlt_500_" . $key . "_" . $mobType, 1, "500") . "] [" . quest::saylink("stlt_600_" . $key . "_" . $mobType, 1, "600") . "])");
		$lootTableCounter = $lootTableCounter + 1;
	}
	plugin::Whisper("");

	if($customizedFlag) {
		my %customLootTableHash = GET_CUSTOM_LOOT_HASH($mobName[1]);
		
		plugin::Whisper("Custom Loot Table(s) For: " . $mobName[1]);
		foreach my $key (keys %customLootTableHash) {
			plugin::Whisper($lootTableCounter . ". [" . quest::saylink("vtd_" . $key . "_0", 1, $key) . "] [" . quest::saylink("rct_" . $key . "_" . $mobName[1], 1, "Remove Loot Table Assignment") . "]" . " Rate: " . $customLootTableHash{$key} ." percent [" . quest::saylink("dclt_1_" . $key . "_" . $mobName[1], 1, "-") . "] [" . quest::saylink("iclt_1_" . $key . "_" . $mobName[1], 1, "+") . "]  ([" . quest::saylink("sclt_0_" . $key . "_" . $mobName[1], 1, "0") . "] [" . quest::saylink("sclt_25_" . $key . "_" . $mobName[1], 1, "25") . "] [" . quest::saylink("sclt_50_" . $key . "_" . $mobName[1], 1, "50") . "] [" . quest::saylink("sclt_100_" . $key . "_" . $mobName[1], 1, "100") . "] [" . quest::saylink("sclt_200_" . $key . "_" . $mobName[1], 1, "200") . "] [" . quest::saylink("sclt_300_" . $key . "_" . $mobName[1], 1, "300") . "] [" . quest::saylink("sclt_400_" . $key . "_" . $mobName[1], 1, "400") . "] [" . quest::saylink("sclt_500_" . $key . "_" . $mobName[1], 1, "500") . "] [" . quest::saylink("sclt_600_" . $key . "_" . $mobName[1], 1, "600") . "])");
			$lootTableCounter = $lootTableCounter + 1;
		}
		plugin::Whisper("");
	}

	if($customizedFlag) {
		plugin::Whisper("[" . quest::saylink("vl_" . $mobName[1], 1, "Refresh This View") . "] [" . quest::saylink("viewallmobs", 1, "View Mob List") . "] [" . quest::saylink("vco_" . $mobName[1] . "_" . $mobType, 1, "Assign A Custom Loot Table") . "]");
	} else {
		plugin::Whisper("[" . quest::saylink("vl_" . $mobNameReference, 1, "Refresh This View") . "] [" . quest::saylink("viewallmobs", 1, "View Mob List") . "] [" . quest::saylink("vto_" . $mobType, 1, "Assign A Global Loot Table") . "]");
	}
}

sub PRINT_ALL_LOOT_TABLES {
	my @lootTableArray = GET_ALL_LOOT_TABLE_IDS();
	my $lootTableCounter = 1;

	PRINT_DETAIL_HEADER("Info", "All Loot Tables");
	plugin::Whisper("The following loot table ids are assigned to zone " . $zoneid . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");
	plugin::Whisper("");

	@lootTableArray = sort @lootTableArray;

	foreach my $id (@lootTableArray) {
		plugin::Whisper($lootTableCounter . ". [" . quest::saylink("vtd_" . $id . "_0", 1, $id) . "] [" . quest::saylink("removeloottable_" . $id, 1, "Remove") . "] " . GET_LOOT_TABLE_ITEM_COUNT_STATUS($id) . " " . GET_ORPHANED_LOOT_TABLE_STATUS($id));
		$lootTableCounter = $lootTableCounter + 1;
	}
	
	plugin::Whisper("");
	plugin::Whisper("[" . quest::saylink("viewallloottables" . $mobNameReference, 1, "Refresh This View") . "] [" . quest::saylink("saynewloottableinfo", 1, "Create New Loot Table") . "]");
}

sub PRINT_NEW_CUSTOM_MOB_TYPE_SELECTION {
	my @mobTypeArray = ("trash", "boss", "raid");
	my $newCustomTypeCounter = 1;

	PRINT_DETAIL_HEADER("Action", "Select Mob Type");
	plugin::Whisper("Select a base type for the new custom mob: [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");

	foreach my $type (@mobTypeArray) {
		plugin::Whisper($newCustomTypeCounter . ". " . $type . " [" . quest::saylink("setnewcustommobtype#" . $type, 1, "+") . "]");
		$newCustomTypeCounter = $newCustomTypeCounter + 1;
	}

	plugin::Whisper("");
	plugin::Whisper("[" . quest::saylink("viewallmobs", 1, "Cancel And View Mob List") . "]");
}

sub PRINT_ALL_LOOT_TABLES_WITH_NO_ASSOCIATION_TO_ITEM_NAME {
	my @itemName = split /_/, $_[0];
	my %lootTableHash = GET_LOOT_TABLE_HASH();
	my $lootTableCounter = 1;

	PRINT_DETAIL_HEADER("Info", "Available Loot Tables");
	plugin::Whisper("The following loot table ids can be assigned to item " . $itemName[1] . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");

	foreach my $key (keys %lootTableHash) {
		if (!grep{$_->{name} eq $itemName[1]} @{$lootTableHash{$key}}) {
			plugin::Whisper($lootTableCounter . ". [" . quest::saylink("vtd_" . $key . "_0", 1, $key) . "] [" . quest::saylink("ali_" . $key . "_" . $itemName[1], 1, "+") . "]");
			$lootTableCounter = $lootTableCounter + 1;
		}
	}

	plugin::Whisper("");
	plugin::Whisper("[" . quest::saylink("displaytablesthatcanbeassociated_" . $itemName[1], 1, "Refresh This View") . "] [" . quest::saylink("viewitemdata_" . $itemName[1], 1, "Back To Item Details") . "]");
}

sub PRINT_ALL_LOOT_TABLES_AVAILABLE_FOR_CUSTOM_ASSIGNMENT {
	my @mobNameArray = split /_/, $_[0];
	my %lootTableHash = GET_LOOT_TABLE_HASH();
	my %customBuffHash = GET_CUSTOM_BUFF_HASH($mobNameArray[1]);
	my %typeBuffHash = GET_TYPE_BUFF_HASH($mobNameArray[2]);
	my @customBuffHashArray = @{$customBuffHash{loot}};
	my @typeBuffHashArray = @{$typeBuffHash{loot}};
	my $lootTableForCustomAssignmentCounter = 1;

	PRINT_DETAIL_HEADER("Info", "Assignable Loot Tables");
	plugin::Whisper("The following loot table ids are available to be assigned to mob " . $mobNameArray[1] . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");

	foreach my $key (sort keys %lootTableHash) {
		if (!grep{$_->{id} eq $key} @customBuffHashArray) {
			if (!grep{$_->{id} eq $key} @typeBuffHashArray) {
				plugin::Whisper($lootTableForCustomAssignmentCounter . ". [" . quest::saylink("vtd_" . $key . "_0", 1, $key) . "] [" . quest::saylink("cl_" . $key . "_" . $mobNameArray[1], 1, "+") . "]");
				$lootTableForCustomAssignmentCounter = $lootTableForCustomAssignmentCounter + 1;
			}
		}	
	}

	plugin::Whisper("");
	plugin::Whisper("[" . quest::saylink("vl_" . $mobNameArray[1], 1, "Back To Loot Tables") . "] [" . quest::saylink("viewallmobs", 1, "View Mob List") . "]");
}

sub PRINT_ALL_LOOT_TABLES_AVAILABLE_FOR_TYPE_ASSIGNMENT {
	my @mobTypeArray = split /_/, $_[0];
	my %lootTableHash = GET_LOOT_TABLE_HASH();
	my %typeBuffHash = GET_TYPE_BUFF_HASH($mobTypeArray[1]);
	my @typeBuffHashArray = @{$typeBuffHash{loot}};
	my $lootTableForTypeAssignmentCounter = 1;

	PRINT_DETAIL_HEADER("Info", "Assignable Loot Tables");
	plugin::Whisper("The following loot table ids are available to be assigned to mob type " . $mobTypeArray[1] . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");

	foreach my $key (sort keys %lootTableHash) {
		if (!grep{$_->{id} eq $key} @typeBuffHashArray) {
			plugin::Whisper($lootTableForTypeAssignmentCounter . ". [" . quest::saylink("vtd_" . $key . "_0", 1, $key) . "] [" . quest::saylink("atts_" . $key . "_" . $mobTypeArray[1], 1, "+") . "]");
			$lootTableForTypeAssignmentCounter = $lootTableForTypeAssignmentCounter + 1;
		}	
	}

	plugin::Whisper("");

	if($mobTypeArray[1] eq "trash") {
		plugin::Whisper("[" . quest::saylink("vl_TrashALL", 1, "Back To Loot Tables") . "]");
	} elsif($mobTypeArray[1] eq "boss") {
		plugin::Whisper("[" . quest::saylink("vl_BossALL", 1, "Back To Loot Tables") . "]");
	} elsif($mobTypeArray[1] eq "raid") {
		plugin::Whisper("[" . quest::saylink("vl_RaidALL", 1, "Back To Loot Tables") . "]");
	}
}

sub PRINT_ALL_LOOT_TABLES_WITH_ITEM_NAME {
	my @itemName = split /_/, $_[0];
	my %lootTableHash = GET_LOOT_TABLE_HASH();
	my $lootTableWithItemNameCounter = 1;

	PRINT_DETAIL_HEADER("Info", "Assigned Loot Tables");
	plugin::Whisper("The following loot table ids are assigned to item " . $itemName[1] . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");
	plugin::Whisper("");

	foreach my $key (keys %lootTableHash) {
		for (my $i = 0; $i < @{$lootTableHash{$key}}; $i++) {
			if($lootTableHash{$key}[$i]{name} eq $itemName[1]) {
				plugin::Whisper($lootTableWithItemNameCounter . ". [" . quest::saylink("vtd_" . $key . "_0", 1, $key) . "] [" . quest::saylink("removeloottable_" . $key, 1, "Remove") . "]");
				$lootTableWithItemNameCounter = $lootTableWithItemNameCounter + 1;
			}
		}
	}
}

sub PRINT_ALL_LOOT_DROPS {
	my @lootListParams = split /_/, $_[0];
	PRINT_ALL_LOOT_DROPS_AS_PAGED_LIST($lootListParams[1], $lootListParams[2]);
}

sub PRINT_ALL_LOOT_DROPS_AS_PAGED_LIST {
	my $listIndex = $_[0];
	my $pageAmount = 15;
	my @allLootTableIDsArray = GET_ALL_LOOT_TABLE_IDS();
	my $lootTableItemCounter = 1;
	my @allLootDropsArray = ();
	my @splicedItemNames = ();

	PRINT_DETAIL_HEADER("Info", "All Items");
	plugin::Whisper("The following items are assigned to zone " . $zoneid . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");

	my %itemHash = GET_ITEM_HASH();
	foreach my $itemName (keys %itemHash) {
		if($itemName ne "") {
			if (!grep{$_ eq $itemName} @allLootDropsArray) {
				push @allLootDropsArray, $itemName;
			}
		}
	}
	
	plugin::Whisper("");
	plugin::Whisper("Item count: " . @allLootDropsArray . " [" . quest::saylink("addnewitemtozone", 1, "Add New Item") . "] [" . quest::saylink("removeallitemsfromitemtable", 1, "Remove All Items") . "] [" . quest::saylink("viewalllootdrops_0", 1, "Refresh This View") . "]");
	plugin::Whisper("");

	@allLootDropsArraySorted = sort @allLootDropsArray;
	@splicedItemNames = splice @allLootDropsArraySorted, ($pageAmount * $listIndex), $pageAmount;

	foreach my $splicedItemName (@splicedItemNames) {
		plugin::Whisper((($pageAmount * $listIndex) + $lootTableItemCounter) . ". " . quest::varlink(GET_ITEM_ID_BY_ITEM_NAME($splicedItemName)) . " (" . GET_ITEM_ID_BY_ITEM_NAME($splicedItemName) . ") " . " [" . quest::saylink("removeitembyname_" . $splicedItemName, 1, "-") . "] [" . quest::saylink("viewitemdata_" . $splicedItemName, 1, "...") . "]");
		$lootTableItemCounter = $lootTableItemCounter + 1;
	}

	plugin::Whisper("");
	
	if($listIndex != 0) {
		if(@allLootDropsArray > ($listIndex * $pageAmount) && @splicedItemNames == 15) {
			if((@allLootDropsArray - ($listIndex * $pageAmount)) > 0) {
				plugin::Whisper("[" . quest::saylink("viewalllootdrops_" . ($listIndex - 1), 1, "Previous") . "] [" . quest::saylink("viewalllootdrops_" . ($listIndex + 1), 1, "Next") . "]");
			} else {
				$endPageAmount = @allLootDropsArray - ($listIndex * $pageAmount);
				plugin::Whisper("[" . quest::saylink("viewalllootdrops_" . ($listIndex - 1), 1, "Previous") . "]");
			}
		} else {
			plugin::Whisper("[" . quest::saylink("viewalllootdrops_" . ($listIndex - 1), 1, "Previous") . "]");
		}
	} else {
		if(@allLootDropsArray > $pageAmount) {
			plugin::Whisper("[" . quest::saylink("viewalllootdrops_" . ($listIndex + 1), 1, "Next") . "]");
		}
	}
}

sub PRINT_ALL_LOOT_DROPS_AS_PAGED_LIST_PUBLIC {
	my $listIndex = $_[0];
	my $pageAmount = 15;
	my @allLootTableIDsArray = GET_ALL_LOOT_TABLE_IDS();
	my %lootTableHash = GET_LOOT_TABLE_HASH();
	my $lootTableItemCounter = 1;
	my @allLootDropsArray = ();
	my @splicedItemNames = ();
	my $printSpamBlockerKey = $zoneid . "_Is_Waiting_To_Be_Available";
	my $printSpamBlocker = plugin::TSSGetRaw($printSpamBlockerKey);
	my $clientEntity = $entity_list->GetClientByName($npc->GetEntityVariable("message_target"));

	if(!$printSpamBlocker) {
		PRINT_DETAIL_HEADER_PUBLIC("Info", "All Items", $clientEntity);

		my %itemHash = GET_ITEM_HASH();
		foreach my $itemName (keys %itemHash) {
			if($itemName ne "") {
				if (!grep{$_ eq $itemName} @allLootDropsArray) {
					push @allLootDropsArray, $itemName;
				}
			}
		}

		@allLootDropsArraySorted = sort @allLootDropsArray;

		foreach my $itemName (@allLootDropsArraySorted) {
			my $allTablesString;

			foreach my $key (sort keys %lootTableHash) {
				for (my $i = 0; $i < @{$lootTableHash{$key}}; $i++) {
					if($lootTableHash{$key}[$i]{name} eq $itemName) {
						if($allTablesString ne "") {
							$allTablesString = $allTablesString . " [" . quest::saylink("showassociatedmobs_" . $key . "_" . $npc->GetEntityVariable("message_target"), 1, $key) . "]";
						} else {
							$allTablesString = " [" . quest::saylink("showassociatedmobs_" . $key . "_" . $npc->GetEntityVariable("message_target"), 1, $key) . "]";
						}
					}
				}
			}
			$clientEntity->Message(315, (($pageAmount * $listIndex) + $lootTableItemCounter) . ". " . quest::varlink(GET_ITEM_ID_BY_ITEM_NAME($itemName)) . " Loot Table: " . $allTablesString);
			$lootTableItemCounter = $lootTableItemCounter + 1;
		}


		$clientEntity->Message(315, "");
		plugin::TSSSetRaw($printSpamBlockerKey, 1, 5);
	} else {
		$clientEntity->Message(315, "You must wait five seconds between querying the zone loot list.");
	}
}

sub PRINT_ALL_LOOT_DROPS_AS_PAGED_LIST_PRIVATE {
	my $listIndex = $_[0];
	my $pageAmount = 15;
	my @allLootTableIDsArray = GET_ALL_LOOT_TABLE_IDS();
	my %lootTableHash = GET_LOOT_TABLE_HASH();
	my $lootTableItemCounter = 1;
	my @allLootDropsArray = ();
	my @splicedItemNames = ();
	my $printSpamBlockerKey = $zoneid . "_Is_Waiting_To_Be_Available_Private";
	my $printSpamBlocker = plugin::TSSGetRaw($printSpamBlockerKey);

	if(!$printSpamBlocker) {
		PRINT_DETAIL_HEADER("Info", "All Items (GM Mode)");

		my %itemHash = GET_ITEM_HASH();
		foreach my $itemName (keys %itemHash) {
			if($itemName ne "") {
				if (!grep{$_ eq $itemName} @allLootDropsArray) {
					push @allLootDropsArray, $itemName;
				}
			}
		}
		
		quest::say("");
		quest::say("Item count: " . @allLootDropsArray);
		quest::say("");

		@allLootDropsArraySorted = sort @allLootDropsArray;

		foreach my $itemName (@allLootDropsArraySorted) {
			my $allTablesString;

			foreach my $key (keys %lootTableHash) {
				for (my $i = 0; $i < @{$lootTableHash{$key}}; $i++) {
					if($lootTableHash{$key}[$i]{name} eq $itemName) {
						if($allTablesString ne "") {
							$allTablesString = $allTablesString . ", " . $key;
						} else {
							$allTablesString = $key;
						}
					}
				}
			}

			quest::say((($pageAmount * $listIndex) + $lootTableItemCounter) . ". " . quest::varlink(GET_ITEM_ID_BY_ITEM_NAME($itemName)) . "[" . quest::saylink("!summonloot#" . GET_ITEM_ID_BY_ITEM_NAME($itemName), 1, "+") . "] (Loot Table(s): " . $allTablesString . ")");
			$lootTableItemCounter = $lootTableItemCounter + 1;
		}

		quest::say("");
		plugin::TSSSetRaw($printSpamBlockerKey, 1, 5);
	} else {
		quest::say("I can only display the loot list once every 5 seconds. Please try again in a few moments.");
	}
}

sub PRINT_ALL_DB_MOBS_AS_PAGED_LIST {
	my @listParams = split /_/, $_[0];
	my $listIndex = $listParams[1];
	my $pageAmount = 15;
	my $mobCounter = 1;

	PRINT_DETAIL_HEADER("Info", "All Mobs In DB");
	plugin::Whisper("The following mobs exist in the database for zone " . $zoneid . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");

	my @mobArray = @dbMobArray;
	
	plugin::Whisper("");
	plugin::Whisper("Mob count: " . @mobArray . " [" . quest::saylink("batchaddncustommobs_0", 1, "Refresh This View") . "] [" . quest::saylink("viewallmobs", 1, "View Mob List") . "]");
	plugin::Whisper("");

	my @splicedMobNames = splice @mobArray, ($pageAmount * $listIndex), $pageAmount;

	foreach my $splicedMobName (@splicedMobNames) {
		plugin::Whisper((($pageAmount * $listIndex) + $mobCounter) . ". " . $splicedMobName . " [" . quest::saylink("dbad_" . $splicedMobName . "_trash", 1, "Trash") . "] [" . quest::saylink("dbad_" . $splicedMobName . "_boss", 1, "Boss") . "] [" . quest::saylink("dbad_" . $splicedMobName . "_raid", 1, "Raid") . "]");
		$mobCounter = $mobCounter + 1;
	}

	plugin::Whisper("");
	
	if($listIndex != 0) {
		if(@mobArray > ($listIndex * $pageAmount) && @splicedMobNames == 15) {
			if((@mobArray - ($listIndex * $pageAmount)) > 0) {
				plugin::Whisper("[" . quest::saylink("batchaddncustommobs_" . ($listIndex - 1), 1, "Previous") . "] [" . quest::saylink("batchaddncustommobs_" . ($listIndex + 1), 1, "Next") . "]");
			} else {
				$endPageAmount = @mobArray - ($listIndex * $pageAmount);
				plugin::Whisper("[" . quest::saylink("batchaddncustommobs_" . ($listIndex - 1), 1, "Previous") . "]");
			}
		} else {
			plugin::Whisper("[" . quest::saylink("batchaddncustommobs_" . ($listIndex - 1), 1, "Previous") . "]");
		}
	} else {
		if(@mobArray > $pageAmount) {
			plugin::Whisper("[" . quest::saylink("batchaddncustommobs_" . ($listIndex + 1), 1, "Next") . "]");
		}
	}
}

sub PRINT_LOOT_TABLE_ITEMS_FOR_QUICK_TABLE_ASSOCIATION {
	my @lootTableID = split /_/, $_[0];
	my $listIndex = $lootTableID[2];
	my $pageAmount = 15;
	my @allLootTableIDsArray = GET_ALL_LOOT_TABLE_IDS();
	my $lootTableItemCounter = 1;
	my @allLootDropsArray = ();
	my @splicedItemNames = ();

	PRINT_DETAIL_HEADER("Info", "Quick Add Items");
	plugin::Whisper("Assign items to loot table " . $lootTableID[1] . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");
	plugin::Whisper("");

	my %itemHash = GET_ITEM_HASH();
	foreach my $itemName (keys %itemHash) {
		if($itemName ne "") {
			if (!grep{$_ eq $itemName} @allLootDropsArray) {
				push @allLootDropsArray, $itemName;
			}
		}
	}

	plugin::Whisper("");
	plugin::Whisper("Item count: " . @allLootDropsArray . " [" . quest::saylink("vtd_" . $lootTableID[1] . "_0", 1, "Back To Table View") . "] [" . quest::saylink("viewallloottables", 1, "View All Loot Tables") . "]");
	plugin::Whisper("");

	@allLootDropsArraySorted = sort @allLootDropsArray;
	@splicedItemNames = splice @allLootDropsArraySorted, ($pageAmount * $listIndex), $pageAmount;

	foreach my $splicedItemName (@splicedItemNames) {
		plugin::Whisper((($pageAmount * $listIndex) + $lootTableItemCounter) . ". " . quest::varlink(GET_ITEM_ID_BY_ITEM_NAME($splicedItemName)) . " (" . GET_ITEM_ID_BY_ITEM_NAME($splicedItemName) .")" . " [" . quest::saylink("ali_" . $lootTableID[1] . "_" . $splicedItemName, 1, "+") . "]");
		$lootTableItemCounter = $lootTableItemCounter + 1;
	}

	plugin::Whisper("");
	
	if($listIndex != 0) {
		if(@allLootDropsArray > ($listIndex * $pageAmount) && @splicedItemNames == 15) {
			if((@allLootDropsArray - ($listIndex * $pageAmount)) > 0) {
				plugin::Whisper("[" . quest::saylink("quickadditems_" . $lootTableID[1] . "_" . ($listIndex - 1), 1, "Previous") . "] [" . quest::saylink("quickadditems_" . $lootTableID[1] . "_" . ($listIndex + 1), 1, "Next") . "]");
			} else { 
				$endPageAmount = @allLootDropsArray - ($listIndex * $pageAmount);
				plugin::Whisper("[" . quest::saylink("quickadditems_" . $lootTableID[1] . "_" . ($listIndex - 1), 1, "Previous") . "]");
			}
		} else {
			plugin::Whisper("[" . quest::saylink("quickadditems_" . $lootTableID[1] . "_" . ($listIndex - 1), 1, "Previous") . "]");
		}
	} else {
		if(@allLootDropsArray > $pageAmount) {
			plugin::Whisper("[" . quest::saylink("quickadditems_" . $lootTableID[1] . "_" . ($listIndex + 1), 1, "Next") . "]");
		}
	}
}

sub PRINT_LOOT_TABLE_ITEMS_AS_PAGED_LIST {
	my @lootTableID = split /_/, $_[0];
	my $pageAmount = 15;
	my $listIndex = $lootTableID[2];
	my %lootTableHash = GET_LOOT_TABLE_HASH();
	my $lootTableItemCounter = 1;
	my @allLootDropsArray = ();
	my @splicedItemNames = ();

	PRINT_DETAIL_HEADER("Info", "Loot Table Items");
	plugin::Whisper("The following items are assigned to loot table id " . $lootTableID[1] . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");

	for (my $i = 0; $i < @{$lootTableHash{$lootTableID[1]}}; $i++) {
		$itemName = $lootTableHash{$lootTableID[1]}[$i]{name};
		push @allLootDropsArray, $itemName;
	}

	plugin::Whisper("");
	plugin::Whisper("Item count: " . @allLootDropsArray . " [" . quest::saylink("vtd_" . $lootTableID[1] . "_0", 1, "Refresh This View") . "] [" . quest::saylink("viewmobsbyloottable_" . $lootTableID[1], 1, "View All Associated Mobs") . "]  [" . quest::saylink("viewallloottables", 1, "View All Loot Tables") . "]");
	plugin::Whisper("Bulk operations: [" . quest::saylink("quickadditems_" . $lootTableID[1] . "_0" , 1, "Quick Add Items") . "] [" . quest::saylink("assignallitemstoloottable_" . $lootTableID[1], 1, "Assign All Items To This Table") . "] [" . quest::saylink("removeallitemsfromloottable_" . $lootTableID[1], 1, "Remove All Items From This Table") . "]");
	plugin::Whisper("");

	@allLootDropsArraySorted = sort @allLootDropsArray;
	@splicedItemNames = splice @allLootDropsArraySorted, ($pageAmount * $listIndex), $pageAmount;

	foreach my $splicedItemName (@splicedItemNames) {
		plugin::Whisper((($pageAmount * $listIndex) + $lootTableItemCounter) . ". " . quest::varlink(GET_ITEM_ID_BY_ITEM_NAME($splicedItemName)) . " [" . quest::saylink("removeitemdata_" . $splicedItemName . "_" . $lootTableID[1] . "_" . $i, 1, "-") . "] [" . quest::saylink("viewitemdata_" . $splicedItemName, 1, "...") . "]");
		$lootTableItemCounter = $lootTableItemCounter + 1;
	}

	plugin::Whisper("");

	if($listIndex != 0) {
		if(@allLootDropsArray > ($listIndex * $pageAmount) && @splicedItemNames == 15) {
			if((@allLootDropsArray - ($listIndex * $pageAmount)) > 0) {
				plugin::Whisper("[" . quest::saylink("vtd_" . $lootTableID[1] . "_" . ($listIndex - 1), 1, "Previous") . "] [" . quest::saylink("vtd_" . $lootTableID[1] . "_"  . ($listIndex + 1), 1, "Next") . "]");
			} else {
				$endPageAmount = @allLootDropsArray - ($listIndex * $pageAmount);
				plugin::Whisper("[" . quest::saylink("vtd_" . $lootTableID[1] . "_"  . ($listIndex - 1), 1, "Previous") . "]");
			}
		} else {
			plugin::Whisper("[" . quest::saylink("vtd_" . $lootTableID[1] . "_"  . ($listIndex - 1), 1, "Previous") . "]");
		}
	} else {
		if(@allLootDropsArray > $pageAmount) {
			plugin::Whisper("[" . quest::saylink("vtd_" . $lootTableID[1] . "_"  . ($listIndex + 1), 1, "Next") . "]");
		}
	}
}

sub PRINT_LOOT_TABLE_ITEM_DETAILS {
	my @lootTableItemDetails = split /_/, $_[0];
	my $lootTableItemNameCounter = 1;
	my %lootTableHash = GET_ITEM_HASH_BY_ITEM_NAME($lootTableItemDetails[1]);

	PRINT_DETAIL_HEADER("Info", "Item Details");
	plugin::Whisper("The following details are assigned to item " . $lootTableItemDetails[1] . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");
	plugin::Whisper("");

	foreach my $key (keys %lootTableHash) {
		if($key ne "name") {
			plugin::Whisper($lootTableItemNameCounter . ". " . $key . ": " . $lootTableHash{$key} . " [" . quest::saylink("sayitemdetails#" . $lootTableItemDetails[1] . "#" . $key, 1, "Edit") . "]");
			$lootTableItemNameCounter = $lootTableItemNameCounter + 1;
		}
	}

	plugin::Whisper(" ");
	plugin::Whisper("[" . quest::saylink("removeitemfromalltables_" . $lootTableItemDetails[1], 1, "Remove From All Loot Tables") . "] [" . quest::saylink("viewallassociatedtables_" . $lootTableItemDetails[1], 1, "View All Assigned Loot Tables") . "] [" . quest::saylink("displaytablesthatcanbeassociated_" . $lootTableItemDetails[1], 1, "Assign To Loot Tables") . "] [" . quest::saylink("viewalllootdrops_0", 1, "View All Items") . "]");
}

sub PRINT_TYPE_BUFF_HASH {
	my @mobName = split /_/, $_[0];
	my @booleanTypeBuffs = ("see_improved_hide", "see_invis", "see_hide");
	my @integerTypeBuffs = ("attack_speed", 'atk', "fr", "mr", "slow_mitigation", "str", "aggro", "dr", "dex", "ac", "level", "pr", "accuracy", "assist", "cr", "size");
	my @bigIntegerTypeBuffs = ("min_hit", "max_hp", "max_hit", "cash");
	my @alphaTypeBuffs = ("special_attacks", "special_abilities");
	my $mobType;

	if($mobName[1] eq "TrashALL") {
		$mobType = "trash";
	} elsif($mobName[1] eq "BossALL") {
		$mobType = "boss";
	} elsif($mobName[1] eq "RaidALL") {
		$mobType = "raid";
	} else {
		$mobType = GET_MOB_TYPE($mobName[1]);
	}
	
	my $typeBuffCounter = 1;
	my %typeBuffHash = GET_TYPE_BUFF_HASH($mobType);

	PRINT_DETAIL_HEADER("Info", "Mob Type Stats");
	plugin::Whisper("The following stats are assigned to the mob type " . $mobType . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");
	plugin::Whisper("");

	foreach my $key (sort keys %typeBuffHash) {
		if($key ne "loot") {
			if (grep{$_ eq $key} @booleanTypeBuffs) {
				plugin::Whisper($typeBuffCounter . ". " . $key . ": " . $typeBuffHash{$key} . " [" . quest::saylink("togglemobstat#" . $key . "#" . $mobType . "#-1", 1, "Disable") . "] [" . quest::saylink("togglemobstat#" . $key . "#" . $mobType . "#1", 1, "On") . "] [" . quest::saylink("togglemobstat#" . $key . "#" . $mobType . "#0", 1, "Off") . "]");
			} elsif(grep{$_ eq $key} @integerTypeBuffs) {
				plugin::Whisper($typeBuffCounter . ". " . $key . ": " . $typeBuffHash{$key} . " [" . quest::saylink("ams#" . $key . "#" . $mobType . "#-1", 1, "Disable") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#0", 1, "0") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#1", 1, "+1") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#10", 1, "+10") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#25", 1, "+25") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#100", 1, "+100") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#1000", 1, "+1000") . "]");
			} elsif(grep{$_ eq $key} @bigIntegerTypeBuffs) {
				plugin::Whisper($typeBuffCounter . ". " . $key . ": " . $typeBuffHash{$key} . " [" . quest::saylink("ams#" . $key . "#" . $mobType . "#-1", 1, "Disable") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#0", 1, "0") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#1", 1, "+1") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#10", 1, "+10") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#100", 1, "+100") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#1000", 1, "+1,000") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#10000", 1, "+10,000") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#100000", 1, "+100,000") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#1000000", 1, "+1,000,000") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#10000000", 1, "+10,000,000") . "] [" . quest::saylink("ams#" . $key . "#" . $mobType . "#100000000", 1, "+100,000,000") . "]");
			} elsif(grep{$_ eq $key} @alphaTypeBuffs) {
				plugin::Whisper($typeBuffCounter . ". " . $key . ": " . $typeBuffHash{$key} . " [" . quest::saylink("saymobstat#" . $key . "#" . $mobType, 1, "Edit") . "]");
			}

			$typeBuffCounter = $typeBuffCounter + 1;
		}
	}

	plugin::Whisper("");
	plugin::Whisper("[" . quest::saylink("vts_" . $mobName[1], 1, "Refresh This View") . "] [" . quest::saylink("viewallmobs", 1, "View Mob List") . "]");
}

sub PRINT_CUSTOM_BUFF_HASH {
	my @mobName = split /_/, $_[0];
	my @booleanTypeBuffs = ("static", "see_invis_override");
	my @integerTypeBuffs = ("slow_mitigation_override", "assist_mod", "aggro_mod", "level_mod", "attack_speed_mod");
	my @bigIntegerTypeBuffs = ("min_hit_mod", "max_hp_mod", "max_hit_mod", "cash_override");
	my @alphaTypeBuffs = ("type", "special_abilities_override", "special_attacks_override", "mobid");
	my @singleDigitTypeBuffs = ("size_mod");
	my $customBuffCounter = 1;
	my %customBuffHash = GET_CUSTOM_BUFF_HASH($mobName[1]);
	my $mobType = GET_MOB_TYPE($mobName[1]);

	PRINT_DETAIL_HEADER("Info", "Custom Mob Stats");
	plugin::Whisper("The following stat modifiers are assigned to the mob named " . $mobName[1] . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");
	plugin::Whisper("");

	foreach my $key (sort keys %customBuffHash) {
		if($key ne "loot") {
			if (grep{$_ eq $key} @booleanTypeBuffs) {
				plugin::Whisper($customBuffCounter . ". " . $key . ": " . $customBuffHash{$key} . " [" . quest::saylink("togglecustommobstat#" . $key . "#" . $mobName[1] . "#-1", 1, "Disable") . "] [" . quest::saylink("togglecustommobstat#" . $key . "#" . $mobName[1] . "#1", 1, "On") . "] [" . quest::saylink("togglecustommobstat#" . $key . "#" . $mobName[1] . "#0", 1, "Off") . "]");
			} elsif(grep{$_ eq $key} @integerTypeBuffs) {
				plugin::Whisper($customBuffCounter . ". " . $key . ": " . $customBuffHash{$key} . " [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#-1", 1, "Disable") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#0", 1, "0") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#1", 1, "+1") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#10", 1, "+10") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#25", 1, "+25") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#100", 1, "+100") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#1000", 1, "+1000") . "]");
			} elsif(grep{$_ eq $key} @bigIntegerTypeBuffs) {
				plugin::Whisper($customBuffCounter . ". " . $key . ": " . $customBuffHash{$key} . " [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#-1", 1, "Disable") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#0", 1, "0") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#1", 1, "+1") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#10", 1, "+10") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#100", 1, "+100") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#1000", 1, "+1,000") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#10000", 1, "+10,000") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#100000", 1, "+100,000") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#1000000", 1, "+1,000,000") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#10000000", 1, "+10,000,000") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#100000000", 1, "+100,000,000") . "]");
			} elsif(grep{$_ eq $key} @singleDigitTypeBuffs) {
				plugin::Whisper($customBuffCounter . ". " . $key . ": " . $customBuffHash{$key} . " [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#-1", 1, "Disable") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#0", 1, "0") . "] [" . quest::saylink("acs#" . $key . "#" . $mobName[1] . "#1", 1, "+1") . "] [" . quest::saylink("rcs#" . $key . "#" . $mobName[1] . "#REDUCE#" . $mobType, 1, "-1") . "]");
			} elsif(grep{$_ eq $key} @alphaTypeBuffs) {
				plugin::Whisper($customBuffCounter . ". " . $key . ": " . $customBuffHash{$key} . " [" . quest::saylink("saycustommobstat#" . $key . "#" . $mobName[1], 1, "Edit") . "]");
			}

			$customBuffCounter = $customBuffCounter + 1;
		}
	}

	plugin::Whisper("");
	plugin::Whisper("[" . quest::saylink("vcs_" . $mobName[1], 1, "Refresh This View") . "] [" . quest::saylink("vfs_" . $mobName[1], 1, "View Stats") . "] [" . quest::saylink("vts_" . $mobName[1], 1, "View Base Type Stats") . "] [" . quest::saylink("viewallmobs", 1, "View Mob List") . "]");
}

sub PRINT_BUFF_HASH {
	my @mobName = split /_/, $_[0];
	my $mobType = GET_MOB_TYPE($mobName[1]);
	my $buffCounter = 1;
	my %buffHash = GET_BUFF_HASH($mobType, $mobName[1]);

	PRINT_DETAIL_HEADER("Info", "Mob Stats");
	plugin::Whisper("The following stats are assigned to the mob named " . $mobName[1] . ": [" . quest::saylink("viewquickactions", 1, GET_UNICODE_MENU_ICON()) . "] [" . quest::saylink("saveallchanges", 1, GET_UNICODE_CHECKMARK_ICON()) . "] [" . quest::saylink("refreshzonedata", 1, GET_UNICODE_UP_ICON()) . "] [" . quest::saylink("rebuffzone", 1, GET_UNICODE_RELOAD_ICON()) . "]");
	plugin::Whisper("");

	foreach my $key (sort keys %buffHash) {
		if($key ne "loot") {
			plugin::Whisper($buffCounter . ". " . $key . ": " . $buffHash{$key});
			$buffCounter = $buffCounter + 1;
		}
	}

	plugin::Whisper("");
	plugin::Whisper("[" . quest::saylink("vts_" . $mobName[1], 1, "View Base Type Stats") . "] [" . quest::saylink("vcs_" . $mobName[1], 1, "View Custom Stat Modifiers") . "] [" . quest::saylink("viewallmobs", 1, "View Mob List") . "]");
}

sub PRINT_ZONE_INFO {
	my %zoneInfoHash = GET_ZONE_INFO_HASH();
	my $zoneInfoCounter = 1;

	PRINT_DETAIL_HEADER("Info", "Zone");

	foreach my $key (sort keys %zoneInfoHash) {
		if($key eq "name") {
			plugin::Whisper($zoneInfoCounter . ". " . $key . ": " . $zoneln);
		} else {
			plugin::Whisper($zoneInfoCounter . ". " . $key . ": " . $zoneInfoHash{$key} . " [" . quest::saylink("sayzoneinfo#" . $key, 1, "Edit") . "]");
		}
		$zoneInfoCounter = $zoneInfoCounter + 1;
	}
}

sub PRINT_HEADER {
	plugin::Whisper(" ");
	plugin::Whisper("- - - - - - - - - - - - - - - - - - - - - - - - - - - - Quick Actions - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -");
	plugin::Whisper("[" . quest::saylink("viewallmobs", 1, "View Mob List") . "] [" . quest::saylink("viewallloottables", 1, "View All Loot Tables") . "] [" . quest::saylink("viewalllootdrops_0", 1, "View All Items") . "] [" . quest::saylink("applyallchanges", 1, "Apply Updates") . "] [" . quest::saylink("resetallchanges", 1, "Reset Updates") . "]");
	plugin::Whisper("[" . quest::saylink("saveallchanges", 1, "Save Updates") . "] [" . quest::saylink("repopallstaticbosses", 1, "Repop Bosses") . "] [" . quest::saylink("depopallstaticbosses", 1, "Depop Bosses") . "] [" . quest::saylink("rebuffzone", 1, "Rebuff Zone") . "] [" . quest::saylink("refreshzonedata", 1, "Refresh Zone Data") . "]");	
	plugin::Whisper("[" . quest::saylink("viewzoneinfo", 1, "View Zone Info") . "] [" . quest::saylink("viewignoredmobs", 1, "View Ignored Mobs") . "] [" . quest::saylink("viewdepopmobs", 1, "View Depop Mobs") . "] [" . quest::saylink("viewzcdiag", 1, "View ZC Runtime") . "] [" . quest::saylink("viewremotecommands", 1, "View Remote Commands") . "]");	
	plugin::Whisper("- - - - - - - - - - - - - - - - - - - - - - - - - - - End Quick Actions - - - - - - - - - - - - - - - - - - - - - - - - - - - -");
}

sub PRINT_DETAIL_HEADER {
	my $section = $_[0];
	my $identifier = $_[1];

	plugin::Whisper(" ");
	plugin::Whisper("- - - - - - - - - - - - - - - - - - - - - - - - - - - - " . $section . " - " . $identifier . " - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -");
}

sub PRINT_DETAIL_HEADER_PUBLIC {
	my $section = $_[0];
	my $identifier = $_[1];
	my $clientEntity = $_[2];

	$clientEntity->Message(315, "");
	$clientEntity->Message(315, "- - - - - - - - - - - - - - - - - - - - - - - - - - - - " . $section . " - " . $identifier . " - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -");
}


#--------------------------------------------------#
#---Misc Block: Anything miscellaneous goes here---#
#--------------------------------------------------#

sub GET_UNICODE_MENU_ICON {
	use Encode qw/encode_utf8 decode_utf8/;
	my $bytes = '☰';
	my $unicode = decode_utf8 ($bytes);

	return $unicode;
}

sub GET_UNICODE_CHECKMARK_ICON {
	use Encode qw/encode_utf8 decode_utf8/;
	my $bytes = '✔';
	my $unicode = decode_utf8 ($bytes);

	return $unicode;
}

sub GET_UNICODE_RELOAD_ICON {
	use Encode qw/encode_utf8 decode_utf8/;
	my $bytes = '→';
	my $unicode = decode_utf8 ($bytes);

	return $unicode;
}

sub GET_UNICODE_UP_ICON {
	use Encode qw/encode_utf8 decode_utf8/;
	my $bytes = '↑';
	my $unicode = decode_utf8 ($bytes);

	return $unicode;
}

sub EVENT_ITEM {
     plugin::return_items(\%itemcount); 
}
