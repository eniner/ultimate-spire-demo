#Plugin::MessageRouter("Text")
sub _uniq_preserve_order {
	my %seen;
	my @unique;

	foreach my $value (@_) {
		next if $seen{$value}++;
		push @unique, $value;
	}

	return @unique;
}

sub _instance_tools_normalize_path {
	my $path = shift // "";
	$path =~ s!\\!/!g;
	$path =~ s!/+$!!;
	return $path;
}

sub _instance_tools_join_path {
	my @parts = @_;
	my $path = "";

	foreach my $part (@parts) {
		next unless defined($part) && $part ne "";
		$part =~ s!\\!/!g;

		if ($path eq "") {
			$path = $part;
			next;
		}

		$path =~ s!/+$!!;
		$part =~ s!^/+!!;
		$path .= "/" . $part;
	}

	return $path;
}

sub _instance_tools_read_quest_root_from_config {
	my $config_path = "";
	foreach my $candidate ("eqemu_config.json", "/home/eqemu/server/eqemu_config.json") {
		if (-f $candidate) {
			$config_path = $candidate;
			last;
		}
	}

	return "" if $config_path eq "";
	open(my $fh, "<", $config_path) or return "";
	local $/;
	my $json_text = <$fh>;
	close $fh;

	foreach my $key ("quest_root", "quest_path", "quests_path") {
		if ($json_text =~ /\"$key\"\s*:\s*\"([^\"]+)\"/) {
			return _instance_tools_normalize_path($1);
		}
	}

	return "";
}

sub _instance_tools_resolve_quest_root {
	my $env_root = $ENV{EQEMU_QUEST_ROOT} // "";
	if ($env_root ne "") {
		return _instance_tools_normalize_path($env_root);
	}

	my $config_root = _instance_tools_read_quest_root_from_config();
	if ($config_root ne "") {
		return $config_root;
	}

	my $file_path = __FILE__;
	$file_path =~ s!\\!/!g;
	if ($file_path =~ m!^(.*/quests)/plugins/[^/]+$!) {
		return $1;
	}

	foreach my $candidate ("/home/eqemu/server/quests", "/home/ubuntu/eq/akk-stack/server/quests", "quests") {
		if (-d $candidate) {
			return $candidate;
		}
	}

	return "quests";
}

sub _instance_tools_ultimatedata_root {
	return _instance_tools_join_path(_instance_tools_resolve_quest_root(), "global", "ultimatedata");
}

sub _instance_tools_ultimatedata_zone_dir {
	my $zone_id = $_[0];
	return _instance_tools_join_path(_instance_tools_ultimatedata_root(), $zone_id);
}

sub _instance_tools_ultimatedata_file {
	my ($zone_id, $suffix) = @_;
	return _instance_tools_join_path(_instance_tools_ultimatedata_zone_dir($zone_id), $zone_id . "_" . $suffix . ".json");
}

sub _instance_tools_spotinstancedata_config_file {
	return _instance_tools_join_path(_instance_tools_resolve_quest_root(), "global", "spotinstancedata", "config.json");
}

sub MessageRouter {
	my $text = $_[0];
	my @commandArray = split ' ', $text;

	if($text =~/!initdata/i) {
        if($commandArray[1] != "") {
             quest::crosszonesignalnpcbynpctypeid(GetControllerNPCID(), 1);
        } else {
        	quest::gmsay("Error: Invalid refresh command, no parameter provided. Use format: !initdata zoneid: ", 4, 1);
        }
    } elsif($text =~/!repop/i) {
    	if($commandArray[1] != "") {
             quest::crosszonesignalnpcbynpctypeid(GetControllerNPCID(), 2);
        } else {
        	quest::gmsay("Error: Invalid repop command, no parameter provided. Use format: !repop zoneid: ", 4, 1);
        }
    } elsif($text =~/!depop/i) {
    	if($commandArray[1] != "") {
             quest::crosszonesignalnpcbynpctypeid(GetControllerNPCID(), 3);
        } else {
        	quest::gmsay("Error: Invalid depop command, no parameter provided. Use format: !depop zoneid: ", 4, 1);
        }
    } elsif($text =~/!reloadzone/i) {
    	if($commandArray[1] != "") {
             quest::crosszonesignalnpcbynpctypeid(GetControllerNPCID(), 4);
        } else {
        	quest::gmsay("Error: Invalid reload command, no parameter provided. Use format: !reloadzone zoneid: ", 4, 1);
        }
    }
}

