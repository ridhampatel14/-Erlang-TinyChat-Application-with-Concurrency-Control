-module(server).

-export([start_server/0]).

-include_lib("./defs.hrl").

-spec start_server() -> _.
-spec loop(_State) -> _.
-spec do_join(_ChatName, _ClientPID, _Ref, _State) -> _.
-spec do_leave(_ChatName, _ClientPID, _Ref, _State) -> _.
-spec do_new_nick(_State, _Ref, _ClientPID, _NewNick) -> _.
-spec do_client_quit(_State, _Ref, _ClientPID) -> _NewState.

start_server() ->
    catch(unregister(server)),
    register(server, self()),
    case whereis(testsuite) of
	undefined -> ok;
	TestSuitePID -> TestSuitePID!{server_up, self()}
    end,
    loop(
      #serv_st{
	 nicks = maps:new(), %% nickname map. client_pid => "nickname"
	 registrations = maps:new(), %% registration map. "chat_name" => [client_pids]
	 chatrooms = maps:new() %% chatroom map. "chat_name" => chat_pid
	}
     ).

loop(State) ->
    receive 
	%% initial connection
	{ClientPID, connect, ClientNick} ->
	    NewState =
		#serv_st{
		   nicks = maps:put(ClientPID, ClientNick, State#serv_st.nicks),
		   registrations = State#serv_st.registrations,
		   chatrooms = State#serv_st.chatrooms
		  },
	    loop(NewState);
	%% client requests to join a chat
	{ClientPID, Ref, join, ChatName} ->
	    NewState = do_join(ChatName, ClientPID, Ref, State),
	    loop(NewState);
	%% client requests to join a chat
	{ClientPID, Ref, leave, ChatName} ->
	    NewState = do_leave(ChatName, ClientPID, Ref, State),
	    loop(NewState);
	%% client requests to register a new nickname
	{ClientPID, Ref, nick, NewNick} ->
	    NewState = do_new_nick(State, Ref, ClientPID, NewNick),
	    loop(NewState);
	%% client requests to quit
	{ClientPID, Ref, quit} ->
	    NewState = do_client_quit(State, Ref, ClientPID),
	    loop(NewState);
	{TEST_PID, get_state} ->
	    TEST_PID!{get_state, State},
	    loop(State)
    end.

%% executes join protocol from server perspective
do_join(ChatName, ClientPID, Ref, State) ->
    % io:format("server:do_join(...): IMPLEMENT ME~n"),
    % State.
    Chatrooms = State#serv_st.chatrooms,
    Registrations = State#serv_st.registrations,
    Nicks = State#serv_st.nicks,
    case maps:get(ChatName, Chatrooms, ChatName) of
        ChatName -> 
            ChatroomPID = spawn(chatroom, start_chatroom, [ChatName]),
            NewChatrooms = maps:put(ChatName, ChatroomPID, Chatrooms),
            NewRegistrations = maps:put(ChatName, [], Registrations),
            NewState = State#serv_st{chatrooms = NewChatrooms, registrations = NewRegistrations},
            do_join(ChatName, ClientPID, Ref, NewState);
        ChatroomPid -> 
            Nickname = maps:get(ClientPID, Nicks),
            ChatroomPid ! {self(), Ref, register, ClientPID, Nickname},
            UpdatedRegistrations = maps:put(
                ChatName,
                maps:get(ChatName, Registrations) ++ [ClientPID],
                Registrations
            ),
            NewState = State#serv_st{registrations = UpdatedRegistrations},
			NewState
    end.

%% executes leave protocol from server perspective
do_leave(ChatName, ClientPID, Ref, State) ->
    % io:format("server:do_leave(...): IMPLEMENT ME~n"),
    % State.
	ChatroomPID = maps:get(ChatName, State#serv_st.chatrooms), 
    UpdatedRegistrations = maps:update(
        ChatName,
        lists:delete(ClientPID, maps:get(ChatName, State#serv_st.registrations)),
        State#serv_st.registrations
    ),
    NewState = State#serv_st{registrations = UpdatedRegistrations},
    ChatroomPID ! {self(), Ref, unregister, ClientPID},
    ClientPID ! {self(), Ref, ack_leave},
    NewState.

%% executes new nickname protocol from server perspective
do_new_nick(State, Ref, ClientPID, NewNick) ->
    % io:format("server:do_new_nick(...): IMPLEMENT ME~n"),
    % State.
	Nicks = State#serv_st.nicks,
    Chatrooms = State#serv_st.chatrooms,
    Registrations = State#serv_st.registrations,
    case lists:any(fun(X) -> X == NewNick end, maps:values(Nicks)) of
        true -> 
            ClientPID ! {self(), Ref, err_nick_used},
            UpdatedState = State;
        false -> 
            UpdatedNicks = maps:update(ClientPID, NewNick, Nicks),
            UpdatedState = State#serv_st{nicks = UpdatedNicks},
            ChatroomNames = maps:keys(Chatrooms),
            lists:map(
                fun(ChatroomName) ->
                    case maps:find(ChatroomName, Registrations) of 
                        {ok, ClientPIDs} -> 
                            case lists:any(fun(X) -> X == ClientPID end, ClientPIDs) of 
                                true -> 
                                    case maps:find(ChatroomName, Chatrooms) of 
                                        {ok, ChatroomPID} -> 
                                            ChatroomPID ! {self(), Ref, update_nick, ClientPID, NewNick}
                                    end;
                                false -> pass
                            end
                    end
                end,
                ChatroomNames
            ),
            ClientPID ! {self(), Ref, ok_nick}
    end,
    UpdatedState.

%% executes client quit protocol from server perspective
do_client_quit(State, Ref, ClientPID) ->
    % io:format("server:do_client_quit(...): IMPLEMENT ME~n"),
    % State.
 	Nicks = State#serv_st.nicks,
    Registrations = State#serv_st.registrations,
    Chatrooms = State#serv_st.chatrooms,
    NewNicks = maps:remove(ClientPID, Nicks),
    NewRegistrations = maps:map(fun(X, Y) when is_list(X) -> lists:delete(ClientPID, Y) end, Registrations),
    lists:map(
        fun(ChatroomName) ->
            case maps:find(ChatroomName, Registrations) of 
                {ok, ClientPIDs} -> 
                    case lists:any(fun(X) -> X == ClientPID end, ClientPIDs) of 
                        true -> 
                            case maps:find(ChatroomName, Chatrooms) of 
                                {ok, ChatroomPID} -> 
                                    ChatroomPID ! {self(), Ref, unregister, ClientPID}
                            end;
                        false -> pass
                    end
            end
        end,
        maps:keys(Chatrooms)
    ),
    ClientPID ! {self(), Ref, ack_quit},
    NewState = State#serv_st{nicks = NewNicks, registrations = NewRegistrations},
	NewState.
