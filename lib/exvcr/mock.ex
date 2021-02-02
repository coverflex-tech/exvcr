defmodule ExVCR.Mock do
  @moduledoc """
  Provides macro to record HTTP request/response.
  """

  alias ExVCR.Recorder

  defmacro __using__(opts) do
    adapter = opts[:adapter] || ExVCR.Adapter.IBrowse
    mock_lib = opts[:mock_lib] || :meck
    options = opts[:options]

    quote do
      import ExVCR.Mock
      :application.start(unquote(adapter).module_name)
      use unquote(adapter)

      def adapter_method() do
        unquote(adapter)
      end

      def mock_lib_method() do
        unquote(mock_lib)
      end

      def options_method() do
        unquote(options)
      end
    end
  end

  @doc """
  Provides macro to mock response based on specified parameters.
  """
  defmacro use_cassette(:stub, options, test) do
    quote do
      stub_fixture = "stub_fixture_#{ExVCR.Util.uniq_id}"
      stub = prepare_stub_record(unquote(options), adapter_method())
      recorder = Recorder.start([fixture: stub_fixture, stub: stub, adapter: adapter_method(), mock_lib: mock_lib_method()])

      try do
        mock_methods(recorder, adapter_method(), mock_lib_method())
        [do: return_value] = unquote(test)
        return_value
      after
        module_name = adapter_method().module_name
        unload(module_name, mock_lib_method())
        if mock_lib_method() == :meck do
          ExVCR.MockLock.release_lock()
        end
      end
    end
  end

  @doc """
  Provides macro to trigger recording/replaying http interactions.

  ## Options

  - `:match_requests_on` A list of request properties to match on when
    finding a matching response. Valid values include `:query`, `:headers`,
    and `:request_body`

  """
  defmacro use_cassette(fixture, options, test) do
    quote do
      recorder = Recorder.start(
        unquote(options) ++ [fixture: normalize_fixture(unquote(fixture)), adapter: adapter_method(), mock_lib: mock_lib_method()])


      try do
        mock_methods(recorder, adapter_method(), mock_lib_method())
        [do: return_value] = unquote(test)
        return_value
      after
        recorder_result = Recorder.save(recorder)

        module_name = adapter_method().module_name
        unload(module_name, mock_lib_method())
        if mock_lib_method() == :meck do
          ExVCR.MockLock.release_lock()
        end
        recorder_result
      end
    end
  end

  @doc """
  Provides macro to trigger recording/replaying http interactions with default options.
  """
  defmacro use_cassette(fixture, test) do
    quote do
      use_cassette(unquote(fixture), [], unquote(test))
    end
  end

  @doc false
  defp load(mock_lib, adapter, recorder) do
    if ExVCR.Application.global_mock_enabled?() do
      ExVCR.Actor.CurrentRecorder.set(recorder)
    else
      module_name    = adapter.module_name
      initialize_mock(mock_lib, module_name)

      target_methods = adapter.target_methods(recorder)
      Enum.each(target_methods, fn({function, callback}) ->
        mock_method(mock_lib, module_name, function, callback)
      end)
    end
  end

  defp initialize_mock(:meck, module_name), do: :ok
  defp initialize_mock(:mimic, module_name), do: :ok #Mimic.copy(module_name)

  defp mock_method(:meck, module_name, function, callback), do: :meck.expect(module_name, function, callback)
  defp mock_method(:mimic, module_name, function, callback), do: Mimic.stub(module_name, function, callback)

  defp unload_mock(:meck, module_name), do: :meck.unload(module_name)
  defp unload_mock(:mimic, module_name), do: :ok # Mimic.Server.reset(module_name)

  @doc false
  def unload(module_name, mock_lib \\ :meck) do
    if ExVCR.Application.global_mock_enabled?() do
      ExVCR.Actor.CurrentRecorder.default_state()
      |> ExVCR.Actor.CurrentRecorder.set()
    else
      unload_mock(mock_lib, module_name)
    end
  end

  @doc """
  Mock methods pre-defined for the specified adapter.
  """
  def mock_methods(recorder, adapter, mock_lib \\ :meck)
  def mock_methods(recorder, adapter, :meck) do
      parent_pid = self()
    Task.async(fn ->
      ExVCR.MockLock.ensure_started
      ExVCR.MockLock.request_lock(self(), parent_pid)
      receive do
        :lock_granted ->
          load(:meck, adapter, recorder)
      end
    end)
    |> Task.await(:infinity)
  end

  def mock_methods(recorder, adapter, :mimic) do
    load(:mimic, adapter, recorder)
  end

  @doc """
  Prepare stub record based on specified option parameters.
  """
  def prepare_stub_record(options, adapter) do
    method        = (options[:method] || "get") |> to_string
    url           = (options[:url] || "~r/.+/") |> to_string
    body          = (options[:body] || "Hello World") |> to_string
    # REVIEW: would be great to have "~r/.+/" as default request_body
    request_body  = (options[:request_body] || "") |> to_string

    headers     = options[:headers] || adapter.default_stub_params(:headers)
    status_code = options[:status_code] || adapter.default_stub_params(:status_code)

    record = %{ "request"  => %{"method" => method, "url" => url, "request_body" => request_body},
                "response" => %{"body" => body, "headers"  => headers, "status_code" => status_code} }

    [adapter.convert_from_string(record)]
  end

  @doc """
  Normalize fixture name for using as json file names, which removes whitespaces and align case.
  """
  def normalize_fixture(fixture) do
    fixture |> String.replace(~r/\s/, "_") |> String.downcase
  end
end
