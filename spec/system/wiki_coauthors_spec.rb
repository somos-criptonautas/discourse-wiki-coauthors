# frozen_string_literal: true

RSpec.describe "Wiki co-authors" do
  let!(:component) { upload_theme_or_component }

  fab!(:author) { Fabricate(:user, username: "original_author") }
  fab!(:first_editor) { Fabricate(:user, username: "first_editor") }
  fab!(:second_editor) { Fabricate(:user, username: "second_editor") }

  fab!(:wiki_tag) { Fabricate(:tag, name: "wiki") }

  fab!(:target_category) { Fabricate(:category, name: "Docs") }
  fab!(:other_category) { Fabricate(:category, name: "Guides") }

  before do
    component.update_setting(:target_categories, target_category.id.to_s)
    component.save!
  end

  # A wiki post with one revision per editor, in the order given. Revisions are
  # what the component reads; a plain `post.update` would not create any.
  def wiki_post_in(category, editors: [], wiki: true, tags: [])
    post =
      Fabricate(
        :post,
        user: author,
        topic: Fabricate(:topic, category: category, tags: tags),
      )
    post.update!(wiki: wiki)

    editors.each_with_index do |editor, index|
      post.revise(editor, { raw: "#{post.raw} — edit #{index}" }, force_new_version: true)
    end

    post
  end

  def visit_post(post)
    visit "/t/#{post.topic.slug}/#{post.topic.id}"
  end

  # The list is avatars, so the username lives in the img alt. Overflow
  # avatars sit inside a closed `<details>` and are deliberately not counted.
  def listed_coauthors
    page.all(".wiki-coauthors__avatar").map { |avatar| avatar[:alt] }
  end

  def all_coauthors
    page.all(".wiki-coauthors__avatar", visible: :all).map { |avatar| avatar[:alt] }
  end

  it "lists each editor once, in the order they first edited" do
    post = wiki_post_in(target_category, editors: [second_editor, first_editor, second_editor])

    visit_post(post)

    expect(page).to have_css(".wiki-coauthors")
    expect(listed_coauthors).to eq(%w[second_editor first_editor])
  end

  it "excludes the post's own author" do
    post = wiki_post_in(target_category, editors: [author, first_editor])

    visit_post(post)

    expect(page).to have_css(".wiki-coauthors")
    expect(listed_coauthors).to eq(%w[first_editor])
  end

  it "never credits an excluded user" do
    component.update_setting(:excluded_users, "second_editor")
    component.save!
    post = wiki_post_in(target_category, editors: [first_editor, second_editor])

    visit_post(post)

    expect(page).to have_css(".wiki-coauthors")
    expect(listed_coauthors).to eq(%w[first_editor])
  end

  it "renders nothing when every editor is excluded" do
    component.update_setting(:excluded_users, "first_editor|second_editor")
    component.save!
    post = wiki_post_in(target_category, editors: [first_editor, second_editor])

    visit_post(post)

    expect(page).to have_css(".cooked")
    expect(page).to have_no_css(".wiki-coauthors")
  end

  it "uses the per-category wording where one is set, the default elsewhere" do
    component.update_setting(:target_categories, "")
    component.update_setting(:label, "Co-edited by")
    component.update_setting(
      :label_overrides,
      [{ "category_ids" => [target_category.id], "label" => "Co-authored by" }].to_json,
    )
    component.save!

    overridden = wiki_post_in(target_category, editors: [first_editor])
    plain = wiki_post_in(other_category, editors: [first_editor])

    visit_post(overridden)
    expect(page).to have_css(".wiki-coauthors__label", text: "Co-authored by")

    visit_post(plain)
    expect(page).to have_css(".wiki-coauthors__label", text: "Co-edited by")
  end

  it "ranks by edit count, most edits first" do
    post = wiki_post_in(
      target_category,
      editors: [first_editor, second_editor, second_editor],
    )

    visit_post(post)

    expect(page).to have_css(".wiki-coauthors")
    expect(listed_coauthors).to eq(%w[second_editor first_editor])
  end

  it "puts editors past max_avatars behind a disclosure" do
    component.update_setting(:max_avatars, 1)
    component.save!
    post = wiki_post_in(target_category, editors: [second_editor, second_editor, first_editor])

    visit_post(post)

    expect(listed_coauthors).to eq(%w[second_editor])
    expect(all_coauthors).to eq(%w[second_editor first_editor])
    expect(page).to have_css(".wiki-coauthors__more-toggle", text: "+1")

    find(".wiki-coauthors__more-toggle").click

    expect(listed_coauthors).to eq(%w[second_editor first_editor])
  end

  it "renders on a tagged wiki post in any category" do
    SiteSetting.tagging_enabled = true
    component.update_setting(:target_categories, "")
    component.update_setting(:target_tags, "wiki")
    component.save!

    post = wiki_post_in(other_category, editors: [first_editor], tags: [wiki_tag])

    visit_post(post)

    expect(page).to have_css(".wiki-coauthors")
    expect(listed_coauthors).to eq(%w[first_editor])
  end

  it "renders nothing on an untagged wiki post when only tags are set" do
    SiteSetting.tagging_enabled = true
    component.update_setting(:target_categories, "")
    component.update_setting(:target_tags, "wiki")
    component.save!

    post = wiki_post_in(other_category, editors: [first_editor])

    visit_post(post)

    expect(page).to have_css(".cooked")
    expect(page).to have_no_css(".wiki-coauthors")
  end

  it "treats categories and tags as a union" do
    SiteSetting.tagging_enabled = true
    component.update_setting(:target_tags, "wiki")
    component.save!

    by_category = wiki_post_in(target_category, editors: [first_editor])
    by_tag = wiki_post_in(other_category, editors: [first_editor], tags: [wiki_tag])

    visit_post(by_category)
    expect(page).to have_css(".wiki-coauthors")

    visit_post(by_tag)
    expect(page).to have_css(".wiki-coauthors")
  end

  it "renders nothing on an unedited wiki post" do
    post = wiki_post_in(target_category)

    visit_post(post)

    expect(page).to have_css(".cooked")
    expect(page).to have_no_css(".wiki-coauthors")
  end

  it "renders nothing on a non-wiki post, edited or not" do
    post = wiki_post_in(target_category, editors: [first_editor], wiki: false)

    visit_post(post)

    expect(page).to have_css(".cooked")
    expect(page).to have_no_css(".wiki-coauthors")
  end

  it "renders nothing outside the target categories" do
    post = wiki_post_in(other_category, editors: [first_editor])

    visit_post(post)

    expect(page).to have_css(".cooked")
    expect(page).to have_no_css(".wiki-coauthors")
  end

  it "renders in every category when no target category is set" do
    component.update_setting(:target_categories, "")
    component.save!
    post = wiki_post_in(other_category, editors: [first_editor])

    visit_post(post)

    expect(page).to have_css(".wiki-coauthors")
    expect(listed_coauthors).to eq(%w[first_editor])
  end

  it "credits anonymous visitors too, without the public edit history setting" do
    SiteSetting.edit_history_visible_to_public = false
    post = wiki_post_in(target_category, editors: [first_editor])

    visit_post(post)

    expect(page).to have_css(".wiki-coauthors")
    expect(listed_coauthors).to eq(%w[first_editor])
  end
end
