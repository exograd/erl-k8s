-module(k8s_resources).

-export([get/3, create/3, delete/3, update/4,
         collection_path/2, path/3,
         definition/1]).

-export_type([id/0, definition/0, name/0, resource/0,
             options/0, get_options/0, create_options/0, delete_options/0]).

-type id() :: core_v1_namespace. % TODO k8s_model:id().

-type definition() ::
    #{path_name := binary(),
      group => binary(),
      version => binary(),
      global => boolean()}.

-type name() :: binary().
-type resource() :: #{}.

-type options() ::
        #{context => k8s_config:context_name(),
          namespace => binary()}.

-type get_options() ::
        #{context => k8s_config:context_name(),
          namespace => binary()}.

-type create_options() ::
        #{context => k8s_config:context_name(),
          namespace => binary()}.

-type delete_options() ::
        #{context => k8s_config:context_name(),
          namespace => binary()}.

-spec get(id(), name(), get_options()) -> k8s:result(resource()).
get(Id, Name, Options) ->
  Request = #{method => <<"GET">>,
              target => path(Id, Name, Options)},
  send_request(Request, Id, Options).

-spec create(id(), resource(), create_options()) -> k8s:result(resource()).
create(Id, Resource, Options) ->
  Request = #{method => <<"POST">>,
              target => collection_path(Id, Options),
              body => encode_resource(Resource, {ref, k8s, Id})},
  send_request(Request, Id, Options).

-spec delete(id(), name(), delete_options()) -> k8s:result(resource()).
delete(Id, Name, Options) ->
  Request = #{method => <<"DELETE">>,
              target => path(Id, Name, Options)},
  send_request(Request, Id, Options).

-spec update(id(), name(), resource(), create_options()) -> k8s:result(resource()).
update(Id, Name, Resource, Options) ->
  Request = #{method => <<"PUT">>,
              target => path(Id, Name, Options),
              body => encode_resource(Resource, {ref, k8s, Id})},
  send_request(Request, Id, Options).

-spec send_request(mhttp:request(), id(), options()) -> k8s:result(resource()).
send_request(Request, Id, Options) ->
  RequestOptions = maps:with([context], Options),
  case k8s_http:send_request(Request, RequestOptions) of
    {ok, Response = #{status := Status}} when Status >= 200, Status < 300 ->
      decode_response_body(Response, {ref, k8s, Id});
    {ok, Response} ->
      decode_response_body(Response,
                           {ref, k8s, apimachinery_apis_meta_v1_status});
    {error, Reason} ->
      {error, Reason}
  end.

-spec encode_resource(resource(), jsv:definition()) -> iodata().
encode_resource(Resource, JSVDefinition) ->
  case jsv:generate(Resource, JSVDefinition) of
    {ok, Value} ->
      json:serialize(Value);
    {error, Reason} ->
      error({invalid_resource, Reason})
  end.

-spec decode_response_body(mhttp:response(), jsv:definition()) ->
        k8s:result(resource()).
decode_response_body(Response, JSVDefinition) ->
  case mhttp_response:body(Response) of
    <<>> ->
      {error, empty_response_body};
    Body ->
      case json:parse(Body) of
        {ok, Value} ->
          ValidationOptions = #{},
          case jsv:validate(Value, JSVDefinition, ValidationOptions) of
            {ok, Resource} ->
              {ok, Resource};
            {error, Errors} ->
              {error, {invalid_resource_data, Errors}}
          end;
        {error, Reason} ->
          {error, {invalid_json_data, Reason}}
      end
  end.

-spec collection_path(id(), options()) -> binary().
collection_path(Id, Options) ->
  Def = definition(Id),
  BasePath =
    case maps:find(group, Def) of
      {ok, Group} ->
        Version = maps:get(version, Def),
        ["/apis", Group, Version];
      error ->
        ["/api", "v1"]
    end,
  PathName = maps:get(path_name, Def),
  Path =
    case maps:get(global, Def, false) of
      true ->
        BasePath ++ [PathName];
      false ->
        Namespace = maps:get(namespace, Options),
        BasePath ++ ["namespaces", Namespace, PathName]
    end,
  iolist_to_binary(lists:join($/, Path)).

-spec path(id(), name(), options()) -> binary().
path(Id, Name, Options) ->
  BasePath = collection_path(Id, Options),
  <<BasePath/binary, $/, Name/binary>>.

-spec definition(id()) -> definition().
definition(core_v1_namespace) ->
  #{path_name => <<"namespaces">>,
    global => true};
definition(Id) ->
  error({unknown_resource, Id}).