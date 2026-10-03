# Merge this into quests/global/global_player.pl inside EVENT_SAY.
# Optional if you only hail the zone_controller NPC or use Spire Apply.
# Required for cross-zone: !initdata <zoneid>  !repop <zoneid>  !depop <zoneid>  !reloadzone <zoneid>

    if ($client && $client->GetGM() == 1) {
        if ($text =~ /!initdata/i || $text =~ /!repop/i || $text =~ /!depop/i || $text =~ /!reloadzone/i) {
            plugin::MessageRouter($text);
        }
    }
