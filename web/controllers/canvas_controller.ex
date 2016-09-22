defmodule CanvasAPI.CanvasController do
  use CanvasAPI.Web, :controller

  alias CanvasAPI.{Canvas, ChangesetView, ErrorView, Repo, User}

  plug CanvasAPI.CurrentAccountPlug when not action in [:show]
  plug :ensure_team when not action in [:show]
  plug :ensure_user when not action in [:show]

  def create(conn, params) do
    changeset =
      %Canvas{}
      |> Canvas.changeset(get_in(params, ~w(data attributes)) || %{})
      |> Ecto.Changeset.put_assoc(:creator, conn.private.current_user)
      |> Ecto.Changeset.put_assoc(:team, conn.private.current_team)
      |> Canvas.put_template(get_in(params, ~w(data relationships template data)))

    case Repo.insert(changeset) do
      {:ok, canvas} ->
        conn
        |> put_status(:created)
        |> render("show.json", canvas: canvas)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ChangesetView, "error.json", changeset: changeset)
    end
  end

  def index(conn, _params) do
    canvases =
      Ecto.assoc(conn.private.current_user, :canvases)
      |> Repo.all

    render(conn, "index.json", canvases: canvases)
  end

  def index_templates(conn, _params) do
    templates =
      from(c in Ecto.assoc(conn.private.current_user, :canvases),
           where: c.is_template == true)
      |> Repo.all
      |> merge_global_templates
      |> Enum.sort_by(fn template ->
        template.blocks |> Enum.at(0) |> Map.get("content")
      end)

    render(conn, "index.json", canvases: templates)
  end

  def show(conn, params = %{"id" => id, "team_id" => team_id}) do
    canvas =
      from(c in Canvas,
           where: c.team_id == ^team_id)
      |> Repo.get(id)

    case canvas do
      canvas = %Canvas{} ->
        conn
        |> maybe_put_octet_stream(params["trailing_format"])
        |> render("show.json", canvas: canvas)
      nil ->
        conn
        |> put_status(:not_found)
        |> render(ErrorView, "404.json")
    end
  end

  def delete(conn, %{"id" => id}) do
    canvas =
      conn.private.current_team
      |> Ecto.assoc(:canvases)
      |> Repo.get(id)

    if canvas do
      Repo.delete!(canvas)

      conn
      |> send_resp(:no_content, "")
    else
      conn
      |> put_status(:not_found)
      |> render(ErrorView, "404.json")
    end
  end

  defp ensure_team(conn, _opts) do
    team =
      from(t in Ecto.assoc(conn.private.current_account, :teams))
      |> Repo.get(conn.params["team_id"])

    if team do
      conn
      |> put_private(:current_team, team)
    else
      conn
      |> halt
      |> put_status(:not_found)
      |> render(ErrorView, "404.json")
    end
  end

  defp ensure_user(conn, _opts) do
    user =
      from(u in Ecto.assoc(conn.private.current_account, :users),
           where: u.team_id == ^conn.private.current_team.id,
           limit: 1)
      |> Repo.all
      |> Enum.at(0)

    if user do
      conn
      |> put_private(:current_user, user)
    else
      conn
      |> halt
      |> put_status(:not_found)
      |> render(ErrorView, "404.json")
    end
  end

  defp maybe_put_octet_stream(conn, "canvas") do
    conn |> put_resp_header("content-type", "application/octet-stream")
  end
  defp maybe_put_octet_stream(conn, _), do: conn

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
           where: c.is_template == true)
      |> Repo.all)
  end
end
