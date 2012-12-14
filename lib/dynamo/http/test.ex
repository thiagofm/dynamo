defmodule Dynamo.HTTP.Test do
  @moduledoc """
  A connection to be used in tests. It implements
  the same API as the other connections implementations
  and a couple extra helpers to be used in tests.

  Check `Dynamo.HTTP` for documentation on
  the majority of the functions.
  """

  use Dynamo.HTTP.Behaviour,
    [ :query_string, :raw_req_headers, :raw_req_body, :raw_req_cookies, :fetched,
      :path_segments, :sent_body, :original_method ]

  @doc """
  Initializes a connection to be used in tests.
  """
  def new() do
    connection(
      app: Dynamo.under_test,
      before_send: Dynamo.HTTP.default_before_send,
      fetched: [],
      raw_req_cookies: Binary.Dict.new(),
      raw_req_headers: Binary.Dict.new([{ "host", "127.0.0.1" }]),
      sent_body: nil,
      state: :unset
    ).req(:GET, "/", "")
  end

  ## Request API

  def version(_conn) do
    { 1, 1 }
  end

  def original_method(connection(original_method: method)) do
    method
  end

  def query_string(connection(query_string: query_string)) do
    query_string
  end

  def path_segments(connection(path_segments: path_segments)) do
    path_segments
  end

  def path(connection(path_segments: path_segments)) do
    to_path path_segments
  end

  ## Response API

  def send(status, body, connection(state: state) = conn) when is_integer(status)
      and state in [:unset, :set] and is_binary(body) do
    connection(run_before_send(conn),
      state: :sent,
      status: status,
      sent_body: check_sent_body(conn, body),
      resp_body: nil
    )
  end

  def send_chunked(status, connection(state: state) = conn) when is_integer(status)
      and state in [:unset, :set] do
    connection(run_before_send(conn),
      state: :chunked,
      status: status,
      sent_body: "",
      resp_body: nil
    )
  end

  def chunk(body, connection(state: state, sent_body: sent) = conn) when state == :chunked do
    connection(conn, sent_body: check_sent_body(conn, sent <> body))
  end

  defp check_sent_body(connection(original_method: "HEAD"), _body), do: ""
  defp check_sent_body(_conn, body),                                do: body

  def sendfile(path, conn) do
    send(200, File.read!(path), conn)
  end

  def sent_body(connection(sent_body: sent_body)) do
    sent_body
  end

  ## Misc

  def fetch(list, conn) when is_list(list) do
    Enum.reduce list, conn, fn(item, acc) -> acc.fetch(item) end
  end

  def fetch(:headers, connection(raw_req_headers: raw_req_headers, req_headers: nil, fetched: fetched) = conn) do
    connection(conn,
      fetched: [:headers|fetched],
      req_headers: raw_req_headers,
      raw_req_headers: Binary.Dict.new)
  end

  def fetch(:params, connection(query_string: query_string, params: nil, fetched: fetched) = conn) do
    params = Dynamo.HTTP.QueryParser.parse(query_string)
    connection(conn, params: params, fetched: [:params|fetched])
  end

  def fetch(:cookies, connection(raw_req_cookies: raw_req_cookies, req_cookies: nil, fetched: fetched) = conn) do
    connection(conn, req_cookies: raw_req_cookies, fetched: [:cookies|fetched])
  end

  def fetch(:body, connection(raw_req_body: req_body, req_body: nil, fetched: fetched) = conn) do
    connection(conn, req_body: req_body, fetched: [:body|fetched])
  end

  def fetch(aspect, conn) when aspect in [:params, :cookies, :body, :headers] do
    conn
  end

  def fetch(aspect, connection(fetchable: fetchable) = conn) when is_atom(aspect) do
    case Keyword.get(fetchable, aspect) do
      nil -> raise Dynamo.HTTP.UnknownAspectError, aspect: aspect
      fun -> fun.(conn)
    end
  end

  ## Test only API

  @doc """
  Resets the connection for a new request with the given
  method and on the given path.

  If the path contains a host, e.g `//example.com/foo`,
  the Host request header is set to such value, otherwise
  it defaults to `127.0.0.1`.
  """
  def req(method, path, body // "", conn) do
    uri      = URI.parse(path)
    segments = Dynamo.Router.Utils.split(uri.path)
    method   = Dynamo.Router.Utils.normalize_verb(method)

    conn = connection(conn,
      method: method,
      original_method: method,
      params: nil,
      path_info_segments: segments,
      path_segments: segments,
      query_string: uri.query || "",
      raw_req_body: body,
      req_body: nil,
      script_name_segments: [])

    if uri.authority do
      conn.put_req_header "host", uri.authority
    else
      conn
    end
  end

  @doc """
  Stores fetched aspects.
  """
  def fetched(connection(fetched: fetched)) do
    fetched
  end

  @doc """
  Sets the cookies to be read by the request.
  """
  def put_req_cookie(key, value, connection(raw_req_cookies: cookies) = conn) do
    connection(conn, raw_req_cookies: Dict.put(cookies, key, value))
  end

  @doc """
  Sets a request header, overriding any previous value.
  Both `key` and `value` are converted to binary.
  """
  def put_req_header(key, value, connection(raw_req_headers: raw_req_headers) = conn) do
    connection(conn, raw_req_headers: Dict.put(raw_req_headers, String.downcase(key), to_binary(value)))
  end

  @doc """
  Deletes a request header.
  """
  def delete_req_header(key, connection(raw_req_headers: raw_req_headers) = conn) do
    connection(conn, raw_req_headers: Dict.delete(raw_req_headers, String.downcase(key)))
  end
end