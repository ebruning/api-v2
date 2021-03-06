defmodule CanvasAPI.Canvas do
  @moduledoc """
  A document containing content represented as nested JSON blocks that is
  editable in realtime.
  """

  use CanvasAPI.Web, :model

  alias CanvasAPI.Block

  @primary_key {:id, CanvasAPI.Base62UUIDField, autogenerate: true}
  @type t :: %__MODULE__{}

  schema "canvases" do
    field :is_template, :boolean, default: false
    field :link_access, :string, default: "none"
    field :native_version, :string, default: "1.0.0"
    field :type, :string, default: "http://sharejs.org/types/JSONv0"
    field :version, :integer, default: 0
    field :slack_channel_ids, {:array, :string}, default: []
    field :edited_at, Calecto.DateTimeUTC

    field :markdown, :string, virtual: true

    belongs_to :creator, CanvasAPI.User
    belongs_to :team, CanvasAPI.Team
    belongs_to :template, CanvasAPI.Canvas, type: :string
    has_many :canvas_watches, CanvasAPI.CanvasWatch
    has_many :comments, CanvasAPI.Comment
    has_many :thread_subscriptions, CanvasAPI.ThreadSubscription
    has_many :ops, CanvasAPI.Op
    has_many :pulse_events, CanvasAPI.PulseEvent

    embeds_many :blocks, Block, on_replace: :delete

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:is_template, :link_access, :markdown, :slack_channel_ids])
    |> parse_markdown
    |> cast_embed(:blocks)
    |> validate_inclusion(:link_access, ~w(none read edit))
    |> put_change(:edited_at, DateTime.utc_now)
    |> put_title_block
    |> put_paragraph_block
  end

  @doc """
  Builds a changeset for updating a canvas.
  """
  def update_changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:is_template, :link_access, :slack_channel_ids])
    |> validate_inclusion(:link_access, ~w(none read edit))
  end

  @doc """
  Find a block in the given canvas.
  """
  def find_block(canvas, id) do
    canvas.blocks
    |> Enum.find_value(fn block ->
      case block do
        %Block{id: ^id} -> block
        %Block{type: "list"} -> find_block(block, id)
        _ -> false
      end
    end)
  end

  @doc """
  Put a template in a canvas if present.

  TODO: This currently allows finding a canvas by ID only (not requiring to be
  in the team).
  """
  @spec put_template(Ecto.Changeset.t, map | nil, Keyword.t) :: Ecto.Changeset.t
  def put_template(changeset, data, opts \\ [])

  def put_template(changeset, %{"id" => id, "type" => "canvas"}, opts) do
    case Repo.get(__MODULE__, id) do
      nil ->
        changeset
      template = %__MODULE__{blocks: blocks} ->
        if opts[:ignore_blocks] do
          changeset
        else
          changeset
          |> cast(%{blocks: Enum.map(blocks, &Block.to_params/1)}, [])
          |> cast_embed(:blocks)
        end
        |> put_assoc(:template, template)
    end
  end

  def put_template(changeset, _, _), do: changeset

  @doc """
  Get the summary of a canvas.
  """
  @spec summary(t | Canvas.Comment.t) :: String.t
  def summary(%{blocks: blocks}) do
    blocks
    |> Enum.find(&(&1.type !== "title"))
    |> case do
      %Block{blocks: [block | _]} ->
        String.slice(block.content, 0..140)
      %Block{content: content} ->
        String.slice(content, 0..140)
      nil ->
        ""
    end
  end

  @doc """
  Get the title of a canvas.
  """
  @spec title(%__MODULE__{}) :: String.t
  def title(%__MODULE__{blocks: blocks}) do
    case blocks do
      [%Block{type: "title", content: content} | _] -> content
      _ -> ""
    end
  end

  @doc """
  Get the web URL of a canvas.
  """
  @spec web_url(%__MODULE__{}) :: String.t
  def web_url(canvas) do
    "#{System.get_env("WEB_URL")}/#{canvas.team.domain}/#{canvas.id}"
  end

  # Put the title block, if necessary.
  @spec put_title_block(Ecto.Changeset.t) :: Ecto.Changeset.t
  defp put_title_block(changeset) do
    changeset
    |> get_change(:blocks)
    |> case do
      [%Ecto.Changeset{changes: %{type: "title"}} | _] ->
        changeset
      blocks_changeset when is_list(blocks_changeset) ->
        put_embed(changeset, :blocks, [title_changeset | blocks_changeset])
      nil ->
        put_embed(changeset, :blocks, [title_changeset])
    end
  end

  @spec put_paragraph_block(Ecto.Changeset.t) :: Ecto.Changeset.t
  defp put_paragraph_block(changeset) do
    blocks = get_change(changeset, :blocks)
    if Enum.count(blocks) == 1 do
      blocks = blocks ++ [Block.changeset(%Block{}, %{type: "paragraph"})]
      put_embed(changeset, :blocks, blocks)
    else
      changeset
    end
  end

  # Get a title block.
  @spec title_changeset :: Ecto.Changeset.t
  defp title_changeset do
    Block.changeset(%Block{}, %{type: "title"})
  end

  # Parse a Markdown change into a blocks param
  @spec parse_markdown(Ecto.Changeset.t) :: Ecto.Changeset.t
  defp parse_markdown(changeset) do
    if markdown = get_change(changeset, :markdown) do
      blocks = CanvasAPI.Markdown.parse(markdown)
      Map.put(changeset, :params, Map.put(changeset.params, "blocks", blocks))
    else
      changeset
    end
  end
end
