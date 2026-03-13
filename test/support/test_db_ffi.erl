-module(test_db_ffi).
-export([clone_db/1]).

%% Clone a template database into a fresh in-memory database using SQLite's
%% backup API (page-level copy). Takes a sqlight Connection as the template.
%% Returns {ok, NewConnection} | {error, Reason}.
clone_db(Template) ->
    {ok, Dest} = esqlite3:open(":memory:"),
    {ok, Backup} = esqlite3:backup_init(Dest, "main", Template, "main"),
    '$done' = esqlite3:backup_step(Backup, -1),
    ok = esqlite3:backup_finish(Backup),
    {ok, Dest}.
