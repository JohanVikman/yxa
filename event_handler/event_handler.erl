%%%-------------------------------------------------------------------
%%% File    : event_handler.erl
%%% Author  : Fredrik Thulin <ft@it.su.se>
%%% Descrip.: Event handler event manager. Receives all the events and
%%%           sends them on to all your configured event handlers.
%%%
%%% Created : 6 Dec 2004 by Fredrik Thulin <ft@it.su.se>
%%%-------------------------------------------------------------------
-module(event_handler).
%%-compile(export_all).

%%--------------------------------------------------------------------
%% External exports
%%--------------------------------------------------------------------
-export([
	 start_link/1,
	 stop/0,

	 generic_event/4,
	 generic_event/5,
	 new_request/4,
	 request_info/3,
	 uas_result/5,
	 uac_result/6
	]).

%%--------------------------------------------------------------------
%% Include files
%%--------------------------------------------------------------------
-include("siprecords.hrl").

%%--------------------------------------------------------------------
%% Records
%%--------------------------------------------------------------------
-record(state, {
	  appname,
	  handlers
	 }).

%%--------------------------------------------------------------------
%% Macros
%%--------------------------------------------------------------------
-define(SERVER, event_mgr).

%%====================================================================
%% External functions
%%====================================================================

%%--------------------------------------------------------------------
%% Function: start_link(AppName, Handlers)
%%           AppName  = string(), name of Yxa application
%%           Handlers = list() of atom(), configured handlers
%% Descrip.: start the server.
%% Returns : Result of gen_server:start_link/4
%%--------------------------------------------------------------------
start_link(AppName) ->
    Handlers = sipserver:get_env(event_handler_handlers, []),
    case gen_event:start_link({local, ?SERVER}) of
	{ok, Pid} ->
	    lists:map(fun(M) ->
			      gen_event:add_handler(?SERVER, M, [AppName])
		      end, Handlers),
	    {ok, Pid};
	Other ->
	    Other
    end.

stop() ->
    gen_event:stop(?SERVER).

generic_event(Prio, Class, Id, L) when is_atom(Prio), is_atom(Class),
				       is_list(Id); is_list(L) ->
    gen_event:notify(?SERVER, {event, self(), Prio, Class, Id, L}).

%% io_lib:format, then call generic_event/5
generic_event(Prio, Class, Id, Format, Args) when is_atom(Prio), is_atom(Class),
						  is_list(Format), is_list(Args) ->
    Str = io_lib:format(Format, Args),
    generic_event(Prio, Class, Id, [Str]).

%% New request has arrived, log a bunch of parameters about it
new_request(Method, URI, Branch, DialogId) when is_list(Method), is_record(URI, sipurl),
						is_list(Branch), is_tuple(DialogId) ->
    gen_event:notify(?SERVER, {event, self(), debug, new_request, Branch,
			       [{request_method, Method}, {request_uri, sipurl:print(URI)},
				{dialogid, DialogId}]}).

%% More information gathered about request
request_info(Prio, Branch, L) when is_atom(Prio), is_list(L) ->
    gen_event:notify(?SERVER, {event, self(), Prio, request_info, Branch, L}).

%% UAS has sent a result, URI = string()
uas_result(Branch, Created, Status, Reason, L) ->
    gen_server:cast(event_handler, {event, self(), debug, uas_result, Branch,
				    [Created, Status, Reason, L]}).

%% UAC has received a reply
uac_result(Branch, Method, URI, Status, Reason, L) ->
    L2 = [{request_method, Method}, {request_uri, URI} | L],
    gen_server:cast(event_handler, {event, self(), debug, uac_result, Branch,
				    [Status, Reason, L2]}).

%%====================================================================
%% Internal functions
%%====================================================================