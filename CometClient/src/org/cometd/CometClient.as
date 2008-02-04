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

import flash.errors.*;
import flash.events.*;

import mx.rpc.*;
import mx.rpc.events.*;
import mx.rpc.http.*;
import mx.utils.*;

import com.adobe.serialization.json.JSON;
import flash.utils.setInterval;
import flash.utils.setTimeout;

public class CometClient
{
	// Recommended flashvar parameter names for configuration
	public static const COMET_SERVER_FLASHVAR:String = "cometserver";
	public static const COMET_URL_FLASHVAR:String = "cometurl";
	
    public static const SUPPORTED_CONNECTION_TYPES:Array = ["long-polling"];
    public static const BAYEUX_VERSION:String = "1.0";
    public static const BAYEUX_MIN_VERSION:String = "1.0";
    
    public static const MAX_HANDSHAKE_ATTEMPTS_DEFAULT:int = 10;
    
    ///////////////////////////////////////////////////////////////////////////////////////////////////////
    
    private var _httpTunnel:HTTPService;
    private var _httpCommand:HTTPService;
    private var _cometURL:String = null;
    private var _rootURL:String = null;
    
    // Client-provided callback for debug output
    private var _clientDebugHandler:Function;
    
    // True if a successful /meta/connect has occurred (ie, we have a clientId, etc)
    private var _connected:Boolean = false;
    
    // AsyncToken from handshake -> connect (different than connect -> reconnect)
    private var _initialConnectToken:AsyncToken;

    private var _version:String = BAYEUX_VERSION;
    private var _minVersion:String = BAYEUX_MIN_VERSION;
    private var _clientId:String;
    private var _advice:Object;
    private var _handshakeReturn:Object;
    private var _maxHandshakeAttempts:int = MAX_HANDSHAKE_ATTEMPTS_DEFAULT;
    private var _currentHandshakeAttempt:int;
    
    // Array of functions w/ signature (fault:Fault, msg:Object, target:Object)
    // TODO: HTTP transport errors should be abstracted from CometClient users
    private var _faultListeners:Array = [];
    
    // Array of { channel:String, star:Boolean, starstar:Boolean, that:Object, cb:Function } where cb has sig (obj:Object)
    // TODO: Implement Subscription interface & impls with MessageDataEvent dispatching, etc
    private var _subscriptionListeners:Array = [];
    
    // Queue of operations to be deferred (can't be executed because of state; waiting for init, etc).
    // Each element is an array where the 1st element is the fn to be deferred, and the rest are the args.
    private var _pendingOperations:Array = [];
    
    ///////////////////////////////////////////////////////////////////////////////////////////////////////
    
    public function CometClient()
    {
    }

    public function get cometURL():String
    {
        return _cometURL;
    }
    
    public function set cometURL(curl:String):void
    {
        _cometURL = curl;
    }
    
    public function get rootURL():String
    {
        return _rootURL;
    }
    
    public function set rootURL(rurl:String):void
    {
        _rootURL = rurl;
    }
    
    public function get clientId():String
    {
        return _clientId;
    }
    
    public function set debugHandler(handler:Function):void
    {
        _clientDebugHandler = handler;
    }
    
    public function get debugHandler():Function
    {
        return _clientDebugHandler;
    }
    
    public function init():void
    {
        // Connection used for handshaking and tunnelling
        // TODO: replace use of HTTPService with a self-contained HTTP client
        
        debugOutput("init() w/ root URL=" + _rootURL + " comet URL=" + _cometURL);
        
        _httpTunnel = new HTTPService(_rootURL);
        // Connection used for sending messages (subscribe, unsubscribe, publish, etc)
        _httpCommand = new HTTPService(_rootURL);        
        // URL for cometd

        // Initialize connections
        _httpCommand.url = _cometURL;
        _httpCommand.method = "POST";
        _httpCommand.resultFormat = HTTPService.RESULT_FORMAT_TEXT;
        _httpCommand.addEventListener(ResultEvent.RESULT, this.commandHandler);
        _httpCommand.addEventListener(FaultEvent.FAULT, this.httpFaultHandler);
                
        _httpTunnel.url = _cometURL;
        _httpTunnel.method = "POST";
        _httpTunnel.resultFormat = HTTPService.RESULT_FORMAT_TEXT;
        _httpTunnel.addEventListener(ResultEvent.RESULT, this.handshakeHandler);
        _httpTunnel.addEventListener(FaultEvent.FAULT, this.httpFaultHandler);
        
        _currentHandshakeAttempt = 0;
        
        sendHandshake();
    }
    
