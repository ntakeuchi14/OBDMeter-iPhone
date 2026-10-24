# OBDMeter (iPhone 版)

BMW E90 (N54 / MSD80) 向けの OBD メーターアプリ [OBDMeter (Android)](https://github.com/ntakeuchi14/OBDMeter) の iPhone 版です。
SwiftUI で作り直しています。設定のバックアップ (zip) は Android 版と同じ形式なので、Android 版で作ったページをそのまま読み込めます。

## Android 版との違い

| | Android 版 | iPhone 版 |
|---|---|---|
| アダプター | USB (OBDLink SX / K+DCAN) | **Bluetooth LE** (OBDLink CX / MX+ など) / **Wi-Fi** の ELM327 |
| フロート表示 | あり | なし (iOS では他のアプリの上に表示できません) |
| 接続テスト・BMW の値探し | あり | なし |
| iDrive でのページ切替 | あり | なし |

- iPhone は USB シリアルのアダプターと Bluetooth クラシック (SPP) のアダプターを使えません。
- メーター (アナログ・バー・デジタル・ランプ・値テーブル・折れ線グラフ・変動監視)、レイアウト編集 (グループ・重なり順・グリッド)、ページの背景、カスタム PID、BMW 固有の項目 (MSD80 の測定値・状態読み出し)、記録と CSV、フォントの取り込みは Android 版と同じです。

## IPA の作り方 (Mac 不要)

GitHub Actions (macOS) で未署名の IPA を作ります。

1. `main` に push すると [iOS Build](../../actions/workflows/ios.yml) が動きます。
2. 終わったら実行結果の画面の Artifacts から `OBDMeter-unsigned-ipa` をダウンロードし、zip を展開すると `OBDMeter-xxxx-unsigned.ipa` が入っています。
3. `v` で始まるタグ (例: `v1.0.0`) を push すると、Releases にも IPA が添付されます。

## iPhone へのインストール (Sideloadly)

1. Windows か Mac に [Sideloadly](https://sideloadly.io/) を入れ、iPhone をケーブルでつなぎます (Windows は iTunes / iCloud を Apple のサイト版で入れておく)。
2. Sideloadly に IPA をドラッグし、Apple ID を入力して Start。
3. iPhone の 設定 → 一般 → VPN とデバイス管理 で、自分の Apple ID の開発元を「信頼」します。
4. iOS 16 以降は 設定 → プライバシーとセキュリティ → デベロッパモード を ON にします (再起動あり)。

無料の Apple ID で入れたアプリは **7 日で起動できなくなる** ので、7 日以内に Sideloadly でもう一度入れ直してください (設定やページは残ります)。

## 使い方

1. 設定 → 接続方式 で「Bluetooth LE」か「Wi-Fi」を選びます。
   - Bluetooth LE: イグニッション ON で「アダプターを探す」→ 一覧からアダプターを選ぶ
   - Wi-Fi: iPhone をアダプターの Wi-Fi につなぎ、アドレス (多くは 192.168.0.10) とポート (35000) を確認
2. 右上のボタン → 「接続」。
3. Android 版の設定を使うときは、Android 版で エクスポートした zip を iPhone の「ファイル」に入れ、設定 → バックアップ → インポート で読み込みます。

## 開発

- `project.yml` から [XcodeGen](https://github.com/yonaskolb/XcodeGen) で Xcode プロジェクトを作ります (`xcodegen generate`)。
- 保存形式のモデルは `tools/gen_models.py` で生成しています (`python3 tools/gen_models.py > OBDMeter/Sources/Data/Models.generated.swift`)。
- BMW の項目一覧は Android 版の `Msd80Table.kt` / `Msd80StatusTable.kt` と同じ内容です (`OBDMeter/Resources/*.txt`)。
