% Holds all runtime methods required to bootstrap the object model.
% These methods are overwritten by their Elixir version later in Object::Methods.
-module(elixir_object_methods).
-export([mixin/2, name/1,
  parent/1, parent_name/1, mixins/1, data/1, builtin_mixin/1,
  get_ivar/2, set_ivar/3, set_ivars/2, update_ivar/3, update_ivar/4]).
-include("elixir.hrl").

% MIXINS AND PROTOS

% TODO: Is this flag needed?

mixin(Self, Value) when is_list(Value) -> [mixin(Self, Item) || Item <- Value];
mixin(Self, Value) -> prepend_as(Self, object_mixins(Self), mixin, Value).

% Reflections

name(Self)   -> object_name(Self).
data(Self)   -> object_data(Self).
mixins(Self) -> object_mixins(Self).

parent(Self) ->
  case object_parent(Self) of
    nil -> nil;
    Object when is_atom(Object) -> elixir_constants:lookup(Object);
    Object -> Object
  end.

parent_name(Self) ->
  case object_parent(Self) of
    nil -> nil;
    Object when is_atom(Object) -> Object;
    _ -> nil
  end.

%% PROTECTED API

get_ivar(Self, Name) when is_atom(Name) ->
  elixir_helpers:orddict_find(Name, object_data(Self));

get_ivar(Self, Name) ->
  elixir_errors:error({badivar, Name}).

set_ivar(Self, Name, Value) when is_atom(Name) ->
  set_ivar_dict(Self, Name, set_ivar, fun(Dict) -> orddict:store(Name, Value, Dict) end).

set_ivars(Self, Value) ->
  assert_dict_with_atoms(Value),
  set_ivar_dict(Self, elixir, set_ivars, fun(Dict) -> elixir_helpers:orddict_merge(Dict, element(2, Value)) end).

update_ivar(Self, Name, Function) ->
  set_ivar_dict(Self, Name, update_ivar, fun(Dict) -> orddict:update(Name, Function, Dict) end).

update_ivar(Self, Name, Initial, Function) ->
  set_ivar_dict(Self, Name, update_ivar, fun(Dict) -> orddict:update(Name, Function, Initial, Dict) end).

% HELPERS

set_ivar_dict(_, Name, _, _) when not is_atom(Name) ->
  elixir_errors:error({badivar, Name});

