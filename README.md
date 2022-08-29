# Daidoquer2

_「こんにちは、daidoquer2です。やさしくしてね。」_

## これはなに？

Discord用の読み上げbotです。テキストチャンネルに流れてきたメッセージを音声で読み上げます。Discord上で声を出せる人と出せない人がコミュニケーションを取るときに便利です。

以下のような特長があります：

- VOICEVOXやGoogle TTSなどの様々なボイスに対応。
  - デフォルトで、Google TTS及び[WEB版VOICEVOX API](https://voicevox.su-shiki.com/su-shikiapis/)に対応しています（トークンを準備する必要あり）。
  - その他のボイスでも、HTTP経由で音声をやりとりするサーバを立てることで簡単に対応できます。例えばCeVIO AIのAPIを経由することでCeVIO AIの音声も使用できます（[事例](https://github.com/bbtatt/CeVIOAIInterfaceHttpServer)）。
- ロールに応じて読み上げボイスを変更可能。
  - 他に、ユーザIDごとに読み上げボイスを設定することもできます。
- 自動でボイスチャネルに入室・退室可能。
- ユーザの入室・退室・ライブ開始・ライブ停止を声でお知らせ。
- 他のユーザが喋っているときには音量を自動的に小さくすることが可能。
- 一度起動すれば複数サーバに導入可能。
- オープンソースソフトウェア（AGPL-3.0）として公開。
  - 内部で読み上げログなどを不正に保存していないことなどを自分で確認できます。

## 使い方

### Docker を使って構築

```
$ git clone https://github.com/ushitora-anqou/daidoquer2.git
$ cd daidoquer2
$ cp config/runtime.exs.default config/runtime.exs
$ vim config/env
# Set Discord token obtained from https://discord.com/developers/applications
DISCORD_TOKEN='XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
# Set API key for su-shiki.com obtained from https://su-shiki.com/api/
SUSHIKICOM_API_TOKEN="XXXXXXXXXXXXXXX"
# Set path to cred for Google TTS (if necessary)
GOOGLE_APPLICATION_CREDENTIALS='/path/to/cred.json'
$ vim config/runtime.exs
# Update settings as you like
$ docker build -t ddq2 --build-arg DDQ2_VERSION=$(git tag -l | sort -V | tail -1 | sed 's/^.//') --build-arg ARCH=amd64 .
$ docker run -v $PWD/config:/app-config ddq2:latest
```

TODO: もう少し丁寧に手順を書く。
