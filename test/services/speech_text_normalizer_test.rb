require "test_helper"

class SpeechTextNormalizerTest < ActiveSupport::TestCase
  test "金額を漢数字の表記へ変換する" do
    {
      "8000円です。" => "八千円です。",
      "8800円です。" => "八千八百円です。",
      "3000円です。" => "三千円です。",
      "10000円です。" => "一万円です。",
      "1980円です。" => "千九百八十円です。",
      "100円です。" => "百円です。",
      "15円です。" => "十五円です。",
      "0円です。" => "ゼロ円です。",
      "120000円です。" => "十二万円です。",
      "10000000円です。" => "千万円です。",
      "123456789円です。" => "一億二千三百四十五万六千七百八十九円です。"
    }.each do |input, expected|
      assert_equal expected, normalize(input), input
    end
  end

  test "金額の全角数字と桁区切りのカンマに対応する" do
    {
      "８０００円です。" => "八千円です。",
      "8,000円です。" => "八千円です。",
      "8，800円です。" => "八千八百円です。",
      "１，９８０円です。" => "千九百八十円です。",
      "1,234,567円です。" => "百二十三万四千五百六十七円です。"
    }.each do |input, expected|
      assert_equal expected, normalize(input), input
    end
  end

  test "数字と漢字の単位が混ざる金額は変更しない" do
    [
      "1万円です。",
      "1万8000円です。",
      "3千円です。",
      "八千円です。"
    ].each do |input|
      assert_equal input, normalize(input), input
    end
  end

  test "日付の1日はついたちと読む" do
    {
      "10月1日から始まります。" => "10月ついたちから始まります。",
      "毎月1日に引き落とされます。" => "毎月ついたちに引き落とされます。",
      "来月１日からです。" => "来月ついたちからです。",
      "毎月1日だけ割引です。" => "毎月ついたちだけ割引です。"
    }.each do |input, expected|
      assert_equal expected, normalize(input), input
    end
  end

  test "期間の1日はいちにちと読む" do
    {
      "1日あたり300円です。" => "いちにちあたり三百円です。",
      "1日だけ試せます。" => "いちにちだけ試せます。",
      "1日中使えます。" => "いちにち中使えます。",
      "1日間の無料体験です。" => "いちにち間の無料体験です。",
      "１日分の料金です。" => "いちにち分の料金です。"
    }.each do |input, expected|
      assert_equal expected, normalize(input), input
    end
  end

  test "文脈が判断できない1日や1日以外の日付は変更しない" do
    [
      "1日に伺います。",
      "1日です。",
      "10月11日です。",
      "11日あたりです。",
      "21日中に届きます。",
      "10月2日です。"
    ].each do |input|
      assert_equal input, normalize(input), input
    end
  end

  test "年間と月数の期間表記を漢数字へ変換する" do
    {
      "1年間使えます。" => "一年間使えます。",
      "2年間の契約です。" => "二年間の契約です。",
      "2か月無料です。" => "二か月無料です。",
      "3ヶ月です。" => "三ヶ月です。",
      "6カ月です。" => "六カ月です。",
      "12ヵ月です。" => "十二ヵ月です。"
    }.each do |input, expected|
      assert_equal expected, normalize(input), input
    end
  end

  test "範囲表記は両方の数字を変換し単位を維持する" do
    {
      "1〜2か月かかります。" => "一から二か月かかります。",
      "1～2か月です。" => "一から二か月です。",
      "3000~5000円です。" => "三千から五千円です。",
      "10〜20GBです。" => "十から二十ギガバイトです。"
    }.each do |input, expected|
      assert_equal expected, normalize(input), input
    end
  end

  test "通信量と通信速度の単位を読み上げ用に変換する" do
    {
      "10GBのプランです。" => "十ギガバイトのプランです。",
      "1Gbpsの回線です。" => "一ギガビーピーエスの回線です。",
      "10 GBです。" => "十ギガバイトです。",
      "１０GBです。" => "十ギガバイトです。"
    }.each do |input, expected|
      assert_equal expected, normalize(input), input
    end
  end

  test "複数の変換対象を含む文章をまとめて変換する" do
    assert_equal(
      "毎月ついたちに更新され、十ギガバイトで八千円、" \
      "一ギガビーピーエスの回線を一年間、いちにちあたり約二百六十円です。",
      normalize(
        "毎月1日に更新され、10GBで8,000円、" \
        "1Gbpsの回線を1年間、1日あたり約260円です。"
      )
    )
  end

  test "通常の文章・URL・電話番号・型番・小数・時刻は変更しない" do
    [
      "いらっしゃいませ。本日はどのようなご用件でしょうか？",
      "詳しくは https://example.com/plans/8000円 をご覧ください。",
      "お問い合わせは03-1234-5678までお願いします。",
      "0120-123-456にお電話ください。",
      "iPhone15を使っています。",
      "型番はRX-1980円モデルです。",
      "SH-02Lという機種です。",
      "1.5GBのプランです。",
      "0.5か月分です。",
      "10:00に開店します。",
      "2026年10月です。",
      "3人家族です。",
      "10GBXという型番です。",
      "#8000円"
    ].each do |input|
      assert_equal input, normalize(input), input
    end
  end

  test "先頭が0の数字は変換しない" do
    assert_equal "08000円です。", normalize("08000円です。")
  end

  test "空文字列やnilでも安全に処理する" do
    assert_equal "", normalize("")
    assert_equal "", normalize(nil)
  end

  test "元のテキストを変更しない" do
    original = +"8000円です。"

    normalize(original)

    assert_equal "8000円です。", original
  end

  private

  def normalize(text)
    SpeechTextNormalizer.new(text).call
  end
end
