use strict;
use warnings;

# virtual secretary script: it takes the inbound session UUID as argument,
# initiates the outbound call to the user,
# and then connects or disconnects depending on user's reaction

fprint('Entered inbound_secretary.pl');


my $directory_user = '720@test01.voxserv.net';

my $in_ses;
my $out_ses;

run_secretary();

if( defined($in_ses) )
{
    $in_ses->destroy();
}

if( defined($out_ses) )
{
    $out_ses->destroy();
}

fprint('Finished inbound_secretary.pl');

## END ##


sub run_secretary
{
    if( scalar(@ARGV) != 1 )
    {
        fprint('ERROR: usage: ' . $0 . ' UUID');
        return;
    }

    my $uuid_inbound = $ARGV[0];
    my $api = new freeswitch::API;

    if( $api->execute('uuid_exists', $uuid_inbound) eq 'false' )
    {
        fprint('UUID ' . $uuid_inbound . ' does not exist');
        return;
    }

    $in_ses = new freeswitch::Session($uuid_inbound);
    
    # inbound call properties
    my $caller =      $in_ses->getVariable('caller_id_number');
    my $caller_name = $in_ses->getVariable('effective_caller_id_name');
    $caller_name =~ s/[^0-9a-zA-Z ]//;
        
    fprint('Caller: ' . $caller . ' (' . $caller_name . ')');
    
    my $greeting = 'ivr/ivr-welcome_to_freeswitch.wav';
    
    my $originate_str =
        sprintf('{ignore_early_media=true,' .
                'originate_timeout=60,origination_caller_id_number=%s,' .
                'origination_caller_id_name=\'%s\'}',
                $caller, $caller_name);    
    
    $originate_str .= 'user/' . $directory_user;
    
    fprint('Originate string: ' . $originate_str);
    
    $out_ses = new freeswitch::Session($originate_str);
    
    sub break_inbound_call {
        my $reason = shift;
        $reason = 'NORMAL_CLEARING' if not defined($reason);        
        fprint('Could not connect to the user');
        $in_ses->setVariable('secretary_hup_cause', $reason);
        if( $in_ses->getVariable('secretary_user_waiting') )
        {
            $in_ses->execute('break');
        }
        return;
    };

    sub check_inbound_session {
        if( not $in_ses->ready() or not $in_ses->getVariable('secretary_user_waiting') )
        {
            fprint('inbound call is dropped');
            $out_ses->sleep(1000);
            $out_ses->streamFile('voicemail/vm-goodbye.wav');
            $out_ses->hangup();
            return 0;
        }
        return 1;
    };

    if( not $out_ses->ready() )
    {
        break_inbound_call('NO_ANSWER');
        return;
    }
    
    if( not check_inbound_session() )
    {
        return;
    }
    
    fprint('Outbound session answered. Starting the secretary IVR');
    my $timeout = time() + 60;    
    my $connect;
    
    while( not $connect )
    {
        $out_ses->sleep(500);
        
        if( not check_inbound_session() )
        {
            return;
        }
            
        if( not $out_ses->ready() )
        {
            fprint('Outbound session hung up');
            break_inbound_call('CALL_REJECTED');
            return;
        }
                
        if( time() > $timeout )
        {
            fprint('Outbound session timed out');
            break_inbound_call('NO_ANSWER');
            $out_ses->hangup();            
            return;
        }

        my $digit = $out_ses->playAndGetDigits(1,1,1,3000,'#',$greeting, undef, '\d');
        if( defined($digit) and $digit ne '' )
        {
            if( $digit != 0 )
            {
                $connect = 1;
            }
            else
            {
                fprint('User selected 0, hanging up');
                break_inbound_call('CALL_REJECTED');
                $out_ses->hangup();
                return 0;
            }
        }
    }
    
    fprint('User confirmed the call. Connecting');
    $in_ses->setVariable('secretary_user_ready_to_talk', 'true');
    $in_ses->setVariable('secretary_out_ses_uuid', $out_ses->get_uuid());

    if( not check_inbound_session() )
    {
        return;
    }

    if( $in_ses->getVariable('secretary_user_waiting') eq 'true' )
    {
        $in_ses->execute('break');
    }

    $out_ses->execute('transfer', 'park inline');
    return;
}
    


sub fprint
{
    my ($msg) = @_;
    freeswitch::consoleLog("INFO",$msg . "\n");
    return;
}

1;
