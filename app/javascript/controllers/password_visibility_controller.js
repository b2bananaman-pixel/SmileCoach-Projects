import { Controller } from "@hotwired/stimulus"

// ログインフォームのパスワードの表示・非表示を切り替える（入力値や送信処理は変更しない）
export default class extends Controller {
  static targets = ["input", "button", "icon"]

  toggle() {
    const visible = this.inputTarget.type === "password"

    this.inputTarget.type = visible ? "text" : "password"
    this.buttonTarget.setAttribute("aria-label", visible ? "パスワードを隠す" : "パスワードを表示する")
    this.buttonTarget.setAttribute("aria-pressed", visible ? "true" : "false")
    this.iconTarget.classList.toggle("bi-eye", visible)
    this.iconTarget.classList.toggle("bi-eye-slash", !visible)
  }
}