#Plugin::ImplicitMessageRouter("Text")
sub ImplicitMessageRouter {
	my $text = $_[0];

	if($text =~/!remoteaddignore/i) {
		quest::signalwith(GetControllerNPCID(), 5);
	} elsif($text =~/!remoteadddepop/i) {
		quest::signalwith(GetControllerNPCID(), 6);
	} elsif($text =~/!remoteaddcustom/i) {
		quest::signalwith(GetControllerNPCID(), 7);
	} elsif($text =~/!remoteadditem/i) {
		quest::signalwith(GetControllerNPCID(), 8);
	} elsif($text =~/!remotesave/i) {
		quest::signalwith(GetControllerNPCID(), 9);
	} elsif($text =~/!remoteupdatetimer/i) {
		quest::signalwith(GetControllerNPCID(), 10);
	} elsif($text =~/!remoteupdatealltimer/i) {
		quest::signalwith(GetControllerNPCID(), 11);
	} elsif($text =~/!togglevis/i) {
		quest::signalwith(GetControllerNPCID(), 12);
	} elsif($text =~/!showloot/i) {
		my $entity_list = $_[1];
		my @commandArray = split '_', $text;
		my $controllerEntity = $entity_list->GetNPCByNPCTypeID(GetControllerNPCID());
		$controllerEntity->SetEntityVariable("message_target", $commandArray[1]);
		quest::signalwith(GetControllerNPCID(), 13);
	} elsif($text =~/!remoteaddtable/i) {
		quest::signalwith(GetControllerNPCID(), 14);
	} elsif($text =~/!remotebatchassociation/i) {
		quest::signalwith(GetControllerNPCID(), 15);
	} elsif($text =~/!ultimaterespawnbossmobs_ucredit/i) {
		quest::signalwith(GetControllerNPCID(), 16);
	} elsif($text =~/!do_repop_boss_summon_device_ueq/i) {
		quest::signalwith(GetControllerNPCID(), 2);
	} elsif($text =~/showassociatedmobs/i) {
		my $entity_list = $_[1];
		my @commandArray = split '_', $text;
		my $controllerEntity = $entity_list->GetNPCByNPCTypeID(GetControllerNPCID());
		$controllerEntity->SetEntityVariable("message_target", $commandArray[2]);
		$controllerEntity->SetEntityVariable("table_target", $commandArray[1]);
		quest::signalwith(GetControllerNPCID(), 19);
	}
	# elsif($text =~/!gmloot/i) {
	# 	quest::signalwith(GetControllerNPCID(), 17);
	# } elsif($text =~/!summonloot#/i) {
	# 	quest::signalwith(GetControllerNPCID(), 18);
	# } elsif($text =~/!forgeloot/i) {
	# 	quest::signalwith(GetCraftNPCID(), 1);
}

#Plugin::GetControllerNPCID()
sub GetControllerNPCID {
	my $controllerID = "2000986";
	return $controllerID;
}

#Plugin::GetCraftNPCID()
sub GetCraftNPCID {
	my $craftID = "2000080";
	return $craftID;
}

#Plugin::GetUltimateZoneInstanceTypeList()
sub GetUltimateZoneInstanceTypeList {
	my @instanceIDList = (58, 65, 66, 89, 124, 113, 128, 51, 17, 59, 31, 39, 111, 108, 69, 63, 72, 112, 469, 278, 445);
	return @instanceIDList;
}

#Plugin::GetUltimateZoneStaticTypeList()
sub GetUltimateZoneStaticTypeList {
	my @instanceIDList = (378, 455, 446);
	return @instanceIDList;
}


