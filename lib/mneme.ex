defmodule Mneme do
  @external_resource "mix.exs"
  @external_resource "README.md"
  @mdoc "README.md"
        |> File.read!()
        |> String.split("<!-- MDOC !-->")
        |> Enum.fetch!(1)

  @moduledoc """
  /ˈniːmiː/ - Snapshot testing utilities

  #{@mdoc}

  ## Configuration

  Mneme supports a variety of flexible configuration options that can be
  applied at multiple levels of granularity, from your entire test suite
  down to an individual test. While the default behavior will work well
  for the majority of cases, it's worth knowing which levers and knobs
  you have available to tweak Mneme to fit your individual workflow.

  ### Options

  #{Mneme.Options.docs()}

  ### Configuring Mneme

  There are four ways you can apply configuration options; Each is more
  specific than the last and will override any conflicting options that
  were set prior.

    * When calling `Mneme.start/1`, which will apply to the entire test
      run;
    * When calling `use Mneme`, which will apply to all tests in that
      module;
    * In a `@mneme_describe` module attribute, which will apply to all
      tests that follow in the given `ExUnit.Case.describe/2` block;
    * In a `@mneme` module attribute, which will apply only to the next
      test that follows.

  For instance, when an auto-assertion has multiple possible patterns
  available, Mneme will try to infer the best one to show you first.
  If you always want the last (and usually most complex) generated
  pattern, you could call `Mneme.start/1` like this:

      # test/test_helper.exs
      ExUnit.start()
      Mneme.start(default_pattern: :last)

  As mentioned above, this can be overriden at the module-level, in a
  `describe` block, or for an individual test:

      defmodule MyTest do
        use ExUnit.Case
        use Mneme, default_pattern: :infer

        test "the default pattern will exclude :baz when this runs" do
          map = %{foo: :one, baz: :three}
          auto_assert %{foo: 1, bar: 2} <- Map.put(map, bar: :two)
        end

        describe "..." do
          @mneme_describe action: :reject

          test "fails without prompting" do
            auto_assert :wrong <- MyModule.some_fun()
          end

          @mneme action: :prompt
          test "prompts to update" do
            auto_assert :wrong <- MyModule.another_fun()
          end
        end
      end

  Breaking up with Mneme? While the official stance of the library is
  that this is Not Recommended™, Mneme can even convert all of your
  existing auto-assertions to regular assertions:

      Mneme.start(
        target: :ex_unit,
        force_update: true,
        action: :accept
      )

  Probably don't do this, but if you do, make sure all your tests are
  committed first in case you want to get back together.

  <hr/>

  > #### `use Mneme` {: .info}
  >
  > When you `use Mneme` in a test module, [assertions](#assertions) are
  > imported and module attributes are made available for
  > [configuration](#configuration).
  """

  @ex_unit_default_receive_timeout 100

  @doc false
  defmacro __using__(opts) do
    quote do
      import Mneme, only: :macros
      require Mneme.Options
      Mneme.Options.register_attributes(unquote(opts))
    end
  end

  @doc """
  Pattern-generating variant of `ExUnit.Assertions.assert/1`.

  ## Examples

  `auto_assert` generates assertions when tests run, issuing a terminal
  prompt before making any changes (unless configured otherwise).

      auto_assert [1, 2] ++ [3, 4]

      # after running the test and accepting the change
      auto_assert [1, 2, 3, 4] <- [1, 2] ++ [3, 4]

  If the match no longer succeeds, a warning and new prompt will be
  issued to update it to the new value.

      auto_assert [1, 2, 3, 4] <- [1, 2] ++ [:a, :b]

      # after running the test and accepting the change
      auto_assert [1, 2, :a, :b] <- [1, 2] ++ [:a, :b]

  Prompts are only issued if the pattern doesn't match the value, so
  that pattern can also be changed manually.

      # this assertion succeeds, so no prompt is issued
      auto_assert [1, 2, | _] <- [1, 2] ++ [:a, :b]

  ## Differences from ExUnit `assert`

  The `auto_assert` macro is meant to match `assert` very closely, but
  there are a few differences to note:

    * Pattern-matching assertions use the `<-` operator instead of the
      `=` match operator.

    * Unlike ExUnit's `assert`, `auto_assert` can match falsy values.
      The following are equivalent:

          falsy = nil
          auto_assert nil <- falsy
          assert falsy == nil

    * Guards can be added with a `when` clause, while `assert` would
      require a second assertion. For example:

          auto_assert pid when is_pid(pid) <- self()

          assert pid = self()
          assert is_pid(pid)

    * Bindings in an `auto_assert` are not available outside of that
      assertion. For example:

          auto_assert pid when is_pid(pid) <- self()
          pid # ERROR: pid is not bound

      If you need to use the result of the assertion, it will evaluate
      to the expression's value.

          pid = auto_assert pid when is_pid(pid) <- self()
          pid # pid is the result of self()

  """
  @doc section: :assertion
  defmacro auto_assert(expression) do
    __build_assertion__(:auto_assert, [expression], __CALLER__)
  end

  @doc """
  Pattern-generating variant of `ExUnit.Assertions.assert_raise/3`.

  If the given function does not raise, the assertion will fail.

  Like `auto_assert/1`, you will be prompted to automatically update
  the assertion if the raised raised exception changes.

  ## Examples

  You can pass an anonymous function that takes no arguments and is
  expected to raise an exception.

      auto_assert_raise fn ->
        some_call_expected_to_raise()
      end

      # after running the test and accepting changes
      auto_assert_raise Some.Exception, fn ->
        some_call_expected_to_raise()
      end

      # optionally include the message
      auto_assert_raise Some.Exception, "perhaps with a message", fn ->
        some_call_expected_to_raise()
      end

  A captured function of arity zero can also be used.

      auto_assert_raise &some_call_expected_to_raise/0

      # after running the test and accepting changes
      auto_assert_raise Some.Exception, &some_call_expected_to_raise/0

  """
  @doc section: :assertion
  @doc since: "0.3.0"
  defmacro auto_assert_raise(exception, message, function) do
    __build_assertion__(:auto_assert_raise, [exception, message, function], __CALLER__)
  end

  @doc """
  See `auto_assert_raise/3`.
  """
  @doc section: :assertion
  @doc since: "0.3.0"
  defmacro auto_assert_raise(exception, function) do
    __build_assertion__(:auto_assert_raise, [exception, function], __CALLER__)
  end

  @doc """
  See `auto_assert_raise/3`.
  """
  @doc section: :assertion
  @doc since: "0.3.0"
  defmacro auto_assert_raise(function) do
    __build_assertion__(:auto_assert_raise, [function], __CALLER__)
  end

  @doc """
  Pattern-generating variant of `ExUnit.Assertions.assert_receive/3`.

  `timeout` is in milliseconds and defaults to `#{@ex_unit_default_receive_timeout}`.

  ## Examples

      Process.send_after(self(), {:some, :message}, 50)

      auto_assert_receive()

      # after running the test, messages appearing within 100ms
      # will be available as options
      auto_assert_receive {:some, :message}

  A custom timeout can be specified as a second argument.

      Process.send_after(self(), {:some, :message}, 150)

      auto_assert_receive nil, 300

      # messages appearing within 300ms will now appear as options
      auto_assert_receive {:some, :message}, 300

  """
  @doc section: :assertion
  @doc since: "0.3.0"
  defmacro auto_assert_receive(pattern, timeout) when is_integer(timeout) and timeout >= 0 do
    __build_assertion__(:auto_assert_receive, [pattern, timeout], __CALLER__)
  end

  @doc """
  See `auto_assert_receive/2`.
  """
  @doc section: :assertion
  @doc since: "0.3.0"
  defmacro auto_assert_receive(pattern) do
    __build_assertion__(:auto_assert_receive, [pattern], __CALLER__)
  end

  @doc """
  See `auto_assert_receive/2`.
  """
  @doc section: :assertion
  @doc since: "0.3.0"
  defmacro auto_assert_receive do
    __build_assertion__(:auto_assert_receive, [], __CALLER__)
  end

  @doc """
  Pattern-generating variant of `ExUnit.Assertions.assert_received/2`.

  Similar to `auto_assert_receive/2`, except that the timeout is set to
  0, so the expected message must already be in the current process'
  mailbox.

  ## Examples

      send(self(), {:some, :message})

      auto_assert_received()

      # after running the test, messages in the current process
      # inbox will be available as options
      auto_assert_receive {:some, :message}

  """
  @doc section: :assertion
  @doc since: "0.3.0"
  defmacro auto_assert_received(pattern) do
    __build_assertion__(:auto_assert_received, [pattern], __CALLER__)
  end

  @doc """
  See `auto_assert_received/1`.
  """
  @doc section: :assertion
  @doc since: "0.3.0"
  defmacro auto_assert_received do
    __build_assertion__(:auto_assert_received, [], __CALLER__)
  end

  @doc false
  def __build_assertion__(kind, args, caller) do
    opts = fetch_opts!(kind, caller)
    Mneme.Assertion.build(kind, args, caller, opts)
  end

  defp fetch_opts!(kind, caller) do
    with {fun_name, 1} <- caller.function,
         %ExUnit.Test{name: ^fun_name, tags: tags} <- get_last_registered_test(caller.module) do
      Mneme.Options.options(tags)
    else
      _ -> raise Mneme.CompileError, message: "#{kind} can only be used inside of a test"
    end
  end

  # Elixir v1.15.0 introduced `ExUnit.Case.get_last_registered_test/1`,
  # which can be called at compile-time to get the `%ExUnit.Test{}`
  # struct containing test tags. For prior versions of Elixir, we access
  # the private module attribute that ExUnit uses to store test structs
  # as they are registered.
  if Version.match?(System.version(), ">= 1.15.0") do
    defp get_last_registered_test(module) do
      ExUnit.Case.get_last_registered_test(module)
    end
  else
    defp get_last_registered_test(module) do
      module
      |> Module.get_attribute(:ex_unit_tests)
      |> List.first()
    end
  end

  @doc """
  Starts Mneme to run auto-assertions as they appear in your tests.

  This will almost always be added to your `test/test_helper.exs`, just
  below the call to `ExUnit.start()`:

      # test/test_helper.exs
      ExUnit.start()
      Mneme.start()

  ## Options

    * `:restart` (boolean) - Restarts Mneme if it has previously been
      started. This option enables certain IEx-based testing workflows
      that allow tests to be run without a startup penalty. Defaults to
      `false`.

    * Any option defined in the [Configuration](#module-configuration)
      section of the module docs.

  """
  @doc section: :setup
  def start(opts \\ []) do
    {restart?, opts} = Keyword.pop(opts, :restart, false)
    supervisor = Process.whereis(Mneme.Supervisor)

    cond do
      !supervisor ->
        configure!(opts)
        start_server!()

      supervisor && restart? ->
        configure!(opts)
        restart_server!()

      true ->
        raise RuntimeError,
              "Mneme has already started. Ensure that `:restart` is used if rerunning tests without restarting the application: `Mneme.start(restart: true)`"
    end

    :ok
  end

  defp start_server! do
    children = [
      Mneme.Server
    ]

    opts = [
      name: Mneme.Supervisor,
      strategy: :one_for_one
    ]

    {:ok, _pid} = Supervisor.start_link(children, opts)
  end

  defp restart_server! do
    _ = Supervisor.terminate_child(Mneme.Supervisor, Mneme.Server)
    {:ok, _pid} = Supervisor.restart_child(Mneme.Supervisor, Mneme.Server)
  end

  defp configure!(opts) do
    ExUnit.configure(
      formatters: [Mneme.Server.ExUnitFormatter],
      default_formatter: ExUnit.CLIFormatter,
      timeout: :infinity
    )

    Mneme.Options.configure(opts)
  end

  @doc false
  def __receive_timeout__, do: @ex_unit_default_receive_timeout
end
