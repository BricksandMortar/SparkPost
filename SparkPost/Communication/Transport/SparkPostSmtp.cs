// <copyright>
// Copyright 2013 by the Spark Development Network
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// </copyright>
//

using System.ComponentModel;
using System.ComponentModel.Composition;
using System.Net.Mail;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Rock;
using Rock.Attribute;
using Rock.Communication;
using Rock.Communication.Transport;
using Rock.Model;

namespace com.bricksandmortarstudio.Communication.Transport
{
    /// <summary>
    /// Sends a communication through SMTP protocol
    /// </summary>
    [Description("Sends a communication through SparkPost's SMTP API")]
    [Export(typeof(TransportComponent))]
    [ExportMetadata("ComponentName", "SparkPost SMTP")]
    [TextField("Server", "", true, "smtp.sparkpostmail.com", "", 0)]
    [TextField("Username", "Required to be SMTP_Injection", true, "SMTP_Injection", "", 1)]
    [TextField("Password", "A valid SparkPost API key", true, "", "", 2, null, true)]
    [IntegerField("Port", "", true, 587, "", 3)]
    [BooleanField("Use SSL", "", false, "", 4)]
    [BooleanField("Inline CSS", "Whether to enable SparkPost's CSS inlining feature", order: 5, key:"inlinecss")]

    public class SparkPostSmtp : SMTPComponent
    {
        /// <summary>
        /// Gets a value indicating whether transport has ability to track recipients opening the communication.
        /// </summary>
        /// <value>
        /// <c>true</c> if transport can track opens; otherwise, <c>false</c>.
        /// </value>
        public override bool CanTrackOpens => true;

        /// <summary>
        /// Gets the recipient status note.
        /// </summary>
        /// <value>
        /// The status note.
        /// </value>
        public override string StatusNote => $"Email was recieved for delivery by SparkPost ({RockDateTime.Now})";

        /// <summary>
        /// Adds any additional headers.
        /// </summary>
        /// <param name="message">The message.</param>
        /// <param name="recipient"></param>
        public override void AddAdditionalHeaders(MailMessage message, CommunicationRecipient recipient)
        {
            var header = new JObject(new JProperty("options", new JObject(new JProperty("open_tracking", true), new JProperty("click_tracking", true),new JProperty("inline_css", GetAttributeValue("inlinecss").AsBoolean()))));
            header.Add(new JProperty("metadata", new JObject(new JProperty("communication_recipient_guid", recipient.Guid.ToString()))));
            string value = header.ToString();
            message.Headers.Add("X-MSYS-API", value);
        }
    }
}