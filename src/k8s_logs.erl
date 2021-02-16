-module(k8s_logs).

-export([fetch_pod_logs/2]).

-export_type([options/0]).

-type options() ::
        #{context => k8s_config:context_name(),
          namespace => binary(),
          container => binary(),
          timestamps => boolean()}.

-spec fetch_pod_logs(PodName :: binary(), options()) -> k8s:result(binary()).
fetch_pod_logs(PodName, Options) ->
  CollectionPathOptions = maps:with([namespace], Options),
  BaseTarget =
    k8s_resources:path(core_v1_pod, PodName, CollectionPathOptions),
  Target = <<BaseTarget/binary, "/log">>,
  Request0 = #{method => <<"GET">>,
               target => Target},
  Request = lists:foldl(fun (F, Req) -> F(Req, Options) end,
                        Request0, [fun set_request_container/2,
                                   fun set_request_timestamps/2]),
  RequestOptions = maps:with([context], Options),
  case k8s_http:send_request(Request, RequestOptions) of
    {ok, Response = #{status := Status}} when Status >= 200, Status < 300 ->
      {ok, mhttp_response:body(Response)};
    {ok, Response = #{status := Status}} ->
      Definition = {ref, k8s, apimachinery_apis_meta_v1_status},
      case k8s_resources:decode_response_body(Response, Definition) of
        {ok, StatusData} ->
          {error, {request_error, Status, StatusData}};
        {error, Reason} ->
          {error, Reason}
      end;
    {error, Reason} ->
      {error, Reason}
  end.

-spec set_request_container(mhttp:request(), options()) -> mhttp:request().
set_request_container(Request, #{container := Container}) ->
  Target = mhttp_request:target_uri(Request),
  Query = [{<<"container">>, Container} | uri:query(Target)],
  Request#{target => Target#{query => Query}};
set_request_container(Request, _) ->
  Request.

-spec set_request_timestamps(mhttp:request(), options()) -> mhttp:request().
set_request_timestamps(Request, #{timestamps := true}) ->
  Target = mhttp_request:target_uri(Request),
  Query = [{<<"timestamps">>, <<"true">>} | uri:query(Target)],
  Request#{target => Target#{query => Query}};
set_request_timestamps(Request, _) ->
  Request.
