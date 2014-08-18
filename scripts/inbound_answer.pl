use strict;
use warnings;

our $session;

fprint('Started inbound_answer.pl');

my $caller;

if( defined($session) )
{
    $caller = $session->getVariable('caller_id_number');
    answer_and_connect();
}


fprint('Finished inbound_answer.pl');

## END ##



sub answer_and_connect
{
    if( not $session->ready() )
    {
        return;
    }

    $session->answer();

    $session->setVariable('secretary_user_waiting', 'true');

    my $api = new freeswitch::API;
    $api->execute('perlrun', '/etc/freeswitch/scripts/inbound_secretary.pl' .
                  ' ' . $session->get_uuid());

    my $ringback = 'local_stream://moh';
    
    $session->setVariable('hangup_after_bridge', 'false');
    $session->setVariable('continue_on_fail', 'true');

    $session->setVariable('playback_timeout_sec', '60');
    $session->execute('playback', $ringback);

    $session->setVariable('secretary_user_waiting', 'false');
    fprint('inbound session: playback interrupted');
    my $out_ses_uuid = $session->getVariable('secretary_out_ses_uuid');
    
    if( $session->getVariable('secretary_user_ready_to_talk') eq 'true' )
    {
        fprint('inbound session: User is ready to talk, bridging');
        my $out_ses = new freeswitch::Session($out_ses_uuid);
        $session->bridge($out_ses);
    }

    # make sure the outbound session is always killed
    $api->execute('uuid_kill', $out_ses_uuid);

    my $hup_cause = $session->getVariable('last_bridge_hangup_cause');
    if( $hup_cause eq '' )
    {
        fprint('last_bridge_hangup_cause is empty, getting hup_cause');
        $hup_cause = $session->getVariable('secretary_hup_cause');
    }
    
    if( $hup_cause eq 'NORMAL_CLEARING' )
    {
        fprint('Call ended normally');
    }
    else
    {
        fprint('Could not connect to the user, cause: ' . $hup_cause);
    }

    $session->hangup();
}



sub fprint
{
    my ($msg) = @_;
    freeswitch::consoleLog("INFO",$msg . "\n");
    return;
}




1;
