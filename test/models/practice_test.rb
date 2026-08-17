require "test_helper"

class PracticeTest < ActiveSupport::TestCase
  test "practice belongs to user" do
    practice = practices(:one)

    assert_equal users(:one), practice.user
  end

  test "practice belongs to practice theme" do
    practice = practices(:one)

    assert_equal practice_themes(:one), practice.practice_theme
  end

  test "practice can be created with user and practice theme" do
    practice = Practice.new(
      user: users(:one),
      practice_theme: practice_themes(:one)
    )

    assert practice.save
  end
end
