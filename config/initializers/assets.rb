# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Bootstrap Iconsのフォント（トップ画面・ログイン画面のアイコン）
Rails.application.config.assets.paths << Rails.root.join("node_modules/bootstrap-icons/font/fonts")
Rails.application.config.assets.precompile += %w[bootstrap-icons.woff2 bootstrap-icons.woff]

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
# Rails.application.config.assets.precompile += %w[ admin.js admin.css ]
