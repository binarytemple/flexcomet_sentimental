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

public class CometClient
{
	public static const SUPPORTED_CONNECTION_TYPES:Array = ["long-polling"];
	public static const BAYEUX_VERSION:Number = 0.1;
	public static const BAYEUX_MIN_VERSION:Number = 0.1;
	
    ///////////////////////////////////////////////////////////////////////////////////////////////////////
	
    private var _httpTunnel:HTTPService;
    private var _httpCommand:HTTPService;
    private var _cometURL:String = null;
    private var _rootURL:String = null;
    
    // True if a successful /meta/connect has occurred (ie, we have a clientId, etc)
    private var _initialized:Boolean = false;
    
    // AsyncToken from handshake -> connect (different than connect -> reconnect)
    private var _initialConnectToken:AsyncToken;

    private var _version:Number = BAYEUX_VERSION;
    private var _minVersion:Number = BAYEUX_MIN_VERSION;
    private var _clientId:String;
    private var _advice:Object;
    private var _handshakeReturn:Object;
    
    // Array of functions w/ signature (fault:Fault, msg:Object, target:Object)
    // TODO: HTTP transport errors should be abstracted from CometClient users
    private var _faultListeners:Array = [];
    
    // Array of { channel:String, that:Object, cb:Function } where cb has sig (obj:Object)
    // TODO: Implement channel globbing, Subscription interface & impls with MessageDataEvent dispatching, etc
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
        
    public function init():void
    {
    	// Connection used for handshaking and tunnelling
    	// TODO: replace use of HTTPService with a self-contained HTTP client
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
        
        // Handshake w/ server
        var handshake:Object = {
            version: _version,
            minimumVersion: _minVersion,
            channel: BayeuxProtocol.META_HANDSHAKE,
            ext: { "json-comment-filtered": true },
            supportedConnectionTypes: SUPPORTED_CONNECTION_TYPES
        };
        
        sendMessage( _httpTunnel, handshake );
    }
    
    public function subscribe(ch:String, cb:Function, that:Object):void
    {
        if ( !_initialized ) {
	    	_pendingOperations.push([ this.subscribe, ch, cb, that ]);
	    	return;
	    }
	    
    	_subscriptionListeners.push( { channel: ch, that: that, cb: cb } );
    	
    	var subscribe:Object = {
    		channel: BayeuxProtocol.META_SUBSCRIBE,
    		clientId: _clientId,
    		subscription: ch
    	};
    	
    	// TODO: locally track existing subscriptions?

		sendMessage( _httpCommand, subscribe );
    }
    
    public function unsubscribe(ch:String):void
    {
        if ( !_initialized ) {
	    	_pendingOperations.push([ this.unsubscribe, ch ]);
	    	return;
	    }
	    
    	var unsubscribe:Object = {
    		channel: BayeuxProtocol.META_UNSUBSCRIBE,
    		clientId: _clientId,
    		subscription: ch
    	};
    	
		sendMessage( _httpCommand, subscribe );
    }
    
    public function publish(ch:String, data:Object):void
    {
        if ( !_initialized ) {
	    	_pendingOperations.push([ this.publish, ch, data ]);
	    	return;
        }
        
        trace( "publish(): ch=" + ch + " data=" + data );
        
    	var publish:Object = {
    		channel: ch,
    		clientId: _clientId, // optional, but easy for us
    		data: data
    	};
    	
		sendMessage( _httpCommand, publish );
	}
	
	public function disconnect():void
	{
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
		_initialized = false;
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
    	var messages:Array = parseResult(evt);
    	
    	// FIXME: Assuming handshake always returns just one message (is this per spec?)
        _handshakeReturn = messages[0];
        _advice = _handshakeReturn.advice;
        
        // Was handshake successful?
        if ( _handshakeReturn.successful != true ) {
        	// TODO: support more handshake failure cases
        	trace( "Handshake failed!  Msg=" + _handshakeReturn );
        	if ( _advice != null ) {
        		if ( _advice.reconnect == BayeuxProtocol.ADVICE_RECONNECT_RETRY ) {
			        var handshake:Object = {
			            version: _version,
			            minimumVersion: _minVersion,
			            channel: BayeuxProtocol.META_HANDSHAKE,
			            ext: { "json-comment-filtered": true },
			            supportedConnectionTypes: SUPPORTED_CONNECTION_TYPES
			        };
			        
			        sendMessage( _httpTunnel, handshake );
        		}
        	}
        }
    	
    	// handshake successful, switch to connection handler
    	_httpTunnel.removeEventListener(ResultEvent.RESULT, this.handshakeHandler);
    	_httpTunnel.addEventListener(ResultEvent.RESULT, this.connectHandler);
    	
        _clientId = _handshakeReturn.clientId;
        
    	
    	trace ( "handshakeHandler(): clientId=" + _clientId );
    	
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
    	var messages:Array = parseResult(evt);
    	
    	for each( var msg:Object in messages ) {
    		for (var i:int=0; i < _subscriptionListeners.length; ++i) {
    		    var subscription:Object = _subscriptionListeners[i];
    		    if ( subscription.channel == msg.channel ) {
    		    	subscription.cb.call( subscription.that, msg );
    		    }
			}
		}    	
    	
    	// Re-open tunnel
    	var reconnect:Object = {
    		channel: BayeuxProtocol.META_RECONNECT,
    		clientId: _clientId,
    		connectionType: BayeuxProtocol.TRANSPORT_LONGPOLLING
    	};
    	
    	sendMessage( _httpTunnel, reconnect );
    	
    	if (evt.token == _initialConnectToken) {
    		_initialized = true;
            _initialConnectToken = null;
            
            while (_pendingOperations.length > 0) {
            	var pendingOperation:Array = _pendingOperations.shift();
            	var func:Function = pendingOperation.shift();
            	func.apply(this, pendingOperation);
        	}
    	}
    }
    
    private function commandHandler(evt:ResultEvent):void {
    	var messages:Array = parseResult(evt);
    	trace( "commandHandler(): " + messages );
    	
    	// TODO: Handle command responses, check for errors..
    }
    
    private function httpFaultHandler(evt:FaultEvent):void {
    	trace( "httpFaultHandler(): " + evt.fault );
    	for each( var f:Function in _faultListeners ) {
    		f(evt.fault, evt.message, evt.target);
		}
    }
    
    private function sendMessage(http:HTTPService, msg:Object):AsyncToken {
    	var json:String = JSON.encode(msg);
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
}

}