#Plugin::RespawnBossMobs("Entity List", "Boss Array")
sub RespawnBossMobs {
	my $entity_list = pop @_;
	my %bosses = @_;

	foreach my $n (%bosses) {
		$namedNPC = $entity_list->GetNPCByNPCTypeID($n);
		
		if(!$namedNPC) {
			$foundSpawnGroupID = GetNPCSpawnGroup($n);
			$foundSpawnCoordinates = GetNPCCoordinates($foundSpawnGroupID);
			my @fields = split /_/, $foundSpawnCoordinates;
			my $splitX = $fields[0];
			my $splitY = $fields[1];
			my $splitZ = $fields[2];
			my $splitH = $fields[3];
			quest::spawn2($n, 0, 0, $splitX, $splitY, $splitZ, $splitH);		
		}
	}
}

#Plugin::DespawnBossMobs("Entity List", "Boss Array")
sub DespawnBossMobs {
	my $entity_list = pop @_;
	my %bosses = @_;

	foreach my $n (%bosses) {
		$namedNPC = $entity_list->GetNPCByNPCTypeID($n);
		if ($namedNPC) {
			$namedNPC->Depop(1);
		}
	}
}

#Plugin::CheckIfJSONFilesExist(ZoneID)
sub CheckIfJSONFilesExist {
	my $zoneID = $_[0];
	my $lootFile = _instance_tools_ultimatedata_file($zoneID, "loot");
	my $itemFile = _instance_tools_ultimatedata_file($zoneID, "item");
	my $mobFile = _instance_tools_ultimatedata_file($zoneID, "mob");

	if(-e $lootFile && -e $itemFile && -e $mobFile) {
		return 1;
	} else {
		return 0;
	}
}

#Plugin::GenerateJSONFilesFromTemplate(ZoneID)
sub GenerateJSONFilesFromTemplate {
	use File::Copy;
	use File::Path qw(make_path remove_tree);
	
	my $zoneID = $_[0];
	my $zoneDataDir = _instance_tools_ultimatedata_zone_dir($zoneID);
	my $templateLootFile = _instance_tools_join_path(_instance_tools_ultimatedata_root(), "templates", "_loot.json");
	my $templateItemFile = _instance_tools_join_path(_instance_tools_ultimatedata_root(), "templates", "_item.json");
	my $templateMobFile = _instance_tools_join_path(_instance_tools_ultimatedata_root(), "templates", "_mob.json");
	my $newLootFile = _instance_tools_ultimatedata_file($zoneID, "loot");
	my $newItemFile = _instance_tools_ultimatedata_file($zoneID, "item");
	my $newMobFile = _instance_tools_ultimatedata_file($zoneID, "mob");

	remove_tree($zoneDataDir);
	make_path($zoneDataDir);

	copy($templateLootFile, $newLootFile) or die "The copy operation failed: $!";
	copy($templateItemFile, $newItemFile) or die "The copy operation failed: $!";
	copy($templateMobFile, $newMobFile) or die "The copy operation failed: $!";
}

#Plugin::GetSpawnDataHash("ZoneID")
sub GetSpawnDataHash {
	use lib qw(..);
	use JSON qw( );
	my $zoneID = $_[0];
	my $filename = _instance_tools_ultimatedata_file($zoneID, "mob");

	my $json_text = do {
	   open(my $json_fh, "<:encoding(UTF-8)", $filename)
	      or die("Can't open \$filename\": $!\n");
	   local $/;
	   <$json_fh>
	};

	my $json = JSON->new;
	my $data = $json->decode($json_text);

	return $data;
}

#Plugin::UpdateSpawnDataHash("NewDataHash", "ZoneID")
sub UpdateSpawnDataHash {
	use lib qw(..);
	use JSON qw( );
	my $newDataHash = $_[0];
	my $zoneID = $_[1];
	my $filename = _instance_tools_ultimatedata_file($zoneID, "mob");

	open my $fh, ">", $filename;
	print $fh encode_json($newDataHash);
	close $fh;
}

