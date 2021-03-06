defmodule CanvasAPI.Unfurl.GitHub.Issue do
  @moduledoc """
  An unfurled GitHub issue.
  """

  @lint {Credo.Check.Readability.MaxLineLength, false}
  @match ~r|\Ahttps://(?:www\.)?github\.com/(?<owner>[^/]+)/(?<repo>[^/]+)/issues/(?<issue_id>\d+)/?\z|

  alias CanvasAPI.Unfurl
  alias Unfurl.GitHub.API, as: GitHubAPI
  alias Unfurl.{Field, Label}

  def match, do: @match

  @doc """
  Unfurl a GitHub issue URL.
  """
  @spec unfurl(url::String.t, options::Keyword.t) :: Unfurl.t | nil
  def unfurl(url, account: account) do
    with {:ok, %{body: body, status_code: 200}} <- do_get(account, url) do
      unfurl_from_body(url, body)
    else
      {:ok, _} ->
        unfurl_from_body(
          url,
          %{"title" => endpoint(url) |> String.replace("/repos/", "")},
          false)
      _ ->
        nil
    end
  end

  def unfurl_from_body(url, body, fetched \\ true) do
    %Unfurl{
      id: url,
      title: body["title"],
      text: issue_text(body),
      thumbnail_url: get_in(body, ~w(user avatar_url)),
      fields: fields(body),
      labels: labels(body["labels"]),
      fetched: fetched
    }
  end

  defp issue_text(body = %{"merged" => true}) do
    username = get_in(body, ~w(merged_by login))
    "##{body["number"]} merged #{time_ago(body["merged_at"])} by #{username}"
  end

  defp issue_text(body = %{"state" => "closed"}) do
    username = get_in(body, ~w(closed_by login))
    "##{body["number"]} closed #{time_ago(body["closed_at"])} by #{username}"
  end

  defp issue_text(body = %{"created_at" => created_at}) do
    username = get_in(body, ~w(user login))
    "##{body["number"]} opened #{time_ago(created_at)} by #{username}"
  end

  defp issue_text(_), do: nil

  defp fields(body = %{}) do
    add_state_field([], body)
    |> add_assignee_field(body)
  end

  defp add_state_field([], %{"merged" => true}) do
    [%Field{title: "State", value: "merged", short: true}]
  end

  defp add_state_field([], %{"state" => state}) do
    [%Field{title: "State", value: state, short: true}]
  end

  defp add_state_field([], _), do: []

  defp add_assignee_field(list, %{"assignees" => assignees}) do
    title =
      case length(assignees) do
        1 -> "Assignee"
        _ -> "Assignees"
      end

    assignee_names =
      assignees
      |> Enum.map(fn assignee -> assignee["login"] end)
      |> Enum.join(", ")

    list ++ [%Field{title: title, value: assignee_names, short: true}]
  end

  defp add_assignee_field(list, _), do: list

  defp do_get(account, url) do
    GitHubAPI.get_by(account, endpoint(url))
  end

  defp endpoint(url) do
    %{"owner" => owner, "repo" => repo, "issue_id" => issue_id} =
      Regex.named_captures(@match, url)
    "/repos/#{owner}/#{repo}/issues/#{issue_id}"
  end

  defp labels(nil), do: []

  defp labels(labels) do
    labels
    |> Enum.map(fn label ->
      %Label{color: "##{label["color"]}", value: label["name"]}
    end)
  end

  defp time_ago(time) do
    time
    |> Timex.parse!("{ISO:Extended}")
    |> Timex.from_now
  end
end