set_ivar_dict(#elixir_slate__{data=Dict} = Self, Name, _, Function) ->
  Self#elixir_slate__{data=Function(Dict)};

set_ivar_dict(#elixir_object__{data=Dict} = Self, Name, _, Function) when not is_atom(Dict) ->
  Self#elixir_object__{data=Function(Dict)};

set_ivar_dict(#elixir_object__{data=Data} = Self, Name, _, Function) ->
  Dict = ets:lookup_element(Data, data, 2),
  Object = Self#elixir_object__{data=Function(Dict)},
  ets:insert(Data, { data, Object#elixir_object__.data }),
  Object;

set_ivar_dict(Self, _, Method, _) ->
  builtinnotallowed(Self, Method).

assert_dict_with_atoms(#elixir_orddict__{struct=Dict} = Object) ->
  case lists:all(fun is_atom/1, orddict:fetch_keys(Dict)) of
    true  -> Dict;
    false ->
      elixir_errors:error({badivars, Object})
  end;

assert_dict_with_atoms(Data) ->
  elixir_errors:error({badivars, Data}).

% Helper that prepends a mixin or a proto to the object chain.
prepend_as(Self, Chain, Kind, Value) ->
  check_module(Value, Kind),
  List = object_mixins(Value),

  % TODO: This does not consider modules available in the ancestor chain
  Object = update_object_chain(Self, Kind, umerge(List, Chain)),

  % Invoke the appropriate hook.
  elixir_dispatch:dispatch(Value, ?ELIXIR_ATOM_CONCAT(["__added_as_", atom_to_list(Kind), "__"]), [Object]).

% Update the given object chain. Sometimes it means we need to update
% the table, sometimes update a record.
update_object_chain(#elixir_object__{data=Data} = Self, Kind, Chain) when is_atom(Data) ->
  TableKind = ?ELIXIR_ATOM_CONCAT([Kind, s]),
  ets:insert(Data, {TableKind, Chain}),
  Self.

% Check if it is a module and raises an error if not.
check_module(#elixir_object__{parent='Module'}, Kind) -> [];
check_module(Else, Kind) -> elixir_errors:error({notamodule, {Kind, Else}}).

% Raise builtinnotallowed error with the given reason:
builtinnotallowed(Builtin, Reason) ->
  elixir_errors:error({builtinnotallowed, {Reason, Builtin}}).

% Methods that get values from objects. Argument can either be an
% #elixir_object__ or an erlang native type.

object_name(#elixir_object__{name=Name}) ->
  Name;

object_name(Native) ->
  nil. % Native and short objects has no name.

object_parent(#elixir_object__{parent=Parent}) ->
  Parent;

object_parent(Native) when is_integer(Native) ->
  'Integer';

object_parent(Native) when is_float(Native) ->
  'Float';

object_parent(Native) when is_atom(Native) ->
  'Atom';

object_parent(Native) when is_list(Native) ->
  'List';

object_parent(Native) when is_binary(Native) ->
  'String';

object_parent(#elixir_orddict__{}) ->
  'OrderedDict';

object_parent(Native) when is_tuple(Native) ->
  'Tuple';

object_parent(Native) when is_function(Native) ->
  'Function';

object_parent(Native) when is_bitstring(Native) ->
  'BitString';

object_parent(Native) when is_pid(Native) ->
  'Process';

object_parent(Native) when is_reference(Native) ->
  'Reference';

object_parent(Native) when is_port(Native) ->
  'Port'.

object_mixins(#elixir_object__{data=Data}) when is_atom(Data) ->
  try
    ets:lookup_element(Data, mixins, 2)
  catch
    error:badarg -> []
  end;

object_mixins(#elixir_object__{name=Name}) ->
  Name:'__mixins__'(nil);

% TODO: This needs to be properly tested.
object_mixins(Native) ->
  object_parent(Native) ++ ['Module::Methods'].

object_data(#elixir_slate__{data=Data}) ->
  Data;

object_data(#elixir_object__{data=Data}) when not is_atom(Data) ->
  Data;

object_data(#elixir_object__{data=Data}) ->
  try
    ets:lookup_element(Data, data, 2)
  catch
    error:badarg -> orddict:new()
  end;

object_data(Native) ->
  orddict:new(). % Native types has no data.

% Builtin mixins

builtin_mixin(Native) when is_list(Native) ->
  'exList::Instance';

builtin_mixin(Native) when is_binary(Native) ->
  'exString::Instance';

builtin_mixin(Native) when is_integer(Native) ->
  'exInteger::Instance';

builtin_mixin(Native) when is_float(Native) ->
  'exFloat::Instance';

builtin_mixin(Native) when is_atom(Native) ->
  'exAtom::Instance';

builtin_mixin(#elixir_orddict__{}) ->
  'exOrderedDict::Instance';

builtin_mixin(Native) when is_bitstring(Native) ->
  'exBitString::Instance';

builtin_mixin(Native) when is_tuple(Native) ->
  'exTuple::Instance';

builtin_mixin(Native) when is_function(Native) ->
  'exFunction::Instance';

builtin_mixin(Native) when is_pid(Native) ->
  'exProcess::Instance';

builtin_mixin(Native) when is_reference(Native) ->
  'exReference::Instance';

builtin_mixin(Native) when is_port(Native) ->
  'exPort::Instance'.

% Merge two lists taking into account uniqueness. Opposite to
% lists:umerge2, does not require lists to be sorted.

umerge(List, Data) ->
  umerge2(lists:reverse(List), Data).

umerge2([], Data) ->
  Data;

umerge2([H|T], Data) ->
  case lists:member(H, Data) of
    true  -> New = Data;
    false -> New = [H|Data]
  end,
  umerge2(T, New).