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

package org.cometd.events {

import flash.events.Event;

public class PublishEvent extends Event
{
    public static const PUBLISH:String = "publish";
    
    private var _msg:Object;
    
    public function PublishEvent(type:String, msg:Object)
    {
        super(type);
        _msg = msg;
    }
    
    public function get message():Object
    {
        return _msg;
    }
}

}
