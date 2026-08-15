practice_themes = [
  {
    name: "家電",
    description: "家電に関する接客練習"
  },
  {
    name: "自動車",
    description: "自動車に関する接客練習"
  },
  {
    name: "インターネット",
    description: "インターネットに関する接客練習"
  },
  {
    name: "保険",
    description: "保険に関する接客練習"
  }
]

practice_themes.each do |theme|
  PracticeTheme.find_or_create_by!(name: theme[:name]) do |practice_theme|
    practice_theme.description = theme[:description]
  end
end