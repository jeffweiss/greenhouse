defmodule Greenhouse do
  use HTTPoison.Base
  alias Greenhouse.Client

  @user_agent [{"User-agent", "greenhouse/elixir (github.com/jeffweiss/greenhouse)"}]


  def process_response_body(""), do: nil
  def process_response_body(body), do: JSX.decode!(body)

  def process_response(%HTTPoison.Response{status_code: 200, body: body}), do: body
  def process_response(%HTTPoison.Response{status_code: status_code, body: body }), do: { status_code, body }


  def delete(path, client, body \\ "") do
    _request(:delete, url(client, path), client.auth, body)
  end

  def post(path, client, body \\ "") do
    _request(:post, url(client, path), client.auth, body)
  end

  def patch(path, client, body \\ "") do
    _request(:patch, url(client, path), client.auth, body)
  end

  def put(path, client, body \\ "") do
    _request(:put, url(client, path), client.auth, body)
  end

  @doc """
  Underlying utility retrieval function. The options passed affect both the
  return value and, ultimately, the number of requests made to GitHub.
  Options:
    * `:pagination` - Can be `:none`, `:manual`, `:stream`, or `:auto`. Defaults to :auto
      `:none` will only return the first page. You won't have access to the headers to manually
      paginate.
      `:auto` will block until all the pages have been retrieved and concatenated together. Most
      of the time, this is what you want. 
      `:stream` will return a `Stream`, prepopulated with the first page.
      `:manual` will return a 3 element tuple of `{page_body, url_for_next_page, auth_credentials}`,
      which will allow you to control the paging yourself.
  """
  def get(path, client, params \\ [], options \\ []) do
    url =
      client
      |> url(path)
      |> add_params_to_url(params)

    case pagination(options) do
      nil     -> request_stream(:get, url, client.auth) |> realize_if_needed
      :none   -> request_stream(:get, url, client.auth, "", :one_page)
      :auto   -> request_stream(:get, url, client.auth) |> realize_if_needed
      :stream -> request_stream(:get, url, client.auth)
      :manual -> request_with_pagination(:get, url, client.auth)
    end
  end

  def _request(method, url, auth, body \\ "") do
    json_request(method, url, body, authorization_header(auth, @user_agent))
  end

  def json_request(method, url, body \\ "", headers \\ [], options \\ []) do
    raw_request(method, url, body, headers, options)
  end

  def raw_request(method, url, body \\ "", headers \\ [], options \\ []) do
    request!(method, url, body, headers, extra_options ++ options) |> process_response
  end

  def request_stream(method, url, auth, body \\ "", override \\ nil) do
    request_with_pagination(method, url, auth, body)
    |> stream_if_needed(override)
  end

  @resources [
    applications: "/applications/",
    candidates: "/candidates/",
    departments: "/departments/",
    email_templates: "/email_templates/",
    job_posts: "/job_posts/",
    jobs: "/jobs/",
    offers: "/offers/",
    offices: "/offices/",
    rejection_reasons: "/rejection_reasons/",
    scorecards: "/scorecards/",
    sources: "/sources/",
    users: "/users/"
  ]

  for {resource, path} <- @resources do
    def unquote(resource)(%Greenhouse.Client{} = client, params \\ [], options \\ []) do
      unquote(path)
      |> get(client, params, options)
    end

    def get_by_id(unquote(resource), id, %Greenhouse.Client{} = client) do
      unquote(path) <> Integer.to_string(id)
      |> get(client)
    end
  end

  defp stream_if_needed(result = {status_code, _}, _) when is_number(status_code), do: result
  defp stream_if_needed({body, nil, _}, _), do: body
  defp stream_if_needed({body, _, _}, :one_page), do: body
  defp stream_if_needed(initial_results, _) do
    Stream.resource(
      fn -> initial_results end,
      &process_stream/1,
      fn _ -> nil end)
  end

  defp realize_if_needed(x) when is_tuple(x) or is_binary(x) or is_list(x) or is_map(x), do: x
  defp realize_if_needed(stream), do: Enum.to_list(stream)

  defp process_stream({[], nil, _}), do: {:halt, nil}
  defp process_stream({[], next, auth}) do
    request_with_pagination(:get, next, auth, "")
    |> process_stream
  end
  defp process_stream({items, next, auth}) when is_list(items) do
    {items, {[], next, auth}}
  end
  defp process_stream({item, next, auth}) do
    {[item], {[], next, auth}}
  end

  defp extra_options do
    Application.get_env(:greenhouse, :request_options, [])
  end

  defp pagination(options \\ []) do
    Keyword.get(options, :pagination,
      Application.get_env(:greenhouse, :pagination, nil))
  end

  def request_with_pagination(method, url, auth, body \\ "") do
    resp = request!(method, url, body, authorization_header(auth, @user_agent), extra_options)
    case process_response(resp) do
      x when is_tuple(x) -> x
      _ -> pagination_tuple(resp, auth)
    end
  end

  defp pagination_tuple(%HTTPoison.Response{headers: headers} = resp, auth) do
    {process_response(resp), next_link(headers), auth}
  end

  defp next_link(headers) do
    for {"Link", link_header} <- headers, links <- String.split(link_header, ",") do
      Regex.named_captures(~r/<(?<link>.*)>;\s*rel=\"(?<rel>.*)\"/, links)
      |> case do
        %{"link" => link, "rel" => "next"} -> link
        _ -> nil
      end
    end
    |> Enum.filter(&(not is_nil(&1)))
    |> List.first
  end

  @doc """
  Take an existing URI and add addition params, appending and replacing as necessary
  ## Examples
      iex> add_params_to_url("http://example.com/wat", [])
      "http://example.com/wat"
      iex> add_params_to_url("http://example.com/wat", [q: 1])
      "http://example.com/wat?q=1"
      iex> add_params_to_url("http://example.com/wat", [q: 1, t: 2])
      "http://example.com/wat?q=1&t=2"
      iex> add_params_to_url("http://example.com/wat", %{q: 1, t: 2})
      "http://example.com/wat?q=1&t=2"
      iex> add_params_to_url("http://example.com/wat?q=1&t=2", [])
      "http://example.com/wat?q=1&t=2"
      iex> add_params_to_url("http://example.com/wat?q=1", [t: 2])
      "http://example.com/wat?q=1&t=2"
      iex> add_params_to_url("http://example.com/wat?q=1", [q: 3, t: 2])
      "http://example.com/wat?q=3&t=2"
      iex> add_params_to_url("http://example.com/wat?q=1&s=4", [q: 3, t: 2])
      "http://example.com/wat?q=3&s=4&t=2"
      iex> add_params_to_url("http://example.com/wat?q=1&s=4", %{q: 3, t: 2})
      "http://example.com/wat?q=3&s=4&t=2"
  """
  @spec add_params_to_url(binary, list) :: binary
  def add_params_to_url(url, params) do
    url
    |> URI.parse
    |> merge_uri_params(params)
    |> String.Chars.to_string
  end

  @spec merge_uri_params(URI.t, list) :: URI.t
  defp merge_uri_params(uri, []), do: uri
  defp merge_uri_params(%URI{query: nil} = uri, params) when is_list(params) or is_map(params) do
    uri
    |> Map.put(:query, URI.encode_query(params))
  end
  defp merge_uri_params(%URI{} = uri, params) when is_list(params) or is_map(params) do
    uri
    |> Map.update!(:query, fn q -> q |> URI.decode_query |> Map.merge(param_list_to_map_with_string_keys(params)) |> URI.encode_query end)
  end

  @spec param_list_to_map_with_string_keys(list) :: map
  defp param_list_to_map_with_string_keys(list) when is_list(list) or is_map(list) do
    for {key, value} <- list, into: Map.new do
      {"#{key}", value}
    end
  end

  defp url(_client = %Client{endpoint: endpoint}, path) do
    endpoint <> path
  end

  def authorization_header(%{user: user, password: password}, headers) do
    userpass = "#{user}:#{password}"
    headers ++ [{"Authorization", "Basic #{:base64.encode(userpass)}"}]
  end

  def authorization_header(%{access_token: token}, headers) do
    userpass = token <> ":"
    headers ++ [{"Authorization", "Basic #{:base64.encode(userpass)}"}]
  end

  def authorization_header(_, headers), do: headers

  @doc """
  Same as `authorization_header/2` but defaults initial headers to include `@user_agent`.
  """
  def authorization_header(options), do: authorization_header(options, @user_agent)

end
