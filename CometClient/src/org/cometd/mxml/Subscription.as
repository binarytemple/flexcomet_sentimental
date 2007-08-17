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

package org.cometd.mxml {

import mx.rpc.mxml.IMXMLSupport;
import mx.core.IMXMLObject;
import flash.events.EventDispatcher;
import org.cometd.events.PublishEvent;

[Event(name="publish", type="org.cometd.events.PublishEvent")]
public class Subscription extends EventDispatcher implements IMXMLObject, IMXMLSupport
{
    private var _client:Comet;
    
    private var _channel:String;
    private var _comet:String;
    
    public function Subscription()
    {
    }
    
    public function initialized(document:Object, id:String):void
    {
        // TODO: implement Subscriptions as array of properties to avoid id referencing
        _client = document[_comet];
        _client.subscribe( _channel, onMessage, this );
    }
    
    public function get concurrency():String
    {
        return null;
    }
    
    public function set concurrency(c:String):void
    {
    }
    
    public function get showBusyCursor():Boolean
    {
        return false;
    }
    
    public function set showBusyCursor(sbc:Boolean):void
    {
    }
    
    public function set comet(cc:String):void
    {
        _comet = cc;
    }
    
    public function get comet():String
    {
        return _comet;
    }
    
    public function get channel():String
    {
        return _channel;
    }
    
    public function set channel(c:String):void
    {
        _channel = c;
    }
    
    private function onMessage(msg:Object):void
    {
        var pe:PublishEvent = new PublishEvent(PublishEvent.PUBLISH, msg);
        dispatchEvent(pe);
    }
}

}