    private function sendHandshake():AsyncToken {
        _currentHandshakeAttempt++;
        
        // Handshake w/ server
        var handshake:Object = {
            version: _version,
            minimumVersion: _minVersion,
            channel: BayeuxProtocol.META_HANDSHAKE,
            ext: { "json-comment-filtered": false },
            supportedConnectionTypes: SUPPORTED_CONNECTION_TYPES
        };
        
        return sendMessage( _httpTunnel, handshake );
    }
    
    public function subscribe(ch:String, cb:Function, that:Object = null):Boolean
    {
        if ( ch == null || ch.charAt(0) != '/' || cb == null ) {
            return false;
        }
        
        if ( !_connected ) {
            _pendingOperations.push([ this.subscribe, ch, cb, that ]);
            return true;
        }
        
        // Keep the original channel around since we will potentially manipulate value in ch (wildcard handling)
        var originalChannel:String = new String(ch);
        
        var s:Boolean = false;
        var ss:Boolean = false;
        
        if ( ch.length > 1 && ch.substr(ch.length-2,2) == "/*" ) {
            // Single segment wildcard subscription
            ch = ch.substring(0, ch.length-1);
            s = true;
        }
        else if ( ch.length > 2 && ch.substr(ch.length-3,3) == "/**" ) {
            // Multiple segment wildcard subscription
            ch = ch.substring(0, ch.length-2);
            ss = true;
        }
        
        // At this point, ch holds either the full channel or the root of a wildcard channel
        _subscriptionListeners.push( { channel: ch, star: s, starstar: ss, that: that, cb: cb } );
        
        var subscribe:Object = {
            channel: BayeuxProtocol.META_SUBSCRIBE,
            clientId: _clientId,
            subscription: originalChannel
        };
        
        // TODO: locally track existing subscriptions?

        sendMessage( _httpCommand, subscribe );
        return true;
    }
    
    public function unsubscribe(ch:String):void
    {
        if ( !_connected ) {
            _pendingOperations.push([ this.unsubscribe, ch ]);
            return;
        }
        
        // Keep the original channel around since we will potentially manipulate value in ch (wildcard handling)
        var originalChannel:String = new String(ch);
        
        var s:Boolean = false;
        var ss:Boolean = false;
        
        if ( ch.length > 1 && ch.substr(ch.length-2,2) == "/*" ) {
            // Single segment wildcard subscription
            ch = ch.substring(0, ch.length-1);
            s = true;
        }
        else if ( ch.length > 2 && ch.substr(ch.length-3,3) == "/**" ) {
            // Multiple segment wildcard subscription
            ch = ch.substring(0, ch.length-2);
            ss = true;
        }

        // Find indices of all listeners that match this channel
        var i:Number;
		var indicesToDelete:Array = new Array();
        for ( i=0 ; i < _subscriptionListeners.length ; ++i ) {
        	var listener:Object = _subscriptionListeners[i];
        	if ( listener.channel == ch && listener.star == s && listener.starstar == ss ) {
        		indicesToDelete.push(i);
        	}
        }
        
        // Remove the listeners
        for ( i=indicesToDelete.length-1 ; i >= 0 ; --i ) {
        	_subscriptionListeners.splice(indicesToDelete[i], 1);
        }
        
        var unsubscribe:Object = {
            channel: BayeuxProtocol.META_UNSUBSCRIBE,
            clientId: _clientId,
            subscription: originalChannel
        };
        
        sendMessage( _httpCommand, unsubscribe );
    }
    
