# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_10_10_013404) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_roleplay_evaluations", force: :cascade do |t|
    t.bigint "ai_roleplay_session_id", null: false
    t.integer "hearing_score"
    t.text "hearing_good_point"
    t.text "hearing_improvement_point"
    t.integer "listening_score"
    t.text "listening_good_point"
    t.text "listening_improvement_point"
    t.integer "needs_score"
    t.text "needs_good_point"
    t.text "needs_improvement_point"
    t.integer "proposal_score"
    t.text "proposal_good_point"
    t.text "proposal_improvement_point"
    t.integer "closing_score"
    t.text "closing_good_point"
    t.text "closing_improvement_point"
    t.integer "reference_score"
    t.text "overall_strength"
    t.text "priority_improvement"
    t.text "next_practice_goal"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_roleplay_session_id"], name: "index_ai_roleplay_evaluations_on_ai_roleplay_session_id", unique: true
  end

  create_table "ai_roleplay_messages", force: :cascade do |t|
    t.bigint "ai_roleplay_session_id", null: false
    t.string "role", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_roleplay_session_id"], name: "index_ai_roleplay_messages_on_ai_roleplay_session_id"
  end

  create_table "ai_roleplay_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "practice_theme_id", null: false
    t.float "duration"
    t.string "end_reason"
    t.datetime "started_at"
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["practice_theme_id"], name: "index_ai_roleplay_sessions_on_practice_theme_id"
    t.index ["user_id"], name: "index_ai_roleplay_sessions_on_user_id"
  end

  create_table "analyses", force: :cascade do |t|
    t.bigint "practice_id", null: false
    t.integer "total_score"
    t.integer "smile_score"
    t.float "voice_brightness"
    t.integer "voice_brightness_score"
    t.float "voice_clarity"
    t.integer "voice_clarity_score"
    t.float "speech_speed"
    t.integer "speech_speed_score"
    t.integer "filler_count"
    t.integer "filler_score"
    t.float "volume"
    t.integer "volume_score"
    t.text "ai_comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["practice_id"], name: "index_analyses_on_practice_id"
  end

  create_table "practice_themes", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "practices", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "practice_theme_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "transcription"
    t.float "duration"
    t.index ["practice_theme_id"], name: "index_practices_on_practice_theme_id"
    t.index ["user_id"], name: "index_practices_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_roleplay_evaluations", "ai_roleplay_sessions"
  add_foreign_key "ai_roleplay_messages", "ai_roleplay_sessions"
  add_foreign_key "ai_roleplay_sessions", "practice_themes"
  add_foreign_key "ai_roleplay_sessions", "users"
  add_foreign_key "analyses", "practices"
  add_foreign_key "practices", "practice_themes"
  add_foreign_key "practices", "users"
end