#Plugin::GetLootDataHash("ZoneID")
sub GetLootDataHash {
	use lib qw(..);
	use JSON qw( );
	my $zoneID = $_[0];
	my $filename = _instance_tools_ultimatedata_file($zoneID, "loot");

	my $json_text = do {
	   open(my $json_fh, "<:encoding(UTF-8)", $filename)
	      or die("Can't open \$filename\": $!\n");
	   local $/;
	   <$json_fh>
	};

	my $json = JSON->new;
	my $data = $json->decode($json_text);

	return $data;
}

#Plugin::GetItemDataHash("ZoneID")
sub GetItemDataHash {
	use lib qw(..);
	use JSON qw( );
	my $zoneID = $_[0];
	my $filename = _instance_tools_ultimatedata_file($zoneID, "item");

	my $json_text = do {
	   open(my $json_fh, "<:encoding(UTF-8)", $filename)
	      or die("Can't open \$filename\": $!\n");
	   local $/;
	   <$json_fh>
	};

	my $json = JSON->new;
	my $data = $json->decode($json_text);

	return $data;
}

#Plugin::UpdateLootDataHash("NewDataHash", "ZoneID")
sub UpdateLootDataHash {
	use lib qw(..);
	use JSON qw( );
	my $newDataHash = $_[0];
	my $zoneID = $_[1];
	my $filename = _instance_tools_ultimatedata_file($zoneID, "loot");

	open my $fh, ">", $filename;
	print $fh encode_json($newDataHash);
	close $fh;
}

#Plugin::UpdateItemDataHash("NewDataHash", "ZoneID")
sub UpdateItemDataHash {
	use lib qw(..);
	use JSON qw( );
	my $newDataHash = $_[0];
	my $zoneID = $_[1];
	my $filename = _instance_tools_ultimatedata_file($zoneID, "item");

	open my $fh, ">", $filename;
	print $fh encode_json($newDataHash);
	close $fh;
}

#Plugin::GetRandomLootRoll("Minimum", "Maximum")
sub GetRandomLootRoll {
    my $minimumRoll = $_[0];
    my $maximumRoll = $_[1];

    return $minimumRoll + int(rand($maximumRoll - $minimumRoll));
}

#Plugin::FilterSpawnTypes("Npc", "ZoneID")
sub FilterSpawnTypes {
	my $npc = $_[0];
	my $zoneID = $_[1];
	my $isValid = 0;
	my $mobName = $npc->GetCleanName();
	my @exemptMobList = ("Overlord Mata Muram", "Harbinger of Dread", "A Goblin Treasure Master", "A Goblin Treasure Elite");

	if(!grep{$_ eq $mobName} @exemptMobList) {
		if($npc->GetOwnerID() == 0 && $npc->GetSwarmOwner() == 0) {
			if($npc->GetBodyType() < 31) { # && $npc->GetClass() != 41
				$isValid = 1;
			}			
		}
	} else {
		if($mobName ne "A Goblin Treasure Master" && $mobName ne "A Goblin Treasure Elite")	{
			$isValid = 1;
		}
	}

	return $isValid;
}

#Plugin::DestroyInstance("InstanceConfigData", "ClientReference")
sub DestroyInstance {
	my $data = $_[0];
	my $client = $_[1];
	my $zoneShortName = $data->{shortname};
	my $zoneID = $data->{zoneid};
	my $instanceID = GetPlayerInstance($zoneShortName, $client);

	if($instanceID > 0) {
		quest::UpdateInstanceTimer($instanceID, 1);
		quest::DestroyInstance($instanceID);
		ToggleInstanceMaintenance();
		return $instanceID;
	} else {
		return 0;
	}
}

#Plugin::DestroyLegacyInstance("ClientReference", "ShortName", "ZoneID")
sub DestroyLegacyInstance {
	my $client = $_[0];
	my $zoneShortName = $_[1];
	my $zoneID = $_[2];
	my $instanceID = GetPlayerInstance($zoneShortName, $client);

	if($instanceID > 0) {
		quest::UpdateInstanceTimer($instanceID, 1);
		quest::DestroyInstance($instanceID);
		ToggleInstanceMaintenance();
		return $instanceID;
	} else {
		return 0;
	}
}

