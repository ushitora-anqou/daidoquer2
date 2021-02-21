defmodule Daidoquer2.MessageSanitizer do
  @dummy "。ちくわ大明神。"
  @message_length_limit 100

  def sanitize(text) do
    text
    |> replace_with_alternatives
    |> replace_url_with_dummy
    |> replace_code_block_with_dummy
    |> replace_custom_emoji_with_name
    |> replace_emoji_with_name
    |> unify_punctuations
    |> replace_non_sjis_with_empty
    |> omit_if_too_long
    |> String.trim()
  end

  defp replace_with_alternatives(text) do
    text
    |> String.replace("ゔ", "ヴ")
    |> String.replace("ゕ", "ヵ")
    |> String.replace("ゖ", "ヶ")
    |> String.replace("ヷ", "ヴァ")
    |> String.replace("〜", "ー")
  end

  defp replace_url_with_dummy(text) do
    re = ~r/(?:http(s)?:\/\/)?[\w.-]+(?:\.[\w\.-]+)+[\w\-\._~:\/?#[\]@!\$%&'\(\)\*\+,;=.]+/u
    Regex.replace(re, text, @dummy)
  end

  defp replace_code_block_with_dummy(text) do
    re = ~r/```.+```/s
    Regex.replace(re, text, @dummy)
  end

  defp replace_custom_emoji_with_name(text) do
    re = ~r/<:([^:]+):[0-9]+>/
    Regex.replace(re, text, "\\1")
  end

  defp replace_emoji_with_name(text) do
    text
    |> Emojix.replace(fn e ->
      case e.shortcodes do
        [shortcode | _] -> shortcode
        [] -> ""
      end
    end)
  end

  defp unify_punctuations(text) do
    text
    |> String.replace(~r/[,、]+/u, "、")
    |> String.replace(~r/[.。]+/u, "。")
    |> String.replace(~r/[!！][!！?？]+/u, "！")
    |> String.replace(~r/[?？][!！?？]+/u, "？")
  end

  defp replace_non_sjis_with_empty(text) do
    text |> MbcsRs.encode!("SJIS") |> MbcsRs.decode!("SJIS")
  end

  defp omit_if_too_long(text) do
    if String.length(text) <= @message_length_limit do
      text
    else
      String.slice(text, 0, @message_length_limit) <> "。以下ちくわ大明神。"
    end
  end
end
