defmodule CanvasAPI.Unfurl.OpenGraph do
  def unfurl(url) do
    case HTTPoison.get(url, [], follow_redirect: true, max_redirect: 5) do
      {:ok, %{body: body, status_code: 200}} ->
        unfurl_from_body(body, url)
      _ ->
        nil
    end
  end

  defp unfurl_from_body(body, url) do
    og_tags = get_opengraph(body)

    %CanvasAPI.Unfurl{
      id: url,
      provider_name: og_tags["site_name"],
      provider_icon_url: "https://s3.amazonaws.com/canvas-assets/provider-icons/fallback.png",
      title: og_tags["title"] || url,
      text: og_tags["description"],
      thumbnail_url: og_tags["image"] ||
        og_tags["image:secure_url"] ||
        og_tags["image:url"]
    }
  end

  defp get_opengraph(html_body) do
    html_body
    |> Floki.find("meta")
    |> extract_opengraph
  end

  defp extract_opengraph(tags) do
    tags
    |> Enum.reduce(%{}, fn
      (tag = {"meta", attributes, _}, data) ->
        with key when not is_nil(key) <- find_opengraph_key(attributes),
             [value | _] <- Floki.attribute(tag, "content") do
          Map.put(data, key, value)
        else
          _ -> data
        end
    end)
  end

  defp find_opengraph_key(attributes) do
    attributes
    |> Enum.find_value(fn attribute ->
      case attribute do
        {"property", "og:" <> key} -> key
        _ -> nil
      end
    end)
  end
end