#Plugin::SendToInstance("InstanceConfigData", "ClientReference")
sub SendToInstance {
	my $data = $_[0];
	my $client = $_[1];
	my $zoneShortName = $data->{shortname};
	my $zoneID = $data->{zoneid};
	my $x = $data->{x};
	my $y = $data->{y};
	my $z = $data->{z};
	my $h = $data->{h};
	my $instanceID = GetPlayerInstance($zoneShortName, $client);

	if($instanceID > 0) {
		$client->MovePCInstance($zoneID, $instanceID, $x, $y, $z, $h);
		return $instanceID;
	} else {
		return 0;
	}
}

#Plugin::SendToStaticInstance("InstanceConfigData", "ClientReference")
sub SendToStaticInstance {
	my $data = $_[0];
	my $client = $_[1];
	my $zoneID = $data->{zoneid};
	my $staticID = $data->{staticid};
	my $x = $data->{x};
	my $y = $data->{y};
	my $z = $data->{z};
	my $h = $data->{h};

	quest::AssignToInstance($staticID);
	$client->MovePCInstance($zoneID, $staticID, $x, $y, $z, $h);	
}

#Plugin::SendToZone("InstanceConfigData", "ClientReference")
sub SendToZone {
	my $data = $_[0];
	my $client = $_[1];
	my $zoneID = $data->{zoneid};
	my $x = $data->{x};
	my $y = $data->{y};
	my $z = $data->{z};
	my $h = $data->{h};

	quest::movepc($zoneID, $x, $y, $z, $h);	
}

#Plugin::GetInstanceDataHash()
sub GetInstanceDataHash {
	use lib qw(..);
	use JSON qw( );
	my $filename = _instance_tools_spotinstancedata_config_file();

	my $json_text = do {
	   open(my $json_fh, "<:encoding(UTF-8)", $filename)
	      or die("Can't open \$filename\": $!\n");
	   local $/;
	   <$json_fh>
	};

	my $json = JSON->new;
	my $data = $json->decode($json_text);

	return $data;
}

#Plugin::CreateInstance("InstanceConfigData", "ClientReference")
sub CreateInstance {
	my $data = $_[0];
	my $client = $_[1];
	my $zoneShortName = $data->{shortname};
	my $zoneLongName = $data->{longname};
	my $zoneID = $data->{zoneid};
	my $duration = $data->{duration};
	my $ownerNPC = $data->{ownernpc};
	my $clientGroup = $client->GetGroup();
	my $maintenanceFlag = GetInstanceMaintenance();
	my $createSuccess = 0;

	if(!$maintenanceFlag) {
		if($clientGroup) {
			if(VerifyGroupIsInZone($client)) {
				my $instanceID;
	            my $instanceCheckGroupSize = $client->GetGroup()->GroupCount();
	            my $currentGroupMember;
	            my $isStillAttachedFlag = 0;

	            for ($z = 0; $z < $instanceCheckGroupSize; $z++) {
					$currentGroupMember = $client->GetGroup()->GetMember($z);
					$instanceID = GetPlayerInstance($zoneShortName, $currentGroupMember);  

					if($instanceID > 0) {
						$client->Message(315, "$ownerNPC whispers, '". $currentGroupMember->GetCleanName() . " still belongs to " . $zoneLongName . " instance [ID:" . $instanceID . "]. You will need to wait until the instance is fully destroyed.'");
						$isStillAttachedFlag = 1;
						last;
					}
				}

				if($isStillAttachedFlag == 0) {
					my $instancedZone = quest::CreateInstance($zoneShortName, 0, $duration);
					$createSuccess = 1;
					quest::AssignGroupToInstance($instancedZone);
					$client->Message(315, "$ownerNPC whispers, 'Your instance has been created.'");

					for ($i = 0; $i < $instanceCheckGroupSize; $i++) {
						if ($client->GetGroup()->GetMember($i)) {
							$client->GetGroup()->GetMember($i)->Message(4, "You have been assigned to instance [ID:" . $instancedZone . "].");
						}
					}
				}
			} else {
				$client->Message(315, "$ownerNPC whispers, 'I cannot create an instance for you unless your entire group is in this zone.'");
			}
		} else {
			my $instanceID = GetPlayerInstance($zoneShortName, $client);

			if(!$instanceID) {
				my $instancedZone = quest::CreateInstance($zoneShortName, 0, $duration);
				$createSuccess = 1;
				quest::AssignToInstance($instancedZone);
				$client->Message(315, "$ownerNPC whispers, 'Your instance has been created.'");
				$client->Message(4, "You have been assigned to instance [ID:" . $instancedZone . "].");
			} else {
				$client->Message(315, "$ownerNPC whispers, 'You belong to " . $zoneLongName . " instance [ID:" . $instanceID . "]. I cannot create one for you at this time.'");
			}
		}
	} else {
		$client->Message(315, "$ownerNPC whispers, 'I recently destroyed an instance. It takes me 30 seconds to complete maintenance. Please try again shortly.'");
	}

	return $createSuccess;
}

