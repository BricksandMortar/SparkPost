<%@ WebHandler Language="C#" Class="SparkPost" %>
using System;
using System.Web;
using System.IO;
using System.Runtime.Serialization;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Converters;
using Newtonsoft.Json.Linq;
using Rock;
using Rock.Model;
using Rock.Data;
using Rock.Workflow.Action;

public class SparkPost : IHttpHandler
{
    private const int MAX_LENGTH = 2200;
    private HttpRequest _request;
    private HttpResponse _response;

    public void ProcessRequest( HttpContext context )
    {
        _request = context.Request;
        _response = context.Response;

        _response.ContentType = "text/plain";

        if ( !( _request.HttpMethod == "POST" && _request.ContentType.Contains( "application/json" ) ) )
        {
            _response.Write( "Invalid request type." );
            return;
        }

        if ( _request != null )
        {
            var events = JArray.Parse( GetDocumentContents( _request ) );

            var rockContext = new RockContext();

            var communicationRecipientService = new CommunicationRecipientService( rockContext );

            if ( events == null )
            {
                return;
            }
            int unsavedCommunicationCount = 0;
            foreach ( var item in events.Children() )
            {
                unsavedCommunicationCount++;
                var eventItem = item.SelectToken( "['msys']['message_event']" ) != null
                    ? item["msys"]["message_event"]
                    : item.SelectToken( "['msys']['track_event']" ) != null
                        ? item["msys"]["track_event"]
                        : null;
                if ( eventItem != null && eventItem.SelectToken( "['type']" ) != null )
                {
                    var eventType = JsonConvert.DeserializeObject<EventType>(
                            eventItem["type"].ToJson() );

                    // Process a SendEmailWithEvents workflow action 
                    if ( eventItem.SelectToken( "['rcpt_meta']['workflow_action_guid']" ) !=
                            null )
                    {
                        var actionGuid = eventItem.SelectToken( "['rcpt_meta']['workflow_action_guid']" ).ToString().AsGuidOrNull();
                        string status = string.Empty;
                        switch ( eventType )
                        {
                            case EventType.Delivery:
                                status = SendEmailWithEvents.SENT_STATUS;
                                break;
                            case EventType.Click:
                                status = SendEmailWithEvents.CLICKED_STATUS;
                                break;
                            case EventType.Open:
                                status = SendEmailWithEvents.OPENED_STATUS;
                                break;

                            case EventType.Delay:
                                status = SendEmailWithEvents.TIMEOUT_STATUS;
                                break;
                            case EventType.Bounce:
                            case EventType.SpamComplaint:
                            case EventType.OutofBand:
                            case EventType.PolicyRejection:
                            case EventType.GenerationFailure:
                            case EventType.GenerationRejection:
                                status = SendEmailWithEvents.FAILED_STATUS;
                                break;
                            case EventType.Injection:
                                break;
                            case EventType.SMSStatus:
                                break;
                            case EventType.ListUnsubscribe:
                                break;
                            case EventType.LinkUnsubscribe:
                                break;
                            case EventType.RelayInjection:
                                break;
                            case EventType.RelayRejection:
                                break;
                            case EventType.RelayDelivery:
                                break;
                            case EventType.RelayTemporaryFailure:
                                break;
                            case EventType.RelayPermanentFailure:
                                break;
                            default:
                                throw new ArgumentOutOfRangeException();
                        }

                        if ( actionGuid != null && !string.IsNullOrWhiteSpace( status ) )
                        {
                            SendEmailWithEvents.UpdateEmailStatus( actionGuid.Value, status, eventType.ConvertToString().SplitCase(), rockContext, true );
                        }
                    }



                    // process the communication recipient
                    if (
                        eventItem.SelectToken( "['rcpt_meta']['communication_recipient_guid']" ) !=
                        null )
                    {
                        var communicationRecipientGuid = Guid.Parse(
                            eventItem["rcpt_meta"]["communication_recipient_guid"].ToString() );

                        {
                            var communicationRecipient =
                                communicationRecipientService.Get( communicationRecipientGuid );
                            if ( communicationRecipient != null )
                            {

                                switch ( eventType )
                                {
                                    case EventType.Delivery:
                                        communicationRecipient.Status = CommunicationRecipientStatus.Delivered;
                                        communicationRecipient.StatusNote =
                                            string.Format( "Confirmed delivered by SparkPost at {0}",
                                                UnixTimeStampToDateTime(
                                                    eventItem["timestamp"].ToString() ) );
                                        break;

                                    case EventType.Open:
                                        string userAgent =
                                            eventItem["user_agent"].ToString();
                                        var openDateTime =
                                            UnixTimeStampToDateTime(
                                                eventItem["timestamp"].ToString() );
                                        communicationRecipient.Status = CommunicationRecipientStatus.Opened;
                                        communicationRecipient.OpenedDateTime = openDateTime;
                                        communicationRecipient.OpenedClient =
                                            userAgent.Truncate( 197 );
                                        var openActivity =
                                            new CommunicationRecipientActivity
                                            {
                                                ActivityType = "Opened",
                                                ActivityDateTime = openDateTime,
                                                ActivityDetail =
                                                    string.Format( "Opened from {0} ({1})",
                                                        userAgent, eventItem["ip_address"] )
                                                        .Truncate( MAX_LENGTH )
                                            };
                                        communicationRecipient.Activities.Add( openActivity );
                                        break;

                                    case EventType.OutofBand:
                                    case EventType.PolicyRejection:
                                        communicationRecipient.Status = CommunicationRecipientStatus.Failed;
                                        communicationRecipient.StatusNote =
                                            eventItem["error_code"].ToString() +
                                            eventItem["reason"] +
                                            ( eventType == EventType.OutofBand
                                                ? eventItem["bounce_class"]
                                                : null );
                                        break;

                                    case EventType.Click:
                                        var clickActivity =
                                            new CommunicationRecipientActivity();
                                        clickActivity.ActivityType = "Click";
                                        clickActivity.ActivityDateTime = UnixTimeStampToDateTime(
                                            eventItem["timestamp"].ToString() );
                                        clickActivity.ActivityDetail =
                                            string.Format( "Clicked the link {0} ({1}) from {2} using {3}",
                                                eventItem["target_link_name"],
                                                eventItem["target_link_url"],
                                                eventItem["ip_address"],
                                                eventItem["user_agent"] )
                                                .Truncate( MAX_LENGTH );
                                        communicationRecipient.Activities.Add( clickActivity );
                                        break;
                                    case EventType.SpamComplaint:
                                    case EventType.GenerationFailure:
                                    case EventType.GenerationRejection:
                                    case EventType.Bounce:
                                        string message =
                                            ( eventItem["error_code"].ToString() +
                                             eventItem["reason"] +
                                             eventItem["bounce_class"] ).Truncate( MAX_LENGTH );
                                        communicationRecipient.Status = CommunicationRecipientStatus.Failed;
                                        communicationRecipient.StatusNote = message;

                                        Rock.Communication.Email.ProcessBounce(
                                            eventItem["rcpt_to"].ToString(),
                                            Rock.Communication.BounceType.HardBounce,
                                            message,
                                            UnixTimeStampToDateTime(
                                                eventItem["timestamp"].ToString() ) );
                                        break;

                                    case EventType.Injection:
                                            var sentActivity =
                                            new CommunicationRecipientActivity();
                                        sentActivity.ActivityType = "Sent";
                                        sentActivity.ActivityDateTime = UnixTimeStampToDateTime(
                                            eventItem["timestamp"].ToString() );
                                        sentActivity.ActivityDetail =
                                            string.Format( "Emai sent to {0}",
                                                eventItem["rcpt_to"]).Truncate( MAX_LENGTH );
                                        communicationRecipient.Activities.Add( sentActivity );
                                        break;
                                    case EventType.SMSStatus:
                                        break;
                                    case EventType.Delay:
                                        break;
                                    case EventType.ListUnsubscribe:
                                        break;
                                    case EventType.LinkUnsubscribe:
                                        break;
                                    case EventType.RelayInjection:
                                        break;
                                    case EventType.RelayRejection:
                                        break;
                                    case EventType.RelayDelivery:
                                        break;
                                    case EventType.RelayTemporaryFailure:
                                        break;
                                    case EventType.RelayPermanentFailure:
                                        break;
                                    default:
                                        throw new ArgumentOutOfRangeException();
                                }
                            }
                        }

                        // save every 100 changes
                        if ( unsavedCommunicationCount >= 100 )
                        {
                            rockContext.SaveChanges();
                            unsavedCommunicationCount = 0;
                        }
                    }
                }
            }
            // final save
            rockContext.SaveChanges();
        }


        _response.Write( "Success" );

        _response.StatusCode = 200;
    }


