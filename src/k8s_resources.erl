-module(k8s_resources).

-export([get/2, get/3, list/1, list/2,
         create/2, create/3, delete/2, delete/3]).

-export_type([get_options/0, list_options/0,
              create_options/0, delete_options/0]).

-type get_options() ::
        #{context => k8s_config:context_name(),
          namespace => binary()}.

-type list_options() ::
        #{context => k8s_config:context_name(),
          namespace => binary()}.

-type create_options() ::
        #{context => k8s_config:context_name(),
          namespace => binary(),
          dry_run => boolean()}.

-type delete_options() ::
        #{context => k8s_config:context_name(),
          namespace => binary(),
          dry_run => boolean()}.

-spec get(k8s_resource:name(), k8s_resource:type()) ->
        {ok, k8s_resource:resource()} | {error, term()}.
get(Name, Type) ->
  get(Name, Type, #{}).

-spec get(k8s_resource:name(), k8s_resource:type(), get_options()) ->
        {ok, k8s_resource:resource()} | {error, term()}.
get(Name, Type, Options) ->
  ResourceDef = k8s_resource_registry:resource_definition(Type),
  Namespace = maps:get(namespace, Options, undefined),
  BasePath = resource_path(ResourceDef, Namespace),
  Path = iolist_to_binary([BasePath, $/, Name]),
  Request = #{method => <<"GET">>, target => Path},
  SendRequestOptions = maps:with([context], Options),
  send_request(Type, Request, SendRequestOptions).

-spec list(k8s_resource:type()) ->
        {ok, k8s_resource:resource()} | {error, term()}.
list(Type) ->
  list(Type, #{}).

-spec list(k8s_resource:type(), list_options()) ->
        {ok, k8s_resource:resource()} | {error, term()}.
list(Type, Options) ->
  ResourceDef = k8s_resource_registry:resource_definition(Type),
  Namespace = maps:get(namespace, Options, undefined),
  BasePath = resource_path(ResourceDef, Namespace),
  Path = iolist_to_binary(BasePath),
  Request = #{method => <<"GET">>, target => Path},
  SendRequestOptions = maps:with([context], Options),
  send_request(Type, Request, SendRequestOptions).

-spec create(k8s_resource:resource(), k8s_resource:type()) ->
        {ok, k8s_resource:resource()} | {error, term()}.
create(Resource, Type) ->
  create(Resource, Type, #{}).

-spec create(k8s_resource:resource(), k8s_resource:type(), create_options()) ->
        {ok, k8s_resource:resource()} | {error, term()}.
create(Resource, Type, Options) ->
  ResourceDef = k8s_resource_registry:resource_definition(Type),
  Namespace = maps:get(namespace, Options, undefined),
  BasePath = resource_path(ResourceDef, Namespace),
  Path = iolist_to_binary(BasePath),
  Body = k8s_resource:encode(Type, Resource),
  Query = create_request_query(Options),
  Request = #{method => <<"POST">>,
              target => #{path => Path, query => Query},
              body => Body},
  SendRequestOptions = maps:with([context], Options),
  send_request(Type, Request, SendRequestOptions).

-spec create_request_query(create_options()) -> uri:query().
create_request_query(Options) ->
  maps:fold(fun
              (dry_run, true, Acc) ->
               [{<<"dryRun">>, <<"All">>} | Acc];
              (_, _, Acc) ->
               Acc
           end, [], Options).

-spec delete(k8s_resource:name(), k8s_resource:type()) ->
        {ok, k8s_resource:resource()} | {error, term()}.
delete(Name, Type) ->
  delete(Name, Type, #{}).

-spec delete(k8s_resource:name(), k8s_resource:type(), delete_options()) ->
        {ok, k8s_resource:resource()} | {error, term()}.
delete(Name, Type, Options) ->
  ResourceDef = k8s_resource_registry:resource_definition(Type),
  Namespace = maps:get(namespace, Options, undefined),
  BasePath = resource_path(ResourceDef, Namespace),
  Path = iolist_to_binary([BasePath, $/, Name]),
  Query = delete_request_query(Options),
  Request = #{method => <<"DELETE">>,
              target => #{path => Path, query => Query}},
  SendRequestOptions = maps:with([context], Options),
  send_request(Type, Request, SendRequestOptions).

-spec delete_request_query(delete_options()) -> uri:query().
delete_request_query(Options) ->
  maps:fold(fun
              (dry_run, true, Acc) ->
               [{<<"dryRun">>, <<"All">>} | Acc];
              (_, _, Acc) ->
               Acc
           end, [], Options).

-spec send_request(k8s_resource:type(),
                   mhttp:request(), k8s_http:request_options()) ->
        {ok, k8s_resource:resource()} | {error, term()}.
send_request(OutputType, Request, Options) ->
  case k8s_http:send_request(Request, Options) of
    {ok, Response} ->
      Body = mhttp_response:body(Response),
      case mhttp_response:status(Response) of
        Status when Status < 200; Status > 299 ->
          case k8s_resource:decode(status_v1, Body) of
            {ok, StatusResource} ->
              {error, {request_failure, StatusResource}};
            {error, _} ->
              {error, {request_failure, Status, Body}}
          end;
        _ ->
          k8s_resource:decode(OutputType, Body)
      end;
    {error, Reason} ->
      {error, Reason}
  end.

-spec resource_path(k8s_resource:definition(),
                   Namespace :: binary() | undefined) -> iolist().
resource_path(Def = #{path := Path}, Namespace) ->
  case Namespace of
    undefined ->
      [base_resource_path(Def), $/, Path];
    _ ->
      [base_resource_path(Def), "/namespaces/", Namespace, $/, Path]
  end.

-spec base_resource_path(k8s_resource:definition()) -> iolist().
base_resource_path(Def = #{version := Version}) ->
  case maps:get(group, Def) of
    <<"io.k8s.api.core">> ->
      ["/api/", Version];
    Group ->
      ["/apis/", Group, $/, Version]
  end.