    public function publish(ch:String, data:Object):void
    {
        if ( !_connected ) {
            _pendingOperations.push([ this.publish, ch, data ]);
            return;
        }
        
        debugOutput( "publish(): ch=" + ch + " data=" + data );
        
        var publish:Object = {
            channel: ch,
            clientId: _clientId, // optional, but easy for us
            data: data
        };
        
        sendMessage( _httpCommand, publish );
    }
    
    public function disconnect():void
    {
        debugOutput("disconnect() called.");
        
        _httpTunnel.disconnect();
        _httpTunnel = null;
        _httpCommand.disconnect();
        _httpCommand = null;
        
        _faultListeners = [];
        _subscriptionListeners = [];
        _pendingOperations = [];
        
        _handshakeReturn = null;
        _advice = null;
        _clientId = null;
        _connected = false;
        _initialConnectToken = null;
    }
    
    public function addHttpFaultListener(callback:Function):void
    {
        if (_faultListeners.indexOf(callback) != -1)
            _faultListeners.push(callback);
    }
    
    ///////////////////////////////////////////////////////////////////////////////////////////////////////
    
    private function handshakeHandler(evt:ResultEvent):void
    {
        debugOutput("handshakeHandler(): received response.");
        var messages:Array = parseResult(evt);
        
        // FIXME: Assuming handshake always returns just one message (is this per spec?)
        _handshakeReturn = messages[0];
        _advice = _handshakeReturn.advice;
        
        // Was handshake successful?
        if ( _handshakeReturn.successful != true ) {
            debugOutput( "Handshake failed!  Msg=" + _handshakeReturn );
            if ( _advice != null ) {
            	// Follow advice for re-handshaking
                if ( _advice.reconnect == BayeuxProtocol.ADVICE_RECONNECT_NONE ) {
                    debugOutput("Reconnect advice=NONE received.");
                    disconnect();
                }
                else if ( _advice.reconnect == BayeuxProtocol.ADVICE_RECONNECT_RETRY ||
                          _advice.reconnect == BayeuxProtocol.ADVICE_RECONNECT_HANDSHAKE ) {
                    // FIXME: Should we apply interval advice for handshaking?  Not clear from spec.
                    if ( _currentHandshakeAttempt < _maxHandshakeAttempts ) {
                        sendHandshake();
                    }
                    else {
                        debugOutput("Maximum handshake attempts reached.");
                        disconnect();
                    }
                }
                return;
            }
            else {
            	// No advice, just treat as ADVICE_RECONNECT_HANDSHAKE 
                if ( _currentHandshakeAttempt < _maxHandshakeAttempts ) {
                    sendHandshake();
                }
                else {
                    debugOutput("Maximum handshake attempts reached.");
                    disconnect();
                }
            }
        }
        
        // handshake successful, reset handshake attempts and switch to connection handler
        _currentHandshakeAttempt = 0;
        _httpTunnel.removeEventListener(ResultEvent.RESULT, this.handshakeHandler);
        _httpTunnel.addEventListener(ResultEvent.RESULT, this.connectHandler);
        
        _clientId = _handshakeReturn.clientId;
        
        debugOutput( "handshakeHandler(): clientId=" + _clientId );
        
        // TODO: version checking
        // TODO: auth?
        // TODO: transport check, just use long-polling for now
        
        var connect:Object = {
            channel: BayeuxProtocol.META_CONNECT,
            clientId: _clientId,
            connectionType: BayeuxProtocol.TRANSPORT_LONGPOLLING
        };
        
        _initialConnectToken = sendMessage( _httpTunnel, connect );
    }
    
