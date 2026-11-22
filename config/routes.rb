Rails.application.routes.draw do
  # 練習履歴（AIロープレのみを表示する）
  resources :practices, only: [ :index ]

  post "internal/practice_retention", to: "internal/practice_retention#destroy"
  get "internal/practice_retention/dry_run", to: "internal/practice_retention#dry_run"

  # 通常録画は廃止した（Issue #66）。旧URLはカテゴリ選択画面へ転送する
  get "practice_themes", to: redirect("/practice_categories", status: 302)
  get "practice_themes/:id", to: redirect("/practice_categories", status: 302)

  resources :practice_themes, only: [] do
    # 練習テーマを起点とした旧AIロープレ開始URLは、カテゴリ選択画面へ転送する（Issue #86）
    get :ai_roleplay, on: :member, to: redirect("/practice_categories", status: 302)
  end

  # カテゴリ選択 → 商材選択 → AIロープレ開始（Issue #86）
  resources :practice_categories, only: [ :index, :show ]
  get "products/:product_id/ai_roleplay", to: "ai_roleplays#show", as: :product_ai_roleplay

  resources :ai_roleplays, only: [ :create ] do
    get :evaluation, on: :member
    get :video, on: :member
    # 録画だけを削除する（評価・会話などの学習記録は残す。Issue #89）
    delete :video, on: :member, action: :destroy_video
  end

  post "ai_roleplays/synthesize", to: "ai_roleplays#synthesize"
  post "ai_roleplays/respond", to: "ai_roleplays#respond"
  post "ai_roleplays/transcribe", to: "ai_roleplays#transcribe"

  # 最後の最高管理者がアカウントを削除できないよう、アカウント削除の処理だけを差し替える
  devise_for :users, controllers: { registrations: "users/registrations" }

  namespace :admin do
    root to: "dashboard#show"

    # 物理削除は行わない。有効・無効、公開・非公開は専用のアクションでのみ切り替える
    resources :product_categories, only: %i[index new create edit update] do
      member do
        patch :activate
        patch :deactivate
      end
    end

    resources :products, only: %i[index show new create edit update] do
      member do
        patch :publish
        patch :unpublish
      end
    end

    # 新規登録の招待（Issue #90）。招待は削除せず、取り消しは専用のアクションでのみ行う
    resources :invitations, only: %i[index new create] do
      patch :revoke, on: :member
    end

    # 最高管理者専用の機能（GET /admin/super_admin）
    namespace :super_admin do
      root to: "dashboard#show"
    end
  end

  get "home/index"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # ログイン済みの場合は、/ でマイページを表示する（ログイン・ログアウト後の遷移先はDevise既定のroot_pathのまま）
  authenticated :user do
    root "mypages#show", as: :authenticated_root
  end

  # Defines the root path route ("/")
  root "home#index"
end
