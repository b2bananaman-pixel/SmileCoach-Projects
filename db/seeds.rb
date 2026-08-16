practice_themes = [
  {
    name: "家電の提案販売",
    description: "お客様像：冷蔵庫売り場に来店している30代くらいの男女。現在使用している冷蔵庫が古くなり、買い替えを検討している。\n\n接客条件：\n① お客様へ明るく声掛けをする\n② 現在の利用状況を確認する\n③ お客様に合ったサービスを提案する"
  },
  {
    name: "自動車の提案販売",
    description: "お客様像：自動車販売店に来店している30代くらいの夫婦。現在使用している車の買い替えを検討している。\n\n接客条件：\n① お客様へ明るく声掛けをする\n② 現在の利用状況を確認する\n③ お客様に合ったサービスを提案する"
  },
  {
    name: "インターネットの提案販売",
    description: "お客様像：携帯ショップに来店している40代くらいの男性。現在利用しているインターネットサービスの変更を検討している。\n\n接客条件：\n① お客様へ明るく声掛けをする\n② 現在の利用状況を確認する\n③ お客様に合ったサービスを提案する"
  },
  {
    name: "保険の提案販売",
    description: "お客様像：保険相談窓口に来店している30代くらいの男女。現在加入している保険の見直しを検討している。\n\n接客条件：\n① お客様へ明るく声掛けをする\n② 現在の利用状況を確認する\n③ お客様に合ったサービスを提案する"
  }
]

practice_themes.each do |theme|
  practice_theme = PracticeTheme.find_or_initialize_by(name: theme[:name])
  practice_theme.description = theme[:description]
  practice_theme.save!
end
