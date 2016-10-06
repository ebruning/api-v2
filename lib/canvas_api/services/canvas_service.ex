defmodule CanvasAPI.CanvasService do
  @moduledoc """
  A service for viewing and manipulating canvases.
  """

  use CanvasAPI.Web, :service
  alias CanvasAPI.{Canvas, SlackChannelNotifier, Team, User}

  @preload [:team, creator: [:team]]

  @doc """
  Create a new canvas from the given params.

  The creator must provide a team and creator, and can optionally provide a
  template.

  Options:

  - `creator`: `%User{}` (**required**) The user who created the canvas
  - `team`: `%Team{}` (**required**) The team to create the canvas in
  - `template`: `map` A map with `"type" => "canvas"` and an ID for the new
     canvas's template. **Ignored if the template is not found.**

  ## Examples

  ```elixir
  CanvasService.create(
    %{"is_template" => true},
    creator: current_user,
    team: current_team,
    template: %{"id" => "6ijSghOIflAjKVki5j0dpL", "type" => "canvas"})
  ```
  """
  @spec create(map, Keyword.t) :: {:ok, %Canvas{}} | {:error, Ecto.Changeset.t}
  def create(params, opts) do
    %Canvas{}
    |> Canvas.changeset(params)
    |> put_assoc(:creator, opts[:creator])
    |> put_assoc(:team, opts[:team])
    |> Canvas.put_template(opts[:template])
    |> Repo.insert
    |> case do
      {:ok, canvas} ->
        if opts[:notify],
          do: notify_slack(opts[:notify], canvas, [], delay: 300)
        {:ok, Repo.preload(canvas, @preload)}
      error ->
        error
    end
  end

  @doc """
  List canvases on behalf of a user.

  Available filters:

  - `user`: `%User{}` (**required**) A user to list canvases for
  - `only_templates`: `boolean` List only templates canvases, including global
    templates, if they are defined.

  ## Examples

  ```elixir
  CanvasService.list(user: current_user, only_templates: true)
  ```
  """
  @spec list(Keyword.t) :: [%Canvas{}] | []
  def list(user: user) do
    from(assoc(user, :canvases), preload: ^@preload)
    |> Repo.all
  end

  def list(user: user, only_templates: true) do
    from(assoc(user, :canvases),
         where: [is_template: true],
         preload: ^@preload)
    |> Repo.all
    |> merge_global_templates
    |> Enum.sort_by(&Canvas.title/1)
  end

  @doc """
  Show a canvas.

  ## Examples

  ```elixir
  CanvasService.show(
    "6ijSghOIflAjKVki5j0dpL", team_id: "87ee9199-e2fa-49e6-9d99-16988af57fd5")
  ```
  """
  @spec show(String.t, Keyword.t) :: %Canvas{} | nil
  def show(id, team_id: team_id) do
    from(Canvas, where: [team_id: ^team_id], preload: ^@preload)
    |> Repo.get(id)
  end

  @doc """
  Update a canvas.

  ## Examples

  ```elixir
  CanvasService.update(canvas, %{"is_template" => false})
  ```
  """
  @spec update(%Canvas{}, map, Keyword.t) :: {:ok, %Canvas{}} | {:error, Ecto.Changeset.t}
  def update(canvas, params, opts \\ []) do
    old_channel_ids = canvas.slack_channel_ids

    canvas
    |> Canvas.update_changeset(params)
    |> Repo.update
    |> case do
      {:ok, canvas} ->
        if opts[:notify],
          do: notify_slack(opts[:notify], canvas, old_channel_ids)
        {:ok, Repo.preload(canvas, @preload)}
      error ->
        error
    end
  end

  @doc """
  Delete a canvas.

  If the canvas is not found, returns `nil`. If the delete was invalid, returns
  `{:error, changeset}`. If it was successful, returns `{:ok, canvas}`.

  ## Examples

  ```elixir
  CanvasService.delete(
    "6ijSghOIflAjKVki5j0dpL", team_id: "87ee9199-e2fa-49e6-9d99-16988af57fd5")
  ```
  """
  @spec delete(String.t, Keyword.t) :: {:ok, %Canvas{}} | nil | {:error, Ecto.Changeset.t}
  def delete(id, team_id: team_id) do
    case show(id, team_id: team_id) do
      canvas = %Canvas{} -> Repo.delete(canvas)
      nil -> nil
    end
  end

  defp merge_global_templates(team_templates) do
    do_merge_global_templates(
      team_templates, System.get_env("TEMPLATE_USER_ID"))
  end

  defp do_merge_global_templates(templates, nil), do: templates
  defp do_merge_global_templates(templates, id) do
    templates ++
      (from(c in Canvas,
           join: u in User, on: u.id == c.creator_id,
           where: u.id == ^id,
           where: c.is_template == true,
           preload: [creator: [:team]])
      |> Repo.all)
  end

  @spec notify_slack(%User{}, %Canvas{}, list, Keyword.t) :: any
  defp notify_slack(notifier, canvas, old_channel_ids, opts \\ []) do
    token =
      Team.get_token(canvas.team, "slack")
      |> Map.get(:meta)
      |> get_in(~w(bot bot_access_token))

    (canvas.slack_channel_ids -- old_channel_ids)
    |> Enum.each(
      &SlackChannelNotifier.delay_notify_new(
        token, canvas.id, notifier.id, &1, opts))
  end
end