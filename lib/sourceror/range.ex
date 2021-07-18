defmodule Sourceror.Range do
  @moduledoc false

  import Sourceror.Identifier, only: [is_unary_op: 1, is_binary_op: 1]

  defp split_on_newline(string) do
    String.split(string, ~r/\n|\r\n|\r/)
  end

  @spec get_range(Sourceror.ast_node(), keyword) :: Sourceror.range()
  def get_range(quoted, _opts \\ []) do
    range = do_get_range(quoted)

    comments =
      case quoted do
        {_, meta, _} ->
          meta.leading_comments || []

        _ ->
          []
      end

    first_comment = List.first(comments)
    last_comment = List.last(comments)

    {start_line, start_column} =
      if first_comment do
        {first_comment.line, min(range.start.column, first_comment.column || 1)}
      else
        {range.start.line, range.start.column}
      end

    end_column =
      if last_comment && last_comment.line == range.start.line do
        comment_length = String.length(last_comment.text)
        max(range.end.column, (last_comment.column || 1) + comment_length)
      else
        range.end.column
      end

    %{
      start: %{line: start_line, column: start_column},
      end: %{line: range.end.line, column: end_column}
    }
  end

  @spec get_range(Macro.t()) :: Sourceror.range()
  defp do_get_range(quoted)

  # Module aliases
  defp do_get_range({:__aliases__, meta, segments}) do
    start_pos = Map.take(meta, [:line, :column])

    last_segment_length = List.last(segments) |> to_string() |> String.length()

    end_pos = meta.last |> Map.update!(:column, &(&1 + last_segment_length))

    %{start: start_pos, end: end_pos}
  end

  # Strings
  defp do_get_range({:string, meta, string}) when is_binary(string) do
    lines = split_on_newline(string)

    last_line = List.last(lines) || ""

    end_line = meta.line + length(lines)

    end_line =
      if meta.delimiter in [~S/"""/, ~S/'''/] do
        end_line
      else
        end_line - 1
      end

    end_column =
      if meta.delimiter in [~S/"""/, ~S/'''/] do
        meta.column + String.length(meta.delimiter)
      else
        count = meta.column + String.length(last_line) + String.length(meta.delimiter)

        if end_line == meta.line do
          count + 1
        else
          count
        end
      end

    %{
      start: Map.take(meta, [:line, :column]),
      end: %{line: end_line, column: end_column}
    }
  end

  # Integers, Floats
  defp do_get_range({form, meta, number})
       when form in [:int, :float]
       when is_integer(number) or is_float(number) do
    %{
      start: Map.take(meta, [:line, :column]),
      end: %{line: meta.line, column: meta.column + String.length(meta.token)}
    }
  end

  # Atoms
  defp do_get_range({:atom, meta, atom}) when is_atom(atom) do
    start_pos = Map.take(meta, [:line, :column])
    string = Atom.to_string(atom)

    delimiter = meta[:delimiter] || ""

    lines = split_on_newline(string)

    last_line = List.last(lines) || ""

    end_line = meta.line + length(lines) - 1

    end_column = meta.column + String.length(last_line) + String.length(delimiter)

    end_column =
      cond do
        end_line == meta.line && meta[:delimiter] ->
          # Column and first delimiter
          end_column + 2

        end_line == meta.line ->
          # Just the colon
          end_column + 1

        end_line != meta.line ->
          # You're beautiful as you are, Courage
          end_column
      end

    %{
      start: start_pos,
      end: %{line: end_line, column: end_column}
    }
  end

  # Block with no parenthesis
  defp do_get_range({:__block__, _, args} = quoted) do
    if Sourceror.has_closing_line?(quoted) do
      get_range_for_node_with_closing_line(quoted)
    else
      {first, rest} = List.pop_at(args, 0)
      {last, _} = List.pop_at(rest, -1, first)

      %{
        start: get_range(first).start,
        end: get_range(last).end
      }
    end
  end

  # Variables
  defp do_get_range({:var, meta, name}) when is_atom(name) do
    start_pos = Map.take(meta, [:line, :column])

    end_pos = %{
      line: start_pos.line,
      column: start_pos.column + String.length(Atom.to_string(name))
    }

    %{start: start_pos, end: end_pos}
  end

  # 2-tuples from keyword lists
  defp do_get_range({left, right}) do
    left_range = get_range(left)
    right_range = get_range(right)

    %{start: left_range.start, end: right_range.end}
  end

  defp do_get_range({[], _, _} = quoted) do
    get_range_for_node_with_closing_line(quoted)
  end

  # Access syntax
  defp do_get_range({{:., _, [Access, :get]}, _, _} = quoted) do
    get_range_for_node_with_closing_line(quoted)
  end

  # Qualified tuple
  defp do_get_range({{:., _, [_, :{}]}, _, _} = quoted) do
    get_range_for_node_with_closing_line(quoted)
  end

  # Interpolated atoms
  defp do_get_range({{:., _, [:erlang, :binary_to_atom]}, meta, [interpolation, :utf8]}) do
    interpolation = Sourceror.update_meta(interpolation, &Map.put(&1, :delimiter, meta.delimiter))

    get_range_for_interpolation(interpolation)
  end

  # Qualified call
  defp do_get_range({{:., _, [left, right]}, meta, []} = quoted) when is_atom(right) do
    if Sourceror.has_closing_line?(quoted) do
      get_range_for_node_with_closing_line(quoted)
    else
      start_pos = get_range(left).start
      identifier_pos = Map.take(meta, [:line, :column])

      parens_length =
        if meta.no_parens do
          0
        else
          2
        end

      end_pos = %{
        line: identifier_pos.line,
        column:
          identifier_pos.column + String.length(Atom.to_string(right)) +
            parens_length
      }

      %{start: start_pos, end: end_pos}
    end
  end

  # Qualified call with arguments
  defp do_get_range({{:., _, [left, _]}, _meta, args} = quoted) do
    if Sourceror.has_closing_line?(quoted) do
      get_range_for_node_with_closing_line(quoted)
    else
      start_pos = get_range(left).start
      end_pos = get_range(List.last(args) || left).end

      %{start: start_pos, end: end_pos}
    end
  end

  # Unary operators
  defp do_get_range({op, meta, [arg]}) when is_unary_op(op) do
    start_pos = Map.take(meta, [:line, :column])
    arg_range = get_range(arg)

    end_column =
      if arg_range.end.line == meta.line do
        arg_range.end.column
      else
        arg_range.end.column + String.length(to_string(op))
      end

    %{start: start_pos, end: %{line: arg_range.end.line, column: end_column}}
  end

  # Binary operators
  defp do_get_range({op, _, [left, right]}) when is_binary_op(op) do
    %{
      start: get_range(left).start,
      end: get_range(right).end
    }
  end

  # Stepped ranges
  defp do_get_range({:"..//", _, [left, _middle, right]}) do
    %{
      start: get_range(left).start,
      end: get_range(right).end
    }
  end

  # Bitstrings and interpolations
  defp do_get_range({:<<>>, meta, _} = quoted) do
    if meta[:delimiter] do
      get_range_for_interpolation(quoted)
    else
      get_range_for_bitstring(quoted)
    end
  end

  # Sigils
  defp do_get_range({:"~", meta, [_name, {:<<>>, _, segments}, modifiers]}) do
    start_pos = Map.take(meta, [:line, :column])

    end_pos =
      get_end_pos_for_interpolation_segments(segments, meta.delimiter, start_pos)
      |> Map.update!(:column, &(&1 + length(modifiers)))

    end_pos =
      cond do
        multiline_delimiter?(meta.delimiter) and !has_interpolations?(segments) ->
          # If it has no interpolations and is a multiline sigil, then the first
          # line will be incorrectly reported because the first string in the
          # segments(which is the only one) won't have a leading newline, so
          # we're compensating for that here. The end column will be at the same
          # indentation as the start column, plus the length of the multiline
          # delimiter
          %{line: end_pos[:line] + 1, column: start_pos[:column] + 3}

        multiline_delimiter?(meta.delimiter) or has_interpolations?(segments) ->
          # If it's a multiline sigil or has interpolations, then the positions
          # will already be correctly calculated
          end_pos

        true ->
          # If it's a single line sigil, add the offset for the ~x
          Map.update!(end_pos, :column, &(&1 + 2))
      end

    %{
      start: start_pos,
      end: end_pos
    }
  end

  # Unqualified calls
  defp do_get_range({call, _, args} = quoted) when is_atom(call) and is_list(args) do
    get_range_for_unqualified_call(quoted)
  end

  defp get_range_for_unqualified_call({_call, meta, args} = quoted)
       when is_map(meta) and is_list(args) do
    if Sourceror.has_closing_line?(quoted) do
      get_range_for_node_with_closing_line(quoted)
    else
      start_pos = Map.take(meta, [:line, :column])
      end_pos = get_range(List.last(args)).end

      %{start: start_pos, end: end_pos}
    end
  end

  defp get_range_for_node_with_closing_line({_, meta, _} = quoted) when is_map(meta) do
    start_position = Sourceror.get_start_position(quoted)
    end_position = Sourceror.get_end_position(quoted)

    end_position =
      if Map.has_key?(meta, :end) do
        Map.update!(end_position, :column, &(&1 + 3))
      else
        # If it doesn't have an end token, then it has either a ), a ] or a }
        Map.update!(end_position, :column, &(&1 + 1))
      end

    %{start: start_position, end: end_position}
  end

  defp get_range_for_interpolation({:<<>>, meta, segments}) do
    start_pos = Map.take(meta, [:line, :column])

    end_pos = get_end_pos_for_interpolation_segments(segments, meta.delimiter || "\"", start_pos)

    %{start: start_pos, end: end_pos}
  end

  def get_end_pos_for_interpolation_segments(segments, delimiter, start_pos) do
    end_pos =
      Enum.reduce(segments, start_pos, fn
        string, pos when is_binary(string) ->
          lines = split_on_newline(string)
          length = String.length(List.last(lines) || "")

          line_count = length(lines) - 1

          column =
            if line_count > 0 do
              start_pos.column + length
            else
              pos.column + length
            end

          %{
            line: pos.line + line_count,
            column: column
          }

        {:"::", _, [{_, meta, _}, {_, _, :binary}]}, _pos ->
          meta.closing
          |> Map.take([:line, :column])
          # Add the closing }
          |> Map.update!(:column, &(&1 + 1))
      end)

    cond do
      multiline_delimiter?(delimiter) and has_interpolations?(segments) ->
        %{line: end_pos.line, column: String.length(delimiter) + 1}

      has_interpolations?(segments) ->
        Map.update!(end_pos, :column, &(&1 + 1))

      true ->
        Map.update!(end_pos, :column, &(&1 + 2))
    end
  end

  defp has_interpolations?(segments) do
    Enum.any?(segments, &match?({:"::", _, _}, &1))
  end

  defp multiline_delimiter?(delimiter) do
    delimiter in ~w[""" ''']
  end

  defp get_range_for_bitstring(quoted) do
    range = get_range_for_node_with_closing_line(quoted)

    # get_range_for_node_with_closing_line/1 will add 1 to the ending column
    # because it assumes it ends with ), ] or }, but bitstring closing token is
    # >>, so we need to add another 1
    update_in(range, [:end, :column], &(&1 + 1))
  end
end