#Plugin::ToggleInstanceMaintenance()
sub ToggleInstanceMaintenance {
	my $maintenanceKey = "Server_Is_Doing_Instance_Cleanup";
	plugin::TSSSetRaw($maintenanceKey, 1, 30);
}

#Plugin::GetInstanceMaintenance()
sub GetInstanceMaintenance {
	return plugin::TSSGetRaw("Server_Is_Doing_Instance_Cleanup");
}

#Plugin::VerifyGroupIsInZone("ClientReference")
sub VerifyGroupIsInZone {
	my $client = $_[0];
	my $grpIterator = 0;
	my $isReady = 0;
    my $myGroup = $client->GetGroup();
    
    if($myGroup) {
     	for ($i = 0; $i < 6; $i++) {
             if ($client->GetGroup()->GetMember($i)) {
             	$grpIterator = $grpIterator + 1;
             }
         }

     	if($grpIterator == $client->GetGroup()->GroupCount()) {
     		$isReady = 1;
     	}
     } else {
          $isReady = 1;  
     }

    return $isReady;
}

#Plugin::DestroyMiscInstanceKeys("ClientReference")
sub DestroyMiscInstanceKeys {
	my $client = $_[0];
	my $myGroup = $client->GetGroup();
	my $grpIterator = 0;
	my @miscKeysArray = ("_Kurns_Timer", "_bertox_instance_id", "_kurns_instance_group_size");

	if($myGroup) {
     	for($i = 0; $i < 6; $i++) {
             if($client->GetGroup()->GetMember($i)) {
             	foreach my $miscKey (@miscKeysArray) {
             		plugin::TSSDel($client->GetGroup()->GetMember($i), $miscKey);
             	} 
             }
         }
     } else {
     	foreach my $miscKey (@miscKeysArray) {
        	plugin::TSSDel($client, $miscKey);
        }
     }
} 