    public bool IsReusable
    {
        get { return false; }
    }

    private static string GetDocumentContents( HttpRequest request )
    {
        string documentContents;
        using ( var receiveStream = request.InputStream )
        {
            using ( var readStream = new StreamReader( receiveStream, Encoding.UTF8 ) )
            {
                documentContents = readStream.ReadToEnd();
            }
        }
        return documentContents;
    }

    private static DateTime UnixTimeStampToDateTime( string timestamp )
    {
        // Unix timestamp is seconds past epoch
        long unixTimeStamp = long.Parse( timestamp );
        var dtDateTime = new DateTime( 1970, 1, 1, 0, 0, 0, 0, DateTimeKind.Utc );
        dtDateTime = dtDateTime.AddSeconds( unixTimeStamp ).ToLocalTime();
        return RockDateTime.ConvertLocalDateTimeToRockDateTime( dtDateTime );
    }

    [JsonConverter( typeof( StringEnumConverter ) )]
    public enum EventType
    {
        [EnumMember( Value = "bounce" )]
        Bounce,
        [EnumMember( Value = "delivery" )]
        Delivery,
        [EnumMember( Value = "injection" )]
        Injection,
        [EnumMember( Value = "sms_status" )]
        SMSStatus,
        [EnumMember( Value = "spam_complaint" )]
        SpamComplaint,
        [EnumMember( Value = "out_of_band" )]
        OutofBand,
        [EnumMember( Value = "policy_rejection" )]
        PolicyRejection,
        [EnumMember( Value = "delay" )]
        Delay,
        [EnumMember( Value = "click" )]
        Click,
        [EnumMember( Value = "open" )]
        Open,
        [EnumMember( Value = "generation_failure" )]
        GenerationFailure,
        [EnumMember( Value = "generation_rejection" )]
        GenerationRejection,
        [EnumMember( Value = "list_unsubscribe" )]
        ListUnsubscribe,
        [EnumMember( Value = "link_unsubscribe" )]
        LinkUnsubscribe,
        [EnumMember( Value = "relay_injection" )]
        RelayInjection,
        [EnumMember( Value = "relay_rejection" )]
        RelayRejection,
        [EnumMember( Value = "relay_delivery" )]
        RelayDelivery,
        [EnumMember( Value = "relay_tempfail" )]
        RelayTemporaryFailure,
        [EnumMember( Value = "relay_permfail" )]
        RelayPermanentFailure
    }
}
