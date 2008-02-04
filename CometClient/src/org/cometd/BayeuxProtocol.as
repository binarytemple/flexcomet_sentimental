// ========================================================================
// Copyright 2007 Kenneth Tam
// ------------------------------------------------------------------------
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at 
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//========================================================================

package org.cometd {
	
public class BayeuxProtocol
{
	// Protocol channels
    public static const META:String               ="/meta/";
    public static const META_CONNECT:String       ="/meta/connect";
    public static const META_DISCONNECT:String    ="/meta/disconnect";
    public static const META_HANDSHAKE:String     ="/meta/handshake";
    public static const META_PING:String          ="/meta/ping";
    public static const META_STATUS:String        ="/meta/status";
    public static const META_SUBSCRIBE:String     ="/meta/subscribe";
    public static const META_UNSUBSCRIBE:String   ="/meta/unsubscribe";
    
    // Protocol message field names
    public static const CLIENT_FIELD:String       ="clientId";
    public static const DATA_FIELD:String         ="data";
    public static const CHANNEL_FIELD:String      ="channel";
    public static const ID_FIELD:String           ="id";
    public static const TIMESTAMP_FIELD:String    ="timestamp";
    public static const TRANSPORT_FIELD:String    ="transport";
    public static const ADVICE_FIELD:String       ="advice";
    public static const SUCCESSFUL_FIELD:String   ="successful";
    public static const SUBSCRIPTION_FIELD:String ="subscription";
    public static const EXT_FIELD:String          ="ext";
    
    // Transport names
    public static const TRANSPORT_LONGPOLLING:String     ="long-polling";
    public static const TRANSPORT_CALLBACKPOLLING:String ="callback-polling";
    
    // Advice values
    public static const ADVICE_RECONNECT_RETRY:String	  ="retry";
    public static const ADVICE_RECONNECT_HANDSHAKE:String ="handshake"; 
    public static const ADVICE_RECONNECT_NONE:String      ="none";    
    
    public static const ADVICE_INTERVAL:String            ="interval";
    public static const ADVICE_MULTIPLECLIENTS:String     ="multiple-clients";
}

}
