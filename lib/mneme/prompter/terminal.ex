defmodule Mneme.Prompter.Terminal do
  @moduledoc false

  @behaviour Mneme.Prompter

  import Owl.Data, only: [tag: 2]

  alias Mneme.Assertion
  alias Rewrite.Source

  @middle_dot_char "·"
  @bullet_char "●"
  @empty_bullet_char "○"
  @info_char "🛈"
  @arrow_left_char "❮"
  @arrow_right_car "❯"

  @box_horizontal "─"
  @box_vertical "│"
  @box_cross_down "┬"
  @box_cross_up "┴"

  @impl true
  def prompt!(%Source{} = source, %Assertion{} = assertion, opts, _prompt_state) do
    message = message(source, assertion, opts)

    Owl.IO.puts(["\n\n", message])
    result = input()

    {result, nil}
  end

  @doc false
  def message(source, %Assertion{} = assertion, opts) do
    notes = Assertion.notes(assertion)

    [
      format_header(assertion),
      "\n",
      format_diff(source, opts),
      format_notes(notes),
      "\n",
      format_input(assertion)
    ]
  end

  defp input do
    case gets() do
      "y" -> :accept
      "n" -> :reject
      "s" -> :skip
      "k" -> :next
      "j" -> :prev
      _ -> input()
    end
  end

  defp gets do
    resp =
      [IO.ANSI.cursor_up(2), IO.ANSI.cursor_right(2)]
      |> IO.gets()
      |> normalize_gets()

    IO.write([IO.ANSI.cursor_down(1), "\r"])

    resp
  end

  defp normalize_gets(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      string -> String.downcase(string)
    end
  end

  defp normalize_gets(_), do: nil

  defp format_diff(source, %{diff: :text}) do
    Rewrite.TextDiff.format(
      source |> Source.code(Source.version(source) - 1) |> eof_newline(),
      source |> Source.code() |> eof_newline(),
      line_numbers: false,
      format: [
        separator: "",
        gutter: [eq: "   ", ins: " + ", del: " - ", skip: "..."],
        colors: [
          ins: [text: :green, space: IO.ANSI.color_background(0, 1, 0)],
          del: [text: :red, space: IO.ANSI.color_background(1, 0, 0)],
          skip: [text: :yellow],
          separator: [text: :yellow]
        ]
      ],
      colorizer: &tag/2
    )
  end

  defp format_diff(source, %{diff: :semantic} = opts) do
    case semantic_diff(source) do
      {del, ins} ->
        del_height = length(del)
        ins_height = length(ins)

        del_length = del |> Stream.map(&Owl.Data.length/1) |> Enum.max()
        ins_length = ins |> Stream.map(&Owl.Data.length/1) |> Enum.max()

        deletions = del |> Owl.Data.unlines() |> Owl.Data.add_prefix(tag("  -  ", :red))
        insertions = ins |> Owl.Data.unlines() |> Owl.Data.add_prefix(tag("  +  ", :green))

        if cols_each = diff_side_by_side(opts, max(del_length, ins_length) + 4) do
          height_padding =
            if del_height == ins_height do
              []
            else
              [
                "\n",
                "\n"
                |> String.duplicate(abs(del_height - ins_height) - 1)
                |> Owl.Data.add_prefix(tag("  #{@middle_dot_char} ", :faint))
              ]
            end

          {deletions, insertions} =
            if del_height < ins_height do
              {[deletions, height_padding], insertions}
            else
              {deletions, [insertions, height_padding]}
            end

          height = max(del_height, ins_height)
          left = diff_box(tag("old", :red), deletions, height, cols_each)
          right = diff_box(tag("new", :green), insertions, height, cols_each)

          joiner =
            tag(
              [
                @box_cross_down,
                "\n",
                String.duplicate("#{@box_vertical}\n", height),
                @box_cross_up
              ],
              :faint
            )

          [
            Enum.reduce([right, joiner, left], &Owl.Data.zip/2),
            "\n"
          ]
        else
          [
            deletions,
            "\n\n",
            insertions,
            "\n"
          ]
        end

      nil ->
        format_diff(:text, source)
    end
  end

  defp diff_box(title, content, height, width) do
    top_border = [
      tag(@box_horizontal, :faint),
      title,
      @box_horizontal |> String.duplicate(width - Owl.Data.length(title) + 1) |> tag(:faint)
    ]

    bottom_border =
      if height > 8 do
        top_border
      else
        @box_horizontal |> String.duplicate(width + 2) |> tag(:faint)
      end

    data = [top_border, "\n", content, "\n", bottom_border]

    Owl.Box.new(data, border_style: :none, min_width: width)
  end

  defp diff_side_by_side(%{diff_style: {:side_by_side, int}}, _), do: int

  defp diff_side_by_side(%{diff_style: :side_by_side}, largest_side) do
    cols = Owl.IO.columns()

    if cols && largest_side * 2 <= cols do
      floor(cols / 2) - 4
    end
  end

  defp diff_side_by_side(%{diff_style: :stacked}, _), do: nil

  defp semantic_diff(source) do
    with %{left: left, right: right} <- source.private[:diff] do
      task = Task.async(Mneme.Diff, :format, [left, right])

      case Task.yield(task, 1500) || Task.shutdown(task, :brutal_kill) do
        {:ok, {:ok, {nil, nil}}} -> nil
        {:ok, {:ok, {nil, ins}}} -> {Owl.Data.lines(left), ins}
        {:ok, {:ok, {del, nil}}} -> {del, Owl.Data.lines(right)}
        {:ok, {:ok, {del, ins}}} -> {del, ins}
        {:ok, {:error, {:internal, e, stacktrace}}} -> reraise e, stacktrace
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  defp eof_newline(code), do: String.trim_trailing(code) <> "\n"

  defp format_header(%Assertion{type: type, test: test, module: module} = assertion) do
    [
      format_type(type),
      tag([" ", @bullet_char, " "], :faint),
      to_string(test),
      " (",
      inspect(module),
      ")\n",
      format_file(assertion),
      "\n"
    ]
  end

  defp format_file(%Assertion{file: file, line: line}) do
    path = Path.relative_to_cwd(file)
    tag([path, ":", to_string(line)], :faint)
  end

  defp format_type(:new), do: tag("[Mneme] New", :green)
  defp format_type(:update), do: tag("[Mneme] Changed", :yellow)

  defp format_notes([]), do: []

  defp format_notes(notes) do
    notes = Enum.uniq(notes)

    [
      "\n#{@info_char} Notes about this assertion:\n",
      notes |> Owl.Data.unlines() |> Owl.Data.add_prefix("  * "),
      "\n"
    ]
    |> tag(:faint)
  end

  defp format_input(%{type: type} = assertion) do
    nav = Assertion.pattern_index(assertion)

    [
      format_explanation(type),
      "\n",
      tag("> ", :faint),
      "\n",
      format_input_options(nav)
    ]
  end

  defp format_input_options(nav) do
    [
      [tag("y", :green), " ", tag("yes", :faint)],
      [tag("n", :red), " ", tag("no", :faint)],
      [tag("s", :yellow), " ", tag("skip", :faint)],
      format_nav_options(nav)
    ]
    |> Enum.intersperse(["  "])
  end

  defp format_nav_options({_, 1}), do: ""

  defp format_nav_options({index, count}) do
    dots = Enum.map(0..(count - 1), &if(&1 == index, do: @bullet_char, else: @empty_bullet_char))
    tag(["#{@arrow_left_char} j ", dots, " k #{@arrow_right_car}"], :faint)
  end

  defp format_explanation(:new) do
    "Accept new assertion?"
  end

  defp format_explanation(:update) do
    [
      tag("Value has changed! ", :yellow),
      "Update pattern?"
    ]
  end
end
