%%%-------------------------------------------------------------------
%%% File    : cpl_db.erl
%%% Author  : Håkan Stenholm <hsten@it.su.se>
%%% Descrip.: This module handles storage and loading of cpl scripts.
%%%           to disk (and erlang shell).
%%%
%%% Created : 17 Dec 2004 by Håkan Stenholm <hsten@it.su.se>
%%%-------------------------------------------------------------------
-module(cpl_db).

%%--------------------------------------------------------------------
%% External exports
%%--------------------------------------------------------------------
-export([
	 create/0,
	 create/1,
	 load_cpl_for_user/2,
	 set_cpl_for_user/2,
	 get_cpl_for_user/1,
	 get_cpl_text_for_user/1,
	 user_has_cpl_script/1,
	 user_has_cpl_script/2,
	 rm_cpl_for_user/1,
	 get_transform_fun/0
	]).

%%--------------------------------------------------------------------
%% Internal exports
%%--------------------------------------------------------------------
-export([

        ]).

%%--------------------------------------------------------------------
%% Include files
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Records
%%--------------------------------------------------------------------

-record(cpl_script_graph, {
	  user,		%% string(), username
	  graph,	%% term(), parsed CPL script
	  text		%% string(), CPL script before parsing
	 }).

%%--------------------------------------------------------------------
%% Macros
%%--------------------------------------------------------------------

%%====================================================================
%% External functions
%%====================================================================

%%--------------------------------------------------------------------
%% Function: create()
%% Descrip.: Invoke create/1 with the list of servers indicated by
%%           the configuration parameter 'databaseservers'.
%% Returns : term(), result of mnesia:create_table/2.
%%--------------------------------------------------------------------
create() ->
    {ok, S} = yxa_config:get_env(databaseservers),
    create(S).

%%--------------------------------------------------------------------
%% Function: create(Servers)
%%           Servers = list() of atom(), list of nodes
%% Descrip.: Put cpl_script_graph table as disc_copies on Servers
%% Returns : term(), result of mnesia:create_table/2.
%%--------------------------------------------------------------------
create(Servers) ->
    mnesia:create_table(cpl_script_graph, [{attributes, record_info(fields, cpl_script_graph)},
					   {disc_copies, Servers}
					   %% type = set, mnesia default
					  ]).


%%--------------------------------------------------------------------
%% Function: get_cpl_for_user(User)
%% Descrip.: get the cpl script graph for a certain user
%% Returns : nomatch | {ok, CPLGraph}
%%           CPLGraph = term(), a cpl graph for use in
%%                              interpret_cpl:process_cpl_script(...)
%%--------------------------------------------------------------------
get_cpl_for_user(User) ->
    case mnesia:dirty_read({cpl_script_graph, User}) of
	[] -> nomatch;
	[Rec] -> {ok, Rec#cpl_script_graph.graph}
    end.

%%--------------------------------------------------------------------
%% Function: get_cpl_text_for_user(User)
%% Descrip.: Get the CPL script for User as text.
%% Returns : nomatch | {ok, CPLText}
%%           CPLText = string(), the CPL XML
%%--------------------------------------------------------------------
get_cpl_text_for_user(User) ->
    case mnesia:dirty_read({cpl_script_graph, User}) of
	[] -> nomatch;
	[Rec] -> {ok, Rec#cpl_script_graph.text}
    end.

%%--------------------------------------------------------------------
%% Function: load_cpl_for_user(User, FilePath)
%%           FilePath = string(), a full file path (no .|..|~)
%% Descrip.: store the cpl script file at FilePath in mnesia
%% Returns : {atomic, Result}
%%           Result = ok | term()
%%--------------------------------------------------------------------
load_cpl_for_user(User, FilePath) ->
    Str = load_file(FilePath),
    Graph = xml_parse:cpl_script_to_graph(Str),
    store_graph(User, Graph, Str).

%%--------------------------------------------------------------------
%% Function: set_cpl_for_user(User, CPLXML)
%%           User   = string()
%%           CPLXML = string(), CPL XML
%% Descrip.: store the cpl script CPLXML in mnesia
%% Returns : {atomic, Result}
%%           Result = ok | term()
%%--------------------------------------------------------------------
set_cpl_for_user(User, CPLXML) when is_list(User), is_list(CPLXML) ->
    Graph = xml_parse:cpl_script_to_graph(CPLXML),
    store_graph(User, Graph, CPLXML).

store_graph(User, Graph, Text) ->
    F = fun() ->
		mnesia:write(#cpl_script_graph{user  = User,
					       graph = Graph,
					       text  = Text}
			    )
	end,
    mnesia:transaction(F).

%%--------------------------------------------------------------------
%% Function: rm_cpl_for_user(User)
%% Descrip.: remove the cpl script associated with user User
%% Returns : {atomic, ok} | term()
%%--------------------------------------------------------------------
rm_cpl_for_user(User) ->
    F = fun() ->
		mnesia:delete({cpl_script_graph, User})
	end,
    mnesia:transaction(F).

%%--------------------------------------------------------------------
%% Function: user_has_cpl_script(User)
%%           User = string(), username
%% Descrip.: determine if a cpl script has been loaded for the user
%%           User. Type is used to determine if script can handle
%%           incoming or outgoing traffic - it may be able to do both
%% Returns : true | false
%%--------------------------------------------------------------------
user_has_cpl_script(User) ->
    case mnesia:dirty_read({cpl_script_graph, User}) of
	[] ->
	     false;
	[_] ->
	    true
    end.

%%--------------------------------------------------------------------
%% Function: user_has_cpl_script(User, Type)
%%           User = string(), username
%%           Type = incoming | outgoing
%% Descrip.: determine if a cpl script has been loaded for the user
%%           User. Type is used to determine if script can handle
%%           incoming or outgoing traffic - it may be able to do both
%% Returns : true | false
%%--------------------------------------------------------------------
user_has_cpl_script(User, Type) ->
    case mnesia:dirty_read({cpl_script_graph, User}) of
	[] ->
	     false;
	[Rec] ->
	    Graph = Rec#cpl_script_graph.graph,
	    Index = interpret_cpl:get_start_node(Type),
	    try begin
		    interpret_cpl:get_node(Graph, Index),
		    %% no exception so node exists
		    true
		end
	    catch
		throw: _ -> false
	    end
    end.


%%--------------------------------------------------------------------
%% Function: get_transform_fun()
%% Descrip.: Return a function to transform the cpl_script_graph
%%           Mnesia table.
%% Returns : {ok, Fun}
%%--------------------------------------------------------------------
get_transform_fun() ->
    Table = cpl_script_graph,
    F = fun
	    %% check for old cpl_script_graph lacking text element
	    ({cpl_script_graph, User, Graph}) ->
		put({Table, update}, true),
		{cpl_script_graph, User, Graph, ""};
	    (CPL) when is_record(CPL, cpl_script_graph) ->
		%% nothing to update
		CPL
	end,
    {ok, record_info(fields, cpl_script_graph), F}.

%%====================================================================
%% Behaviour functions
%%====================================================================

%%====================================================================
%% Internal functions
%%====================================================================

%%--------------------------------------------------------------------
%% Function: load_file(FilePath)
%%           FilePath = string(), a full file path (no .|..|~)
%% Descrip.: get data from file a FilePath
%% Returns : string()
%%--------------------------------------------------------------------
load_file(FilePath) ->
    case file:read_file(FilePath) of
	{ok, Binary} ->
	    binary_to_list(Binary);
	{error, Reason} ->
	    throw({error, Reason})
    end.
