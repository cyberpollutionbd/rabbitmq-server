%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2014 GoPivotal, Inc.  All rights reserved.
%%

-module(truncate).

-define(ELLIPSIS_LENGTH, 3).

-export([log_event/3]).
%% exported for testing
-export([test/0]).

log_event({Type, GL, {Pid, Format, Args}}, Size, Decr)
  when Type =:= error orelse
       Type =:= info_msg orelse
       Type =:= warning_msg ->
    {Type, GL, {Pid, Format, [term(T, Size, Decr) || T <- Args]}};
log_event({Type, GL, {Pid, ReportType, Report}}, Size, Decr)
  when Type =:= error_report orelse
       Type =:= info_report orelse
       Type =:= warning_report ->
    {Type, GL, {Pid, ReportType, report(Report, Size, Decr)}};
log_event(Event, _Size, _Decr) ->
    Event.

report([[Thing]], Size, Decr) -> report([Thing], Size, Decr);
report(List, Size, Decr)      -> [case Item of
                                      {K, V} -> {K, term(V, Size, Decr)};
                                      _      -> term(Item, Size, Decr)
                                  end || Item <- List].

term(Bin, N, _D) when is_binary(Bin) andalso size(Bin) > N - ?ELLIPSIS_LENGTH ->
    Suffix = without_ellipsis(N),
    <<Head:Suffix/binary, _/binary>> = Bin,
    <<Head/binary, <<"...">>/binary>>;
term(L, N, D) when is_list(L) ->
    case io_lib:printable_list(L) of
        true  -> N2 = without_ellipsis(N),
                 case length(L) > N2 of
                     true  -> string:left(L, N2) ++ "...";
                     false -> L
                 end;
        false -> shrink_list(L, N, D)
    end;
term(T, N, D) when is_tuple(T) ->
    list_to_tuple(shrink_list(tuple_to_list(T), N, D));
term(T, _, _) ->
    T.

without_ellipsis(N) -> erlang:max(N - ?ELLIPSIS_LENGTH, 0).

shrink_list(_, N, _) when N =< 0 ->
    ['...'];
shrink_list([], _N, _D) ->
    [];
shrink_list([H|T], N, D) ->
    [term(H, N - D, D) | term(T, N - 1, D)].

%%----------------------------------------------------------------------------

test() ->
    test_short_examples_exactly(),
    test_large_examples_for_size(),
    ok.

test_short_examples_exactly() ->
    F = fun (Term, Exp) -> Exp = term(Term, 10, 5) end,
    F([], []),
    F("h", "h"),
    F("hello world", "hello w..."),
    F([[h,e,l,l,o,' ',w,o,r,l,d]], [[h,e,l,l,o,'...']]),
    F([a|b], [a|b]),
    F([<<"hello world">>], [<<"he...">>]),
    F({{{{a}}},{b},c,d,e,f,g,h,i,j,k}, {{{'...'}},{b},c,d,e,f,g,h,i,j,'...'}),
    P = spawn(fun() -> receive die -> ok end end),
    F([0, 0.0, <<1:1>>, F, P], [0, 0.0, <<1:1>>, F, P]),
    P ! die,
    ok.

test_large_examples_for_size() ->
    Shrink = fun(Term) -> term(Term, 100, 5) end, %% Real world values
    TestSize = fun(Term) ->
                       true = 5000000 < size(term_to_binary(Term)),
                       true = 500000 > size(term_to_binary(Shrink(Term)))
               end,
    TestSize(lists:seq(1, 5000000)),
    TestSize(recursive_list(1000, 10)),
    TestSize(recursive_list(5000, 20)),
    TestSize(gb_sets:from_list([I || I <- lists:seq(1, 1000000)])),
    TestSize(gb_trees:from_orddict([{I, I} || I <- lists:seq(1, 1000000)])),
    ok.

recursive_list(S, 0) -> lists:seq(1, S);
recursive_list(S, N) -> [recursive_list(S div N, N-1) || _ <- lists:seq(1, S)].