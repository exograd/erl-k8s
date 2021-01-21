-module(k8sc_object_meta_v1).

-behaviour(k8sc_resource).

-export([jsv_definition/0]).

-export_type([object_meta/0]).

-type object_meta() ::
        #{name => binary(),
          annotations => #{binary() := binary()},
          labels => #{binary() := binary()},
          resource_version => string()}.

-spec jsv_definition() -> jsv:definition().
jsv_definition() ->
  {object,
   #{members =>
       #{name => string,
         annotations => {object, #{value => string}},
         labels => {object, #{value => string}},
         resource_version => string},
     required =>
       []}}.