    private function connectHandler(evt:ResultEvent):void {
        
        debugOutput("connectHandler(): response received.");
        
        if (_initialConnectToken != null && evt.token == _initialConnectToken) {
            debugOutput("Initial connection complete, connected=true");
            _connected = true;
            _initialConnectToken = null;
            
            while (_pendingOperations.length > 0) {
                var pendingOperation:Array = _pendingOperations.shift();
                var func:Function = pendingOperation.shift();
                func.apply(this, pendingOperation);
            }
        }
        
        var messages:Array = parseResult(evt);
        
        for each( var msg:Object in messages ) {
            if (msg.advice != null) {
                _advice = msg.advice;
            }
            if (msg.channel != null && (msg.channel as String).indexOf("/meta/") != 0) {
                for (var i:int=0; i < _subscriptionListeners.length; ++i) {
                    var subscription:Object = _subscriptionListeners[i];
                    if ( channelMatchesSubscription( msg.channel, subscription ) ) {
                        subscription.cb.call( subscription.that, msg );
                    }
                }
            }
        }        
        
        // Re-open tunnel after waiting for appropriate interval
        var reconnect:Object = {
            channel: BayeuxProtocol.META_CONNECT,
            clientId: _clientId,
            connectionType: BayeuxProtocol.TRANSPORT_LONGPOLLING
        };
           var interval:int = _advice.interval as int;
        if ( interval > 0 ) {
            debugOutput( "connectHandler(): waiting reconnect interval=" + interval ); 
            setTimeout(sendMessage, interval, [ _httpTunnel, reconnect ]);
        }
        else {
            sendMessage( _httpTunnel, reconnect );
        }
    }
    
    private function commandHandler(evt:ResultEvent):void {
        var messages:Array = parseResult(evt);
        debugOutput( "commandHandler(): " + messages );
        
        for each( var msg:Object in messages ) {
            // Update advice if present
            if (msg.advice != null) {
                _advice = msg.advice;
            }
            // Report command failures back to client
            if (msg.successful != null && msg.successful == false) {
                if ( _clientDebugHandler != null ) {
                    _clientDebugHandler.call(this, "" + msg.channel + " error:" + msg.error); 
                }
            }
            // Messages on non-meta channels are event broadcasts, so notify subscribers
            if (msg.channel != null && (msg.channel as String).indexOf("/meta/") != 0) {
                for (var i:int=0; i < _subscriptionListeners.length; ++i) {
                    var subscription:Object = _subscriptionListeners[i];
                    if ( channelMatchesSubscription( msg.channel, subscription ) ) {
                        subscription.cb.call( subscription.that, msg );
                    }
                }
            }
        }        
    }
    
    private function httpFaultHandler(evt:FaultEvent):void {
        debugOutput( "httpFaultHandler(): " + evt.fault );
        for each( var f:Function in _faultListeners ) {
            f(evt.fault, evt.message, evt.target);
        }
    }
    
    private function sendMessage(http:HTTPService, msg:Object):AsyncToken {
        var json:String = JSON.encode( [ msg ] );
        var params:Object = { message: json };
        return http.send(params);
    }
    
    // Returns an array of Bayeux messages
    private function parseResult(evt:ResultEvent):Array {
        // TODO: explicitly handle commented json..
        var result:String = String(evt.result);
        result = result.slice(result.indexOf("["), result.lastIndexOf("]")+1);
        var decodedJSON:Object = JSON.decode(result);
        return ArrayUtil.toArray(decodedJSON);
    }
    
    // Tests whether a channel matches a subscription.
    private function channelMatchesSubscription( channel:String, subscription:Object ):Boolean {
        var subscriptionChannel:String = subscription.channel;
        
        if ( subscriptionChannel == channel ) {
            debugOutput("Channel=" + channel + " matches sub=" + subscriptionChannel); 
            return true;
        }
        else if ( subscription.star == true ) {
            if ( channel.length > subscriptionChannel.length &&
                 channel.substr(0, subscriptionChannel.length) == subscriptionChannel && // channel begins with subscription root
                 channel.indexOf("/", subscriptionChannel.length) == -1 ) { // channel has no additional segments after subscription root
                debugOutput("Channel=" + channel + " matches sub=" + subscriptionChannel + "*"); 
                return true;
            }
        }
        else if ( subscription.starstar == true ) {
            if ( channel.length > subscriptionChannel.length &&
                 channel.substr(0, subscriptionChannel.length) == subscriptionChannel ) { // channel begins with subscription root
                debugOutput("Channel=" + channel + " matches sub=" + subscriptionChannel + "**"); 
                return true;
            }
        }
        return false;
    }
    
    private function debugOutput(msg:String):void {
        if ( _clientDebugHandler != null ) {
            var date:Date = new Date();
            _clientDebugHandler.call(this, date.toTimeString() + ": " + msg);
        }
    }
}

}

