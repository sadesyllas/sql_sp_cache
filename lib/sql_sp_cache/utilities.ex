defmodule SqlSpCache.Utilities do
  @moduledoc false

  use Bitwise

  # gen_byte_size

  def gen_byte_size(value, acc_byte_size \\ 0)

  def gen_byte_size([], acc_byte_size)
  do
    acc_byte_size + 1 # assume 64-bit word
  end

  def gen_byte_size([value | rest_values], acc_byte_size)
  do
    gen_byte_size(
      rest_values,
      (
        acc_byte_size +
        1 + # assume 64-bit word
        gen_byte_size(value)
      ))
  end

  def gen_byte_size(value, acc_byte_size)
  when is_map(value)
  do
    value_byte_size =
      value
      |> Enum.map(fn {k, v} -> gen_byte_size(k) + gen_byte_size(v) end)
      |> Enum.sum()
    acc_byte_size +
    40 + # assume 5x64-bit word (minimum for map)
    value_byte_size
  end

  def gen_byte_size(value, acc_byte_size)
  when is_tuple(value)
  do
    acc_byte_size +
    16 + # assume 2x64-bit words
    gen_byte_size(Tuple.to_list(value))
  end

  def gen_byte_size(value, acc_byte_size)
  when is_integer(value) or is_float(value)
  do
    acc_byte_size + 24 # assume 3x64-bit words
  end

  def gen_byte_size(value, acc_byte_size)
  when is_atom(value) or is_pid(value) or is_port(value) or is_reference(value)
  do
    acc_byte_size + 8 # assume 64-bit word
  end

  def gen_byte_size(value, acc_byte_size)
  when is_binary(value)
  do
    acc_byte_size +
    6 + # assume 6x64-bit word
    byte_size(value)
  end

  def gen_byte_size(nil, acc_byte_size)
  do
    acc_byte_size
  end

  def gen_byte_size(_, acc_byte_size)
  do
    acc_byte_size
  end

  # get_data_header

  def get_data_header(nil)
  do
    get_data_header(<<>>)
  end

  def get_data_header(data)
  do
    byte_count = byte_size(data)
    [&(&1 >>> 24), &(&1 >>> 16), &(&1 >>> 8), &(&1 &&& 255)]
    |> Enum.reduce(<<>>, fn to_byte_value, data_header -> data_header <> <<to_byte_value.(byte_count)>> end)
  end
end