#Plugin::GetPlayerInstance("ZoneShortName", "Client")
sub GetPlayerInstance {
	use DBI;
	my $shortZone = $_[0];
	my $clientReference = $_[1];
	my $client = plugin::val('$client');
	my $charId = $client->CharacterID();

	$dbh = plugin::LoadMysql();
	my @row = $dbh->selectrow_array("
	SELECT il.id
	FROM
	  instance_list il
	  LEFT JOIN  instance_list_player ilp ON (il.id = ilp.id)
	  JOIN zone z ON (il.zone = z.zoneidnumber)
	WHERE
	  ilp.charid = ?
	  AND z.short_name = ?
	ORDER BY
	  il.id DESC
	", undef, $charId, $shortZone);

	if ( $dbh->errstr ) {
		plugin::Debug("DB Error attempting to lookup character instance: '" . $shortZone . "' : " . $dbh->errstr);
	}

	if ($row[0]) {
		return $row[0];
	} else {
		return;
	}
}

sub UpdateNPCSpawnGroupRespawnTimer {
	use DBI;
	my $npcID = $_[0];
	my $respawnTime = $_[1];
	my $zoneShortName = $_[2];
	my $spawngroupID = GetNPCSpawnGroup($npcID);
	my $updateSuccess = 0;
	my $client = plugin::val('$client');

	$dbh = plugin::LoadMysql();
	$statement = "UPDATE spawn2 SET respawntime = ? WHERE spawngroupid = ? AND zone = ?";
	$rv = $dbh->do($statement, undef, $respawnTime, $spawngroupID, $zoneShortName); 

	if($dbh->errstr) {
		plugin::Debug("DB Error attempting respawn timer update!");
	}

	$DBI::err && die $DBI::errstr;
	$rc = $dbh->disconnect;
}

sub GetNPCSpawnGroups {
	use DBI;
	my $npcID = $_[0];
	my $client = plugin::val('$client');
	my @returnedMobIDs;

	$dbh = plugin::LoadMysql();
	my @rows = @{$dbh->selectall_arrayref('SELECT spawngroupID FROM spawnentry where npcID = ?', undef, $npcID)};

	for my $row (@rows) {
  		push @returnedMobIDs, $row->[0];
	}

	if ($dbh->errstr) {
		plugin::Debug("DB Error attempting NPC ID lookup [" . $npcID . "].");
	}

	return @returnedMobIDs;
}

sub GetNPCSpawnGroup {
	use DBI;
	my $npcID = $_[0];
	my $client = plugin::val('$client');

	$dbh = plugin::LoadMysql();
	my @row = $dbh->selectrow_array("SELECT spawnentry.`spawngroupID` FROM spawnentry where spawnentry.`npcID` = ? ORDER BY npcID DESC", undef, $npcID);

	if ($dbh->errstr) {
		plugin::Debug("DB Error attempting NPC ID lookup!");
	}

	if ($row[0]) {
		return $row[0];
	} else {
		return "NOW";
	}
}

sub GetNPCCoordinates {
	use DBI;
	my $npcSpawnGroupID = $_[0];
	my $client = plugin::val('$client');

	$dbh = plugin::LoadMysql();
	my @row = $dbh->selectrow_array("SELECT spawn2.`x`, spawn2.`y`, spawn2.`z`, spawn2.`heading` FROM spawn2 where spawn2.`spawngroupID` = ? ORDER BY spawn2.`id` DESC", undef, $npcSpawnGroupID);

	if ($dbh->errstr) {
		plugin::Debug("DB Error attempting to lookup");
	}

	if ($row[0]) {
		my $returnValue = $row[0] . "_" . $row[1] . "_" . $row[2] . "_" . $row[3];
		return $returnValue;
	} else {
		return "NOW";
	}
}

sub GetItemNameByItemID {
	use DBI;
	my $itemID = $_[0];
	my $client = plugin::val('$client');

	$dbh = plugin::LoadMysql();
	my @row = $dbh->selectrow_array("SELECT items.`name` FROM items where items.`id` = ?", undef, $itemID);

	if ($dbh->errstr) {
		plugin::Debug("DB Error attempting to lookup");
	}

	if ($row[0]) {
		return $row[0];
	} else {
		return "LOOKUPERROR";
	}
}

sub GetAllNPCNamesForZone {
	use DBI;
	my $zoneID = $_[0];
	my $startIDList = $zoneID . '000';
	my $endIDList = $zoneID . '999';
	my @returnedNPCNames;

	$dbh = plugin::LoadMysql();
	my @rows = @{$dbh->selectall_arrayref('SELECT name from npc_types WHERE id > ? AND id < ? ORDER BY level DESC', undef, $startIDList, $endIDList)};

	for my $row (@rows) {
		my $removeFabledString = "Fabled_";
		my $cleanedData = $row->[0];
		my $fabledSearchResult = index($cleanedData, $removeFabledString);

		if($fabledSearchResult == -1) {
			$cleanedData =~ s/#//ig;
			$cleanedData =~ s/_/ /ig;
	  		push @returnedNPCNames, $cleanedData;
	  	}
	}

	if ($dbh->errstr) {
		plugin::Debug("DB Error attempting NPC Names lookup for zone id [" . $zoneID . "].");
	}

	my @uniqueReturnedNPCNames = _uniq_preserve_order(@returnedNPCNames);
	return @uniqueReturnedNPCNames;
}
