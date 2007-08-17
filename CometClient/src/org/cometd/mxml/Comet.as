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
import org.cometd.CometClient;

public class Comet extends CometClient implements IMXMLObject, IMXMLSupport
{
    private var _id:String;
    private var _concurrency:String = null;
    private var _showBusyCursor:Boolean = false;
    
    public function Comet()
    {
    }
    
    public function initialized(document:Object, id:String):void
    {
        _id = id;
        super.init();
    }
    
    public function get concurrency():String
    {
        return _concurrency;
    }
    
    public function set concurrency(c:String):void
    {
        _concurrency = c;
    }
    
    public function get showBusyCursor():Boolean
    {
        return _showBusyCursor;
    }
    
    public function set showBusyCursor(sbc:Boolean):void
    {
        _showBusyCursor = sbc;
    }
    
    // TODO: implement Subscriptions as array of properties
}

}
