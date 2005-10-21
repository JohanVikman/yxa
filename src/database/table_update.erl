%% this code updates older database tables - code commited before
%% 25-10-2004
%%
%%--------------------------------------------------------------------

-module(table_update).

%%--------------------------------------------------------------------
%% External exports
%%--------------------------------------------------------------------

-export([
	 update/0
	]).

%%--------------------------------------------------------------------
%% Internal exports
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Include files
%%--------------------------------------------------------------------
-include("phone.hrl").
-include("siprecords.hrl").
-include("database_regexproute.hrl").

%%--------------------------------------------------------------------
%% Records
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Macros
%%--------------------------------------------------------------------

%%====================================================================
%% External functions
%%====================================================================

%%--------------------------------------------------------------------
%% Function:
%% Descrip.: update databases
%% Returns : ok
%%--------------------------------------------------------------------
update() ->
    logger:log(debug, "Checking if any mnesia tables needs updating"),
    phone(),
    regexproute(),
    ok.

%%--------------------------------------------------------------------
%% Function:
%% Descrip.: phone record got two new fields, add dummy fields for old
%%           existing database entries
%% Returns :
%%--------------------------------------------------------------------
phone() ->
    put(update, false),
    F = fun
	    %% check for old record lacking callid and cseq field
	    ({phone, Number, Flags, Class, Expire, Address, ReqUriStr}) ->
		put(update, true),
		#phone{
		     number = Number,
		     flags = Flags,
		     class = Class,
		     expire = Expire,
		     address = Address,
		     requristr = ReqUriStr,
		     callid = "",
		     cseq = 0
		    };
	    %% debug related patch - to fix when new phone entries got improperly updated -
	    %% forgot setting CallId and CSeq field values
	    ({phone, Number, Flags, Class, Expire, Address, ReqUriStr, undefined, undefined}) ->
		put(update, true),
		#phone{
		     number = Number,
		     flags = Flags,
		     class = Class,
		     expire = Expire,
		     address = Address,
		     requristr = ReqUriStr,
		     callid = "",
		     cseq = 0
		    };
	    %% nothing to update
	    ({phone, _Number, _Flags, _Class, _Expire, _Address, _ReqUriStr, _CallId, _CSeq} = Phone) ->
		Phone
	end,
    case mnesia:transform_table(phone, F, record_info(fields, phone)) of
	{atomic, ok} ->
	    ok;
	{aborted, {not_active, Reason, phone, _NodeList}} ->
	    %% All disc_copies nodes must be online for table transforming, but we can't require
	    %% all those nodes to be alive in order to start the Yxa servers.
	    logger:log(normal, "Warning: Failed to update Mnesia table 'phone' : ~s", [Reason]),
	    ok
    end,

    case erase(update) of
	true ->
	    logger:log(debug, "phone: updated");
	false ->
	    true
    end.

%%--------------------------------------------------------------------
%% Function:
%% Descrip.: update the sipurl record() in the regexproute, and store
%%           it as a string instead of as a record.
%% Returns :
%%--------------------------------------------------------------------
regexproute() ->
    put(update, false),
    F = fun
	    %% check for old sipurl's lacking url_param field
	    ({regexproute, Regexp, Flags,  Class,  Expire,
	      {sipurl, Proto, User, Pass, Host, Port, Param}
	     }) ->
		put(update, true),
		%% fixes so that url_param record is used
		URL = sipurl:new([{proto, Proto}, {user, User}, {pass, Pass},
				  {host, Host}, {port, Port}, {param, Param}]),
		%% store as string instead of record, so that we don't have to do
		%% conversions like this in the future when we modify records
		URLstr = sipurl:print(URL),
		#regexproute{
		     regexp = Regexp,
		     flags = Flags,
		     class = Class,
		     expire = Expire,
		     address = URLstr
		    };
	    %% check for sipurl's with both param and url_param field
	    ({regexproute, Regexp, Flags,  Class,  Expire,
	      {sipurl, Proto, User, Pass, Host, Port, _Param, UrlParam}
	     }) ->
		put(update, true),
		URL = sipurl:new([{proto, Proto}, {user, User}, {pass, Pass},
				  {host, Host}, {port, Port}, {param, UrlParam}]),
		%% store as string instead of record, so that we don't have to do
		%% conversions like this in the future when we modify records
		URLstr = sipurl:print(URL),
		#regexproute{
		     regexp = Regexp,
		     flags = Flags,
		     class = Class,
		     expire = Expire,
		     address = URLstr
		    };
	    %% nothing to update
	    (RegExpRoute) when is_record(RegExpRoute, regexproute) ->
		RegExpRoute
	end,
    case mnesia:transform_table(regexproute, F, record_info(fields, regexproute)) of
	{atomic, ok} ->
	    ok;
	{aborted, {not_active, Reason, regexproute, _NodeList}} ->
	    %% All disc_copies nodes must be online for table transforming, but we can't require
	    %% all those nodes to be alive in order to start the Yxa servers.
	    logger:log(normal, "Warning: Failed to update Mnesia table 'regexproute' : ~s", [Reason]),
	    ok
    end,

    case erase(update) of
	true ->
	    logger:log(debug, "regexproute: updated");
	false ->
	    true
    end.

%%====================================================================
%% Behaviour functions
%%====================================================================

%%--------------------------------------------------------------------
%% Function:
%% Descrip.:
%% Returns :
%%--------------------------------------------------------------------

%%====================================================================
%% Internal functions
%%====================================================================
