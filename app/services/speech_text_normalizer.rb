# 音声合成に渡す直前のテキストを、読み上げやすい表記へ変換する。
# 画面表示・会話履歴・AI評価に使う元の文章は変更しない。
class SpeechTextNormalizer
  KANJI_DIGITS = %w[〇 一 二 三 四 五 六 七 八 九].freeze
  SMALL_UNITS = [ "", "十", "百", "千" ].freeze
  LARGE_UNITS = [ "", "万", "億", "兆" ].freeze
  MAX_NUMBER = 10**16 - 1

  # 半角・全角数字。桁区切りのカンマを含む表記にも対応する
  DIGIT = "[0-9０-９]".freeze
  NUMBER = "#{DIGIT}{1,3}(?:[,，]#{DIGIT}{3})+|#{DIGIT}+".freeze

  # 英数字・記号・漢数字に続く数字は、型番・URL・電話番号・小数・「1万8000円」などの一部とみなして変換しない
  NOT_PART_OF_TOKEN = "(?<![0-9０-９A-Za-zＡ-Ｚａ-ｚ.．,，:/_\\-－#＃〜～~万億兆千百十〇一二三四五六七八九])".freeze

  RANGE_SEPARATOR = "[〜～~]".freeze

  NUMBER_WITH_RANGE =
    "#{NOT_PART_OF_TOKEN}(?<first>#{NUMBER})(?:(?<separator>#{RANGE_SEPARATOR})(?<second>#{NUMBER}))?".freeze

  YEN_PATTERN = /#{NUMBER_WITH_RANGE}(?<unit>円)/

  PERIOD_PATTERN = /#{NUMBER_WITH_RANGE}(?<unit>年間|[かカヵヶケ]月)/

  DATA_UNIT_READINGS = {
    "Gbps" => "ギガビーピーエス",
    "GB" => "ギガバイト"
  }.freeze

  DATA_PATTERN =
    /#{NUMBER_WITH_RANGE}[ 　]?(?<unit>Gbps|GB)(?![A-Za-z0-9])/

  # 「10月1日」「毎月1日」「来月1日」などの1日は日付（ついたち）
  FIRST_DAY_OF_MONTH_PATTERN =
    /(?<prefix>(?:#{DIGIT}|[〇一二三四五六七八九十毎今来先翌])月)[1１]日(?![0-9０-９])/

  # 「1日あたり」「1日だけ」「1日中」などの1日は期間（いちにち）
  ONE_DAY_PERIOD_PATTERN =
    /#{NOT_PART_OF_TOKEN}[1１]日(?=あたり|当たり|だけ|中|間|分|ごと|おき)/

  def initialize(text)
    @text = text
  end

  def call
    text = @text.to_s.dup

    return text if text.empty?

    text = text.gsub(FIRST_DAY_OF_MONTH_PATTERN) do
      "#{Regexp.last_match[:prefix]}ついたち"
    end

    text = text.gsub(ONE_DAY_PERIOD_PATTERN, "いちにち")

    text = text.gsub(YEN_PATTERN) do
      convert_number_with_unit(Regexp.last_match)
    end

    text = text.gsub(PERIOD_PATTERN) do
      convert_number_with_unit(Regexp.last_match)
    end

    text.gsub(DATA_PATTERN) do
      match = Regexp.last_match

      convert_number_with_unit(
        match,
        unit: DATA_UNIT_READINGS.fetch(match[:unit])
      )
    end
  end

  private

  def convert_number_with_unit(match, unit: match[:unit])
    first = to_kanji(match[:first])
    return match[0] if first.nil?

    return "#{first}#{unit}" if match[:second].nil?

    second = to_kanji(match[:second])
    return match[0] if second.nil?

    "#{first}から#{second}#{unit}"
  end

  # 漢数字に変換できない値（先頭が0の数字、桁数が大きすぎる数字）はnilを返す
  def to_kanji(number_text)
    digits = number_text.tr("０-９", "0-9").delete(",，")

    return if digits.length > 1 && digits.start_with?("0")

    number = digits.to_i

    return if number > MAX_NUMBER
    return "ゼロ" if number.zero?

    groups = number.digits(10_000)

    groups.each_with_index.reverse_each.map do |group, index|
      next "" if group.zero?

      "#{group_to_kanji(group)}#{LARGE_UNITS[index]}"
    end.join
  end

  def group_to_kanji(group)
    group.digits.each_with_index.reverse_each.map do |digit, index|
      next "" if digit.zero?

      # 十・百・千の前の「一」は読まない（例：千九百八十）
      prefix = digit == 1 && index.positive? ? "" : KANJI_DIGITS[digit]

      "#{prefix}#{SMALL_UNITS[index]}"
    end.join
  end
